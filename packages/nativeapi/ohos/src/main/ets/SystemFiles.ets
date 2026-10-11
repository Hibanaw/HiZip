import { common, Want, wantConstant } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import { fileManagerService } from '@kit.FileManagerServiceKit';

export class SystemFiles {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async icon(name: string, directory: boolean): Promise<Uint8Array> {
    const extension = name.substring(name.lastIndexOf('.')).toLowerCase();
    const type = directory ? 'general.folder' : uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(extension);
    const resource = await fileManagerService.getFileIcon(type);
    if (typeof resource === 'string') {
      const encoded = resource.startsWith('data:') ? resource.substring(resource.indexOf(',') + 1) : resource;
      return new util.Base64Helper().decodeSync(encoded);
    }
    const manager = resourceManager.getSysResourceManager();
    const symbolic = resource.params?.length ? resource.params[0] as string : '';
    const resourceName = symbolic.substring(symbolic.lastIndexOf('.') + 1);
    const descriptor = resource.id > 0 ? manager.getDrawableDescriptor(resource.id)
      : manager.getDrawableDescriptorByName(resourceName);
    if (descriptor) {
      const packer = image.createImagePacker();
      try {
        return new Uint8Array(await packer.packToData(descriptor.getPixelMap(),
          { format: 'image/png', quality: 100 }));
      } finally {
        await packer.release();
      }
    }
    return resource.id > 0 ? manager.getMediaContent(resource.id) : manager.getMediaByName(resourceName);
  }

  async open(path: string, mimeType: string, writable: boolean, application: string): Promise<void> {
    if (application !== 'system') throw new Error('Only the system open action is available.');
    const want: Want = {
      action: 'ohos.want.action.viewData', uri: fileUri.getUriFromPath(path), type: mimeType,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION |
        (writable ? wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION : 0),
    };
    // Editors such as WPS save through a sibling temporary file followed by
    // rename. Sharing only the file creates a file bind mount, which cannot be
    // replaced. Mount its dedicated extraction directory after the file instead.
    // Never grant the whole cache, an archive cache, or an imported document's
    // directory: only ArchiveService's one-entry editing workspace is eligible.
    const relative = path.substring(this.context.cacheDir.length);
    if (writable && path.startsWith(this.context.cacheDir + '/') &&
        /^\/hizip-[a-zA-Z0-9]+\/archive-[a-zA-Z0-9]+\/file-[a-zA-Z0-9]+\/[^/]+$/.test(relative) &&
        !relative.split('/').some((part: string) => part === '.' || part === '..' || part.includes('\u0000'))) {
      want.parameters = {
        'ability.params.stream': [fileUri.getUriFromPath(path),
          fileUri.getUriFromPath(path.substring(0, path.lastIndexOf('/')))],
      };
    }
    await this.context.startAbility(want);
  }
}
