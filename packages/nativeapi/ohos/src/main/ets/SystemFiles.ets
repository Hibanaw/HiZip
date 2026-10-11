import { common, Want, wantConstant } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import { fileManagerService } from '@kit.FileManagerServiceKit';

export class SystemFiles {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async icon(name: string, directory: boolean): Promise<Uint8Array> {
    // getFileIcon supports file UTDs, not general.folder. Unknown UTDs can
    // return the generic document icon rather than reporting an error.
    if (directory) return this.resourceIcon(-1, 'ohos_ic_normal_white_grid_folder');
    const extension = name.substring(name.lastIndexOf('.')).toLowerCase();
    const type = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(extension);
    const resource = await fileManagerService.getFileIcon(type);
    if (typeof resource === 'string') {
      const encoded = resource.startsWith('data:') ? resource.substring(resource.indexOf(',') + 1) : resource;
      return new util.Base64Helper().decodeSync(encoded);
    }
    const symbolic = resource.params?.length ? resource.params[0] as string : '';
    const resourceName = symbolic.substring(symbolic.lastIndexOf('.') + 1);
    return this.resourceIcon(resource.id, resourceName);
  }

  private async resourceIcon(id: number, resourceName: string): Promise<Uint8Array> {
    const manager = resourceManager.getSysResourceManager();
    const descriptor = id > 0 ? manager.getDrawableDescriptor(id)
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
    return id > 0 ? manager.getMediaContent(id) : manager.getMediaByName(resourceName);
  }

  async open(uri: string, mimeType: string, writable: boolean, application: string): Promise<void> {
    if (application !== 'system') throw new Error('Only the system open action is available.');
    const want: Want = {
      action: 'ohos.want.action.viewData', uri: uri, type: mimeType,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION |
        (writable ? wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION : 0),
    };
    await this.context.startAbility(want);
  }
}
