import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, FlutterManager, EventSink, StreamHandler, Any } from '@ohos/flutter_ohos';

export class WindowInsetsData {
  ready: boolean = false;
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  status: number = 0;
}

// Compute overlap with the actual Flutter surface, not the entire window.
// A decorated floating window already excludes its native title bar.
export class WindowInsets implements StreamHandler {
  private engine: FlutterEngine;
  private context: common.UIAbilityContext | null = null;
  private host: window.Window | null = null;
  private sink: EventSink | null = null;
  private timer: number = -1;
  private generation: number = 0;
  constructor(engine: FlutterEngine) { this.engine = engine; }

  attach(context: common.UIAbilityContext): void {
    this.context = context;
    if (this.sink) this.watch();
  }
  detach(): void {
    this.generation++;
    this.unwatch();
    this.context = null;
  }
  onListen(args: Any, events: EventSink): void {
    this.sink = events;
    this.watch();
  }
  onCancel(args: Any): void {
    this.generation++;
    this.sink = null;
    this.unwatch();
  }
  private watch(): void {
    if (!this.context || !this.sink) return;
    const generation = ++this.generation;
    window.getLastWindow(this.context).then((host: window.Window) => {
      if (generation !== this.generation || !this.sink) return;
      this.unwatch();
      this.host = host;
      host.on('avoidAreaChange', this.onAvoidArea);
      host.on('windowStatusChange', this.onStatus);
      host.on('windowSizeChange', this.onSize);
      host.on('windowTitleButtonRectChange', this.onTitle);
      this.schedule();
    }).catch((error: BusinessError) => { this.sink?.error('window_insets', error.message, null); });
  }
  private onAvoidArea = (value: window.AvoidAreaOptions): void => { this.schedule(); };
  private onStatus = (value: window.WindowStatusType): void => { this.schedule(); };
  private onSize = (value: window.Size): void => { this.schedule(); };
  private onTitle = (value: window.TitleButtonRect): void => { this.schedule(); };
  private schedule(): void {
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = -1;
      if (!this.host || !this.sink) return;
      try { this.sink.success(this.read(this.host)); }
      catch (error) { this.sink.error('window_insets', (error as BusinessError).message, null); }
    }, 32);
  }
  private unwatch(): void {
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    if (!this.host) return;
    this.host.off('avoidAreaChange', this.onAvoidArea);
    this.host.off('windowStatusChange', this.onStatus);
    this.host.off('windowSizeChange', this.onSize);
    this.host.off('windowTitleButtonRectChange', this.onTitle);
    this.host = null;
  }
  async current(): Promise<WindowInsetsData> {
    if (!this.context) return new WindowInsetsData();
    return this.read(await window.getLastWindow(this.context));
  }
  private read(host: window.Window): WindowInsetsData {
    const result = new WindowInsetsData();
    result.status = host.getWindowStatus();
    const ui = host.getUIContext();
    const shell = this.engine.getFlutterNapi().nativeShellHolderId;
    let id = '';
    FlutterManager.getInstance().getFlutterViewList().forEach((view) => {
      if (view.isSameEngineShellHolderId(shell)) id = view.getId();
    });
    const node = ui.getFrameNodeById(id);
    if (!node) return result;
    const position = node.getPositionToWindow();
    const size = node.getMeasuredSize();
    if (size.width <= 0 || size.height <= 0) return result;
    const x = ui.vp2px(position.x);
    const y = ui.vp2px(position.y);
    const types: window.AvoidAreaType[] = [window.AvoidAreaType.TYPE_SYSTEM,
      window.AvoidAreaType.TYPE_CUTOUT, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR];
    const overlap = (start: number, length: number, surfaceStart: number,
      surfaceLength: number): number => {
      const end = start + length;
      const surfaceEnd = surfaceStart + surfaceLength;
      return Math.max(0, Math.min(end, surfaceEnd) - Math.max(start, surfaceStart));
    };
    for (const type of types) {
      const area = host.getWindowAvoidArea(type);
      if (!area.visible && type !== window.AvoidAreaType.TYPE_CUTOUT) continue;
      if (area.topRect.height > 0) {
        result.top = Math.max(result.top, overlap(area.topRect.top, area.topRect.height, y, size.height));
      }
      if (area.bottomRect.height > 0) {
        result.bottom = Math.max(result.bottom, overlap(area.bottomRect.top, area.bottomRect.height, y, size.height));
      }
      if (area.leftRect.width > 0) {
        result.left = Math.max(result.left, overlap(area.leftRect.left, area.leftRect.width, x, size.width));
      }
      if (area.rightRect.width > 0) {
        result.right = Math.max(result.right, overlap(area.rightRect.left, area.rightRect.width, x, size.width));
      }
    }
    result.top = Math.min(size.height, result.top);
    result.bottom = Math.min(size.height, result.bottom);
    result.left = Math.min(size.width, result.left);
    result.right = Math.min(size.width, result.right);
    result.ready = true;
    return result;
  }
}
