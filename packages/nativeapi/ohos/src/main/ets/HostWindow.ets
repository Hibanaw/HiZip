import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { Any, EventSink, MethodChannel, MethodResult, StreamHandler } from '@ohos/flutter_ohos';

export class HostWindowState {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  status: number = 0;
  decorVisible: boolean = true;
  titleButtons: window.TitleButtonRect = { right: 0, top: 0, width: 0, height: 0 };
}

export class HostWindow implements StreamHandler {
  private context: common.UIAbilityContext | null = null;
  private host: window.Window | null = null;
  private sink: EventSink | null = null;
  private generation: number = 0;
  private closeGeneration: number = 0;
  private closeHost: window.Window | null = null;
  private closeChannel: MethodChannel;

  constructor(closeChannel: MethodChannel) { this.closeChannel = closeChannel; }

  attach(context: common.UIAbilityContext): void {
    this.context = context;
    this.watchClose();
    this.watch();
  }

  detach(): void {
    this.generation++;
    this.closeGeneration++;
    const closeHost = this.closeHost;
    this.closeHost = null;
    if (closeHost) {
      try { closeHost.off('windowWillClose', this.onWillClose); } catch (_) {}
    }
    this.unwatch();
    this.context = null;
  }

  onListen(args: Any, events: EventSink): void {
    this.sink = events;
    this.watch();
  }

  onCancel(args: Any): void {
    this.generation++;
    this.unwatch();
    this.sink = null;
  }

  async current(): Promise<HostWindowState> {
    if (!this.context) throw new Error('No UIAbility is attached.');
    return this.read(await window.getLastWindow(this.context));
  }

  private read(host: window.Window): HostWindowState {
    const rect = host.getWindowProperties().windowRect;
    const state = new HostWindowState();
    state.x = rect.left;
    state.y = rect.top;
    state.width = rect.width;
    state.height = rect.height;
    state.status = host.getWindowStatus();
    state.decorVisible = host.getWindowDecorVisible();
    state.titleButtons = host.getTitleButtonRect();
    return state;
  }

  private watch(): void {
    if (!this.context || !this.sink) return;
    const generation = ++this.generation;
    window.getLastWindow(this.context).then((host: window.Window) => {
      if (generation !== this.generation || !this.sink) return;
      this.unwatch();
      this.host = host;
      host.on('windowRectChange', this.onRect);
      host.on('windowSizeChange', this.onSize);
      host.on('windowTitleButtonRectChange', this.onTitle);
      if (deviceInfo.sdkApiVersion >= 20) host.on('windowStatusDidChange', this.onStatus);
      else host.on('windowStatusChange', this.onStatus);
      this.publish();
    }).catch((error: BusinessError) => {
      if (generation !== this.generation) return;
      this.unwatch();
      this.sink?.error('window_state', error.message, null);
    });
  }

  private onRect = (value: window.RectChangeOptions): void => { this.publish(); };
  private onSize = (value: window.Size): void => { this.publish(); };
  private onStatus = (value: window.WindowStatusType): void => { this.publish(); };
  private onTitle = (value: window.TitleButtonRect): void => { this.publish(); };

  private watchClose(): void {
    if (!this.context || deviceInfo.sdkApiVersion < 15) return;
    const generation = ++this.closeGeneration;
    window.getLastWindow(this.context).then((host: window.Window) => {
      if (generation !== this.closeGeneration) return;
      host.on('windowWillClose', this.onWillClose);
      this.closeHost = host;
    }).catch((error: BusinessError) => {
      console.error('Window close preparation unavailable: ' + error.message);
    });
  }

  private onWillClose = (): Promise<boolean> => new Promise<boolean>((resolve) => {
    const result: MethodResult = {
      success: (value: Any): void => { resolve(value !== true); },
      error: (code: string, message: string, details: Any): void => { resolve(true); },
      notImplemented: (): void => { resolve(false); },
    };
    this.closeChannel.invokeMethod('prepareWindowClose', null, result);
  });

  private publish(): void {
    if (!this.host || !this.sink) return;
    try {
      this.sink.success(this.read(this.host));
    } catch (error) {
      this.sink.error('window_state', (error as BusinessError).message, null);
    }
  }

  private unwatch(): void {
    const host = this.host;
    this.host = null;
    if (!host) return;
    try { host.off('windowRectChange', this.onRect); } catch (_) {}
    try { host.off('windowSizeChange', this.onSize); } catch (_) {}
    try { host.off('windowTitleButtonRectChange', this.onTitle); } catch (_) {}
    try {
      if (deviceInfo.sdkApiVersion >= 20) host.off('windowStatusDidChange', this.onStatus);
      else host.off('windowStatusChange', this.onStatus);
    } catch (_) {}
  }
}
