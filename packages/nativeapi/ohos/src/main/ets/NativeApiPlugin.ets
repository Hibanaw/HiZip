import { common, Want, AbilityConstant } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { preferences, uniformTypeDescriptor } from '@kit.ArkData';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import {
  FlutterPlugin, FlutterPluginBinding, AbilityAware, AbilityPluginBinding,
  MethodCall, MethodCallHandler, MethodResult, MethodChannel, EventChannel, FlutterAbility, NewWantListener,
} from '@ohos/flutter_ohos';

import { WindowInsets } from './WindowInsets';
import { HostWindow } from './HostWindow';
import { SystemFiles } from './SystemFiles';
import { DocumentStore, DocumentLocation } from './DocumentStore';

// UI selections include their system URI; C/FFI only receives private working paths.
export default class NativeApiPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler, NewWantListener {
  private binding: AbilityPluginBinding | null = null;
  private pendingUris: Want[] = [];
  private documents: DocumentStore = new DocumentStore(() => this.workspace());
  private saves: Map<string, string> = new Map();
  private freshSaves: Set<string> = new Set();
  private directories: Map<string, string> = new Map();
  private channel: MethodChannel | null = null;
  private insets: WindowInsets | null = null;
  private insetsChannel: EventChannel | null = null;
  private hostWindow: HostWindow | null = null;
  private windowChannel: EventChannel | null = null;
  private closeChannel: MethodChannel | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  getUniqueClassName(): string { return 'NativeApiPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'nativeapi/hizip');
    this.channel.setMethodCallHandler(this);
    this.insets = new WindowInsets(binding.getFlutterEngine());
    this.insetsChannel = new EventChannel(binding.getBinaryMessenger(), 'nativeapi/hizip/windowInsets');
    this.insetsChannel.setStreamHandler(this.insets);
    this.closeChannel = new MethodChannel(binding.getBinaryMessenger(), 'nativeapi/hizip/windowClose');
    this.hostWindow = new HostWindow(this.closeChannel);
    this.windowChannel = new EventChannel(binding.getBinaryMessenger(), 'nativeapi/hizip/windowState');
    this.windowChannel.setStreamHandler(this.hostWindow);
  }
  onDetachedFromEngine(): void {
    this.hostWindow?.detach();
    this.windowChannel?.setStreamHandler(null);
    this.windowChannel = null;
    this.hostWindow = null;
    this.closeChannel = null;
    this.insets?.detach();
    this.insetsChannel?.setStreamHandler(null);
    this.insetsChannel = null;
    this.insets = null;
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.documents.clear();
    this.saves.clear();
    this.freshSaves.clear();
    this.directories.clear();
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.binding = binding;
    binding.addOnNewWantListener(this);
    this.receiveWant((binding.getAbility() as FlutterAbility).getWant());
    this.abilityContext = binding.getAbility().context;
    this.insets?.attach(this.abilityContext);
    this.hostWindow?.attach(this.abilityContext);
  }
  onDetachedFromAbility(): void {
    this.binding?.removeOnNewWantListener(this);
    this.binding = null;
    this.hostWindow?.detach();
    this.insets?.detach();
    this.abilityContext = null;
    this.documents.clear();
    this.saves.clear();
    this.freshSaves.clear();
    this.directories.clear();
  }
  onNewWant(want: Want, _launchParams: AbilityConstant.LaunchParam): void {
    this.receiveWant(want);
    this.channel?.invokeMethod('openFilesChanged', null);
  }
  private receiveWant(want: Want): void {
    if (want.action === 'ohos.want.action.viewData' && want.uri?.startsWith('file://')) {
      this.pendingUris.push(want);
    }
  }

  private get context(): common.UIAbilityContext {
    if (!this.abilityContext) throw new Error('No UIAbility is attached.');
    return this.abilityContext;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.dispatch(call, result).catch((error: BusinessError) => {
      result.error('nativeapi_' + (error.code ?? 'failure'), error.message, null);
    });
  }

  private sandboxPath(path: string): string {
    if (typeof path !== 'string' || !path || path.length > 4096 || path.includes('\u0000')) {
      throw new Error('Invalid file path.');
    }
    if (!path.startsWith(this.context.filesDir + '/') &&
        !path.startsWith(this.context.cacheDir + '/')) {
      throw new Error('Only application sandbox files can be exported.');
    }
    if (path.substring(1).split('/').some((part: string) => part === '..' || part === '.' || part === '')) {
      throw new Error('Invalid file path.');
    }
    return path;
  }

  private localPath(call: MethodCall): string {
    return this.sandboxPath(call.argument('path') as string);
  }

  private suffixFilters(call: MethodCall): string[] {
    const values = call.argument('extensions') as string[] | null;
    if (!values) return [];
    if (!Array.isArray(values) || values.length > 100) throw new Error('Invalid file extensions.');
    const suffixes: string[] = [];
    values.forEach((value: string) => {
      if (typeof value !== 'string') throw new Error('Invalid file extension.');
      let suffix = value.trim().toLowerCase();
      if (!suffix) return;
      if (!suffix.startsWith('.')) suffix = '.' + suffix;
      if (!/^\.[a-z0-9]+([._-][a-z0-9]+)*$/.test(suffix)) throw new Error('Invalid file extension.');
      if (!suffixes.includes(suffix)) suffixes.push(suffix);
    });
    return suffixes.length === 0 ? [] : [suffixes.join(',')];
  }

  private name(uri: string): string {
    const segment = uri.substring(uri.lastIndexOf('/') + 1);
    const name = uri.startsWith('file://') ? decodeURIComponent(segment) : segment;
    if (!name || name === '.' || name === '..' || /[\/\\\u0000]/.test(name)) {
      throw new Error('Invalid document name.');
    }
    return name;
  }

  private documentMimeType(path: string, requested: string | null): string {
    if (requested !== null && requested !== undefined) {
      if (typeof requested !== 'string' ||
          !/^[a-zA-Z0-9!#$&^_.+-]+\/[a-zA-Z0-9!#$&^_.+-]+$/.test(requested)) {
        throw new Error('Invalid MIME type.');
      }
      return requested;
    }
    const name = this.name(path);
    const dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      try {
        const typeId = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(name.substring(dot).toLowerCase());
        const descriptor = uniformTypeDescriptor.getTypeDescriptor(typeId);
        if (descriptor && descriptor.mimeTypes.length > 0) return descriptor.mimeTypes[0];
      } catch (_) {}
    }
    return 'application/octet-stream';
  }

  private async workspace(): Promise<string> {
    const dir = this.context.filesDir + '/imports/' + Date.now() + '-' + Math.floor(Math.random() * 1000000);
    await fs.mkdir(dir, true);
    return dir;
  }

  private async directoryWritable(uri: string): Promise<boolean> {
    try { return await fs.access(new fileUri.FileUri(uri).path, fs.AccessModeType.WRITE); }
    catch (_) { return false; }
  }

  private async authorizeDirectory(uri: string): Promise<boolean> {
    if (await this.directoryWritable(uri)) return true;
    if (deviceInfo.deviceType !== '2in1') return false;
    const options = new picker.DocumentSelectOptions();
    options.defaultFilePathUri = uri;
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    options.authMode = true;
    await new picker.DocumentViewPicker(this.context).select(options);
    return this.directoryWritable(uri);
  }

  private dimension(call: MethodCall, key: string): number | null {
    const value = call.argument(key) as number | null;
    if (value === null || value === undefined) return null;
    if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > 2147483647)) {
      throw new Error('Window dimensions must be finite and positive.');
    }
    return value;
  }

  private coordinate(call: MethodCall, key: string): number {
    const value = call.argument(key) as number;
    if (!Number.isInteger(value) || value < -2147483648 || value > 2147483647) {
      throw new Error('Window coordinates must be signed 32-bit integers.');
    }
    return value;
  }

  private async copy(source: string, destination: string): Promise<void> {
    const input = await fs.open(source, fs.OpenMode.READ_ONLY);
    try {
      const targetPath = destination.startsWith('file://') ? new fileUri.FileUri(destination).path : destination;
      const output = await fs.open(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try { await fs.copyFile(input.fd, output.fd); await fs.fsync(output.fd); }
      finally { await fs.close(output); }
    } finally { await fs.close(input); }
  }

  private async publishEntry(source: string, directoryUri: string): Promise<void> {
    const target = directoryUri + '/' + encodeURIComponent(this.name(source));
    if (await fs.access(new fileUri.FileUri(target).path)) throw new Error('An exported entry already exists.');
    const stat = await fs.lstat(source);
    if (stat.isDirectory()) {
      // fs.copy(directory, existingDirectory) creates source.basename below it.
      await fs.copy(fileUri.getUriFromPath(source), directoryUri);
    } else if (stat.isFile()) {
      await this.copy(source, target);
    } else { throw new Error('Only regular files and directories can be exported.'); }
  }

  private async validateTree(source: string): Promise<void> {
    const stat = await fs.lstat(source);
    if (stat.isFile()) return;
    if (!stat.isDirectory()) throw new Error('Symbolic links and special files cannot be exported.');
    for (const name of await fs.listFile(source)) {
      await this.validateTree(source + '/' + name);
    }
  }

  private async validateExportPath(path: string): Promise<void> {
    const base = path.startsWith(this.context.filesDir + '/') ? this.context.filesDir : this.context.cacheDir;
    const parts = path.substring(base.length + 1).split('/');
    let current = base;
    for (const part of parts) {
      current += '/' + part;
      if ((await fs.lstat(current)).isSymbolicLink()) throw new Error('Symbolic links cannot be exported.');
    }
    await this.validateTree(path);
  }

  private async dispatch(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'windowInsets':
        result.success(await this.insets?.current()); return;
      case 'documentLocation': {
        const path = call.argument('path') as string;
        const saved = this.saves.get(path) ?? this.directories.get(path);
        result.success(this.documents.getLocation(path) ?? (saved ? this.documents.location(path, saved, true) : null));
        return;
      }
      case 'importDocument': {
        result.success(await this.documents.importFile(call.argument('uri') as string, call.argument('readOnly') === true));
        return;
      }
      case 'prepareDocumentWrite':
        await this.documents.prepareWrite(this.localPath(call)); result.success(null); return;
      case 'finishDocumentWrite': {
        const path = this.localPath(call);
        await this.validateExportPath(path);
        await this.documents.finishWrite(path); result.success(null); return;
      }
      case 'abortDocumentWrite':
        await this.documents.abortWrite(this.localPath(call)); result.success(null); return;
      case 'pendingOpenFiles': {
        const locations: DocumentLocation[] = [];
        while (this.pendingUris.length > 0) {
          const want = this.pendingUris[0];
          locations.push(await this.documents.importFile(want.uri!));
          this.pendingUris.shift();
        }
        result.success(locations);
        return;
      }
      case 'hostInfo': {
        const capabilities: string[] = ['documents', 'openWithDefault', 'preferences', 'cacheDirectory', 'supportDirectory', 'windowState', 'windowEvents'];
        if (canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) capabilities.push('directoryImport');
        if (canIUse('SystemCapability.Window.SessionManager')) capabilities.push('windowControl');
        result.success({ deviceType: deviceInfo.deviceType, apiVersion: deviceInfo.sdkApiVersion, capabilities: capabilities });
        return;
      }
      case 'windowState':
        result.success(await this.hostWindow?.current()); return;
      case 'configureWindow': {
        const title = call.argument('title') as string | null;
        const minWidth = this.dimension(call, 'minWidth');
        const minHeight = this.dimension(call, 'minHeight');
        const maxWidth = this.dimension(call, 'maxWidth');
        const maxHeight = this.dimension(call, 'maxHeight');
        if ((minWidth !== null && maxWidth !== null && minWidth > maxWidth) ||
            (minHeight !== null && maxHeight !== null && minHeight > maxHeight)) {
          throw new Error('Window minimum dimensions must not exceed maximum dimensions.');
        }
        const host = await window.getLastWindow(this.context);
        if (title !== null) await host.setWindowTitle(title);
        if (minWidth !== null || minHeight !== null || maxWidth !== null || maxHeight !== null) {
          const limits: window.WindowLimits = {};
          if (minWidth !== null) limits.minWidth = minWidth;
          if (minHeight !== null) limits.minHeight = minHeight;
          if (maxWidth !== null) limits.maxWidth = maxWidth;
          if (maxHeight !== null) limits.maxHeight = maxHeight;
          await host.setWindowLimits(limits);
        }
        result.success(null);
        return;
      }
      case 'setWindowDecorVisible': {
        const visible = call.argument('visible') as boolean;
        if (typeof visible !== 'boolean') throw new Error('Invalid window decoration visibility.');
        const height = call.argument('height') as number | null;
        if (height !== null && (typeof height !== 'number' || !Number.isInteger(height) || height < 37 || height > 112)) {
          throw new Error('Window decoration height must be 37–112 vp.');
        }
        const host = await window.getLastWindow(this.context);
        const previousVisible = host.getWindowDecorVisible();
        const previousHeight = height === null ? null : host.getWindowDecorHeight();
        try {
          if (height !== null) host.setWindowDecorHeight(height);
          await host.setTitleAndDockHoverShown(visible);
          host.setWindowDecorVisible(visible);
        } catch (error) {
          try {
            if (previousHeight !== null) host.setWindowDecorHeight(previousHeight);
            await host.setTitleAndDockHoverShown(previousVisible);
            host.setWindowDecorVisible(previousVisible);
          } catch (_) {}
          throw error as Error;
        }
        result.success(null);
        return;
      }
      case 'moveWindow': {
        const x = this.coordinate(call, 'x');
        const y = this.coordinate(call, 'y');
        await (await window.getLastWindow(this.context)).moveWindowTo(x, y);
        result.success(null); return;
      }
      case 'resizeWindow': {
        const width = this.coordinate(call, 'width');
        const height = this.coordinate(call, 'height');
        if (width <= 0 || height <= 0) throw new Error('Window dimensions must be positive.');
        await (await window.getLastWindow(this.context)).resize(width, height);
        result.success(null); return;
      }
      case 'minimizeWindow':
        await (await window.getLastWindow(this.context)).minimize(); result.success(null); return;
      case 'maximizeWindow':
        await (await window.getLastWindow(this.context)).maximize(window.MaximizePresentation.FOLLOW_APP_IMMERSIVE_SETTING); result.success(null); return;
      case 'restoreWindow':
        await (await window.getLastWindow(this.context)).restore(); result.success(null); return;
      case 'startMovingWindow':
        await (await window.getLastWindow(this.context)).startMoving(); result.success(null); return;
      case 'closeWindow':
        await this.context.terminateSelf(); result.success(null); return;
      case 'removePreference': {
        const store = await preferences.getPreferences(this.context, 'hizip');
        await store.delete(call.argument('key') as string);
        await store.flush();
        result.success(null);
        return;
      }

      case 'temporaryDirectory':
        result.success(this.context.cacheDir);
        return;
      case 'applicationSupportDirectory':
        result.success(this.context.filesDir);
        return;
      case 'getPreference': {
        const store = await preferences.getPreferences(this.context, 'hizip');
        const key = call.argument('key') as string;
        result.success(await store.has(key) ? await store.get(key, '') : null);
        return;
      }
      case 'setPreference': {
        const store = await preferences.getPreferences(this.context, 'hizip');
        await store.put(call.argument('key') as string, call.argument('value') as string);
        await store.flush();
        result.success(null);
        return;
      }
      case 'openFile':
      case 'openContents':
      case 'openFiles': {
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = call.method === 'openFile' ? 1 : 100;
        if (call.method === 'openContents') options.selectMode = picker.DocumentSelectMode.MIXED;
        const filters = this.suffixFilters(call);
        if (filters.length > 0) options.fileSuffixFilters = filters;
        const uris = await new picker.DocumentViewPicker(this.context).select(options);
        const paths: DocumentLocation[] = [];
        for (const uri of uris) {
          // Separate roots retain original names, including same-named documents.
          if (call.method === 'openContents' && (await fs.stat(new fileUri.FileUri(uri).path)).isDirectory()) {
            const path = await this.workspace() + '/' + this.name(uri);
            await fs.copy(uri, fileUri.getUriFromPath(path.substring(0, path.lastIndexOf('/'))));
            await this.validateTree(path);
            paths.push(this.documents.location(path, uri, false));
          } else {
            paths.push(await this.documents.importFile(uri));
          }
        }
        result.success(call.method === 'openFile' ? (paths.length === 0 ? null : paths[0]) : paths);
        return;
      }
      case 'openDirectory': {
        const options = new picker.DocumentSelectOptions();
        options.selectMode = picker.DocumentSelectMode.FOLDER;
        options.maxSelectNumber = 1;
        const uris = await new picker.DocumentViewPicker(this.context).select(options);
        if (uris.length === 0) { result.success(null); return; }
        const root = await this.workspace();
        const path = root + '/' + this.name(uris[0]);
        try {
          await fs.copy(uris[0], fileUri.getUriFromPath(root));
          await this.validateTree(path);
          result.success(this.documents.location(path, uris[0], false));
        } catch (error) {
          try { await fs.rmdir(root); } catch (_) {}
          throw error as Error;
        }
        return;
      }
      case 'saveLocation': {
        const options = new picker.DocumentSaveOptions();
        const suggestedName = call.argument('name') as string;
        if (typeof suggestedName !== 'string' || !suggestedName || suggestedName === '.' ||
            suggestedName === '..' || /[\/\\\u0000]/.test(suggestedName)) {
          throw new Error('Invalid document name.');
        }
        options.newFileNames = [suggestedName];
        const initial = call.argument('initialDirectory') as string | null;
        if (initial?.startsWith('file://')) options.defaultFilePathUri = initial;
        if (deviceInfo.sdkApiVersion >= 23) options.autoCreateEmptyFile = false;
        const filters = this.suffixFilters(call);
        if (filters.length > 0) options.fileSuffixChoices = filters;
        const uris = await new picker.DocumentViewPicker(this.context).save(options);
        if (uris.length === 0) { result.success(null); return; }
        const path = await this.workspace() + '/' + this.name(uris[0]);
        this.saves.set(path, uris[0]);
        result.success(this.documents.location(path, uris[0], true));
        return;
      }
      case 'hasDirectoryLocation': {
        result.success(this.directories.has(call.argument('path') as string)); return;
      }
      case 'directorySaveLocation': {
        const root = this.sandboxPath(call.argument('root') as string);
        const uri = this.directories.get(root);
        if (!uri) throw new Error('No authorized output directory.');
        if (!await this.authorizeDirectory(uri)) throw new Error('所选目录没有写入授权，请使用系统保存文件选择器选择保存位置。');
        const name = this.name(call.argument('name') as string);
        const dot = name.lastIndexOf('.');
        const stem = dot > 0 ? name.substring(0, dot) : name;
        const extension = dot > 0 ? name.substring(dot) : '';
        let candidate = name;
        let number = 2;
        while (await fs.access(new fileUri.FileUri(uri + '/' + encodeURIComponent(candidate)).path)) candidate = stem + ' (' + number++ + ')' + extension;
        const path = root + '/' + candidate;
        const target = uri + '/' + encodeURIComponent(candidate);
        this.saves.set(path, target);
        this.freshSaves.add(path);
        result.success(this.documents.location(path, target, true));
        return;
      }
      case 'hasSaveLocation': {
        const path = call.argument('path') as string;
        result.success(typeof path === 'string' && this.saves.has(path));
        return;
      }
      case 'finishSave': {
        const path = this.localPath(call);
        const uri = this.saves.get(path);
        if (!uri) throw new Error('No authorized save location for this file.');
        await this.validateExportPath(path);
        if (!(await fs.lstat(path)).isFile()) throw new Error('Save source must be a regular file.');
        if (this.freshSaves.has(path) && await fs.access(new fileUri.FileUri(uri).path)) {
          throw new Error('The output file already exists. Select another save location.');
        }
        if (await fs.access(new fileUri.FileUri(uri).path)) await this.documents.writeCopy(path, uri);
        else await this.copy(path, uri);
        const location = await this.documents.registerSaved(path, uri);
        this.saves.delete(path);
        this.freshSaves.delete(path);
        result.success(location);
        return;
      }
      case 'downloadDirectoryLocation': {
        const options = new picker.DocumentSaveOptions();
        options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
        const uris = await new picker.DocumentViewPicker(this.context).save(options);
        if (uris.length === 0) { result.success(null); return; }
        if (!await this.directoryWritable(uris[0])) throw new Error('下载目录没有写入授权。');
        const root = await this.workspace();
        this.directories.set(root, uris[0]);
        result.success(this.documents.location(root, uris[0], true));
        return;
      }
      case 'directoryLocation': {
        const options = new picker.DocumentSelectOptions();
        const initial = call.argument('initialDirectory') as string | null;
        if (initial?.startsWith('file://')) options.defaultFilePathUri = initial;
        options.selectMode = picker.DocumentSelectMode.FOLDER;
        options.maxSelectNumber = 1;
        const uris = await new picker.DocumentViewPicker(this.context).select(options);
        if (uris.length === 0) { result.success(null); return; }
        if (!await this.authorizeDirectory(uris[0])) throw new Error('所选目录没有写入授权，请重新选择可写的输出目录。');
        const root = await this.workspace();
        this.directories.set(root, uris[0]);
        result.success(this.documents.location(root, uris[0], true));
        return;
      }
      case 'finishDirectory': {
        const root = call.argument('root') as string;
        const path = this.localPath(call);
        const checkedRoot = this.sandboxPath(root);
        const uri = this.directories.get(checkedRoot);
        if (!uri || (path !== checkedRoot && !path.startsWith(checkedRoot + '/'))) throw new Error('Invalid export location.');
        if (!(await fs.lstat(path)).isDirectory()) throw new Error('Export source must be a directory.');
        if (path === checkedRoot) {
          await this.validateTree(path);
          const names = await fs.listFile(path);
          // Preflight all collisions before publishing any selected entries.
          for (const name of names) {
            if (await fs.access(new fileUri.FileUri(uri + '/' + encodeURIComponent(name)).path)) {
              throw new Error('An exported entry already exists: ' + name);
            }
          }
          for (const name of names) {
            const source = path + '/' + name;
            const target = uri + '/' + encodeURIComponent(name);
            await this.publishEntry(source, uri);
            if ((await fs.lstat(source)).isFile()) await this.documents.registerSaved(source, target);
          }
          this.directories.delete(checkedRoot);
          result.success(new fileUri.FileUri(uri).path);
          return;
        }
        const target = uri + '/' + encodeURIComponent(this.name(path));
        await this.validateExportPath(path);
        // mkdir accepts sandbox paths only; copy supports authorized document URIs.
        if (await fs.access(new fileUri.FileUri(target).path)) throw new Error('Export directory already exists.');
        await this.publishEntry(path, uri);
        this.directories.delete(checkedRoot);
        result.success(new fileUri.FileUri(target).path);
        return;
      }
      case 'fileIcon': {
        result.success(await new SystemFiles(this.context).icon(
          call.argument('path') as string, call.argument('directory') === true));
        return;
      }
      case 'applicationsForFile': {
        result.success([{ name: '系统默认应用', path: 'system', icon: null, default: true }]);
        return;
      }
      case 'openWith':
      case 'openWithDefault': {
        const path = this.localPath(call);
        await this.validateExportPath(path);
        if (!(await fs.lstat(path)).isFile()) throw new Error('Open source must be a regular file.');
        const writable = call.argument('writable') as boolean | null;
        if (writable !== null && writable !== undefined && typeof writable !== 'boolean') {
          throw new Error('Invalid file access mode.');
        }
        await new SystemFiles(this.context).open(path,
          this.documentMimeType(path, call.argument('mimeType') as string | null),
          writable === true, (call.argument('application') as string | null) ?? 'system');
        result.success(null);
        return;
      }
      case 'copyDocumentToUri': {
        const path = this.localPath(call);
        const uri = call.argument('uri') as string;
        if (typeof uri !== 'string' || !uri.startsWith('file://')) throw new Error('Invalid document URI.');
        await this.validateExportPath(path);
        if (!(await fs.lstat(path)).isFile()) throw new Error('Copy source must be a regular file.');
        if (await fs.access(new fileUri.FileUri(uri).path)) await this.documents.writeCopy(path, uri);
        else await this.copy(path, uri);
        result.success(null);
        return;
      }
      case 'exportFile': {
        const path = this.localPath(call);
        await this.validateExportPath(path);
        if (!(await fs.lstat(path)).isFile()) throw new Error('Export source must be a regular file.');
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [this.name(path)];
        const uris = await new picker.DocumentViewPicker(this.context).save(options);
        if (uris.length === 0) { result.success(false); return; }
        if (await fs.access(new fileUri.FileUri(uris[0]).path)) await this.documents.writeCopy(path, uris[0]);
        else await this.copy(path, uris[0]);
        result.success(true);
        return;
      }
      default: result.notImplemented();
    }
  }
}
