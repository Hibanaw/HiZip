import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import {
  FlutterPlugin, FlutterPluginBinding, AbilityAware, AbilityPluginBinding,
  MethodCall, MethodCallHandler, MethodResult, MethodChannel, EventChannel,
} from '@ohos/flutter_ohos';

import { WindowInsets } from './WindowInsets';

// Public document URIs stay here. C/FFI and Dart receive private local paths only.
export default class NativeApiPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private saves: Map<string, string> = new Map();
  private directories: Map<string, string> = new Map();
  private channel: MethodChannel | null = null;
  private insets: WindowInsets | null = null;
  private insetsChannel: EventChannel | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  getUniqueClassName(): string { return 'NativeApiPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'nativeapi/hizip');
    this.channel.setMethodCallHandler(this);
    this.insets = new WindowInsets(binding.getFlutterEngine());
    this.insetsChannel = new EventChannel(binding.getBinaryMessenger(), 'nativeapi/hizip/windowInsets');
    this.insetsChannel.setStreamHandler(this.insets);
  }
  onDetachedFromEngine(): void {
    this.insets?.detach();
    this.insetsChannel?.setStreamHandler(null);
    this.insetsChannel = null;
    this.insets = null;
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.saves.clear();
    this.directories.clear();
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityContext = binding.getAbility().context;
    this.insets?.attach(this.abilityContext);
  }
  onDetachedFromAbility(): void {
    this.insets?.detach();
    this.abilityContext = null;
    this.saves.clear();
    this.directories.clear();
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

  private localPath(call: MethodCall): string {
    const path = call.argument('path') as string;
    if (!path.startsWith(this.context.filesDir + '/') &&
        !path.startsWith(this.context.cacheDir + '/')) {
      throw new Error('Only application sandbox files can be exported.');
    }
    if (path.split('/').includes('..')) throw new Error('Invalid file path.');
    return path;
  }

  private name(uri: string): string {
    const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
    if (!name || name === '.' || name === '..' || name.includes('/') || name.includes('\\')) {
      throw new Error('Invalid document name.');
    }
    return name;
  }

  private async workspace(): Promise<string> {
    const dir = this.context.filesDir + '/imports/' + Date.now() + '-' + Math.floor(Math.random() * 1000000);
    await fs.mkdir(dir, true);
    return dir;
  }

  private async copy(source: string, destination: string): Promise<void> {
    const input = await fs.open(source, fs.OpenMode.READ_ONLY);
    try {
      const output = await fs.open(destination, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try { await fs.copyFile(input.fd, output.fd); }
      finally { await fs.close(output); }
    } finally { await fs.close(input); }
  }

  private async validateTree(source: string): Promise<void> {
    for (const name of await fs.listFile(source)) {
      const path = source + '/' + name;
      const stat = await fs.lstat(path);
      if (stat.isDirectory()) await this.validateTree(path);
      else if (!stat.isFile()) throw new Error('Symbolic links and special files cannot be exported.');
    }
  }

  private async dispatch(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'windowInsets':
        result.success(await this.insets?.current()); return;
      case 'hostInfo': {
        const capabilities: string[] = ['documents', 'preferences', 'cacheDirectory', 'windowState'];
        if (canIUse('SystemCapability.Window.SessionManager')) capabilities.push('windowControl');
        result.success({ deviceType: deviceInfo.deviceType, apiVersion: deviceInfo.sdkApiVersion, capabilities: capabilities });
        return;
      }
      case 'windowState': {
        const host = await window.getLastWindow(this.context);
        const rect = host.getWindowProperties().windowRect;
        result.success({ x: rect.left, y: rect.top, width: rect.width, height: rect.height, status: host.getWindowStatus() });
        return;
      }
      case 'configureWindow': {
        const host = await window.getLastWindow(this.context);
        const title = call.argument('title') as string | null;
        if (title !== null) await host.setWindowTitle(title);
        const minWidth = call.argument('minWidth') as number | null;
        const minHeight = call.argument('minHeight') as number | null;
        if (minWidth !== null || minHeight !== null) {
          const limits: window.WindowLimits = {};
          if (minWidth !== null) limits.minWidth = minWidth;
          if (minHeight !== null) limits.minHeight = minHeight;
          await host.setWindowLimits(limits);
        }
        result.success(null);
        return;
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
      case 'openFiles': {
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = 100;
        const uris = await new picker.DocumentViewPicker(this.context).select(options);
        const paths: string[] = [];
        for (const uri of uris) {
          // Separate roots retain original names, including same-named documents.
          const path = await this.workspace() + '/' + this.name(uri);
          await this.copy(uri, path);
          paths.push(path);
        }
        result.success(paths);
        return;
      }
      case 'saveLocation': {
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [call.argument('name') as string];
        const uris = await new picker.DocumentViewPicker(this.context).save(options);
        if (uris.length === 0) { result.success(null); return; }
        const path = await this.workspace() + '/' + this.name(uris[0]);
        this.saves.set(path, uris[0]);
        result.success(path);
        return;
      }
      case 'finishSave': {
        const path = this.localPath(call);
        const uri = this.saves.get(path);
        if (!uri) throw new Error('No authorized save location for this file.');
        await this.copy(path, uri);
        this.saves.delete(path);
        result.success(null);
        return;
      }
      case 'directoryLocation': {
        const options = new picker.DocumentSelectOptions();
        options.selectMode = picker.DocumentSelectMode.FOLDER;
        options.maxSelectNumber = 1;
        const uris = await new picker.DocumentViewPicker(this.context).select(options);
        if (uris.length === 0) { result.success(null); return; }
        const root = await this.workspace();
        this.directories.set(root, uris[0]);
        result.success(root);
        return;
      }
      case 'finishDirectory': {
        const root = call.argument('root') as string;
        const path = this.localPath(call);
        const uri = this.directories.get(root);
        if (!uri || !path.startsWith(root + '/')) throw new Error('Invalid export location.');
        const target = uri + '/' + encodeURIComponent(this.name(path));
        await this.validateTree(path);
        // mkdir accepts sandbox paths only; copy supports authorized document URIs.
        if (await fs.access(target)) throw new Error('Export directory already exists.');
        await fs.copy(fileUri.getUriFromPath(path), target);
        this.directories.delete(root);
        result.success(target);
        return;
      }
      case 'exportFile': {
        const path = this.localPath(call);
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [this.name(path)];
        const uris = await new picker.DocumentViewPicker(this.context).save(options);
        if (uris.length === 0) { result.success(false); return; }
        await this.copy(path, uris[0]);
        result.success(true);
        return;
      }
      default: result.notImplemented();
    }
  }
}
