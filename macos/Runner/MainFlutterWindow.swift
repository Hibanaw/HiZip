import Cocoa
import FlutterMacOS
import hizip_native
import desktop_multi_window

private final class AuxiliaryDialogModalHost: NSObject, NSWindowDelegate {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private weak var previousDelegate: NSWindowDelegate?
  private var session: NSApplication.ModalSession?
  private var timer: Timer?

  init(channel: FlutterMethodChannel) { self.channel = channel }

  func begin(_ window: NSWindow) {
    if session != nil { return }
    self.window = window
    if window.delegate !== self { previousDelegate = window.delegate }
    window.delegate = self
    session = NSApp.beginModalSession(for: window)
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self = self, let session = self.session else { return }
      if self.window?.isVisible != true {
        self.end()
        self.channel.invokeMethod("closeRequested", arguments: nil)
        return
      }
      NSApp.runModalSession(session)
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func end() {
    timer?.invalidate()
    timer = nil
    if let session = session { NSApp.endModalSession(session) }
    session = nil
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    channel.invokeMethod("closeRequested", arguments: nil)
    return false
  }

  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    if previousDelegate?.responds(to: selector) == true { return previousDelegate }
    return super.forwardingTarget(for: selector)
  }
}

private final class TrafficLightTitlebar: NSTitlebarAccessoryViewController {
  private weak var host: NSWindow?

  init(window: NSWindow) {
    host = window
    super.init(nibName: nil, bundle: nil)
    // Reserve the native titlebar band too, so the buttons' hit areas and
    // tracking regions remain inside the titlebar when they move down.
    view = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 49))
    layoutAttribute = .left
    window.addTitlebarAccessoryViewController(self)
    for notification in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(centerButtons), name: notification, object: window)
    }
    DispatchQueue.main.async { [weak self] in self?.centerButtons() }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func centerButtons() {
    guard let window = host, !window.styleMask.contains(.fullScreen),
      let frameView = window.contentView?.superview else { return }
    guard let close = window.standardWindowButton(.closeButton), let closeParent = close.superview else { return }
    let closeFrame = closeParent.convert(close.frame, to: frameView)
    let shift = frameView.bounds.minX + 49 / 2.0 - closeFrame.midX
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
      let current = parent.convert(button.frame, to: frameView)
      let center = parent.convert(NSPoint(x: current.midX + shift, y: frameView.bounds.maxY - 49 / 2.0), from: frameView)
      var origin = button.frame.origin
      origin.x = center.x - button.frame.width / 2
      origin.y = center.y - button.frame.height / 2
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
  }
}

class MainFlutterWindow: HizipPreviewWindow {
  private var cleanupComplete = false, preparingClose = false
  private var closeCallbacks: [(Bool) -> Void] = []

  func prepareForClose(_ completion: @escaping (Bool) -> Void) {
    if cleanupComplete { DispatchQueue.main.async { completion(true) }; return }
    closeCallbacks.append(completion)
    if preparingClose { return }
    preparingClose = true
    guard let controller = contentViewController as? FlutterViewController else {
      finishCleanup(true); return
    }
    let channel = FlutterMethodChannel(name: "dev.hizip/native_files", binaryMessenger: controller.engine.binaryMessenger)
    channel.invokeMethod("prepareWindowClose", arguments: nil) { [weak self] result in
      self?.finishCleanup(!(result is FlutterError))
    }
  }

  private func finishCleanup(_ success: Bool) {
    cleanupComplete = success
    preparingClose = false
    let callbacks = closeCallbacks
    closeCallbacks.removeAll()
    for callback in callbacks { callback(success) }
  }

  override func performClose(_ sender: Any?) {
    prepareForClose { [weak self] success in
      if success { self?.closeAfterCleanup(sender) }
    }
  }

  private func closeAfterCleanup(_ sender: Any?) { super.performClose(sender) }

  override func awakeFromNib() {
    let windowFrame = self.frame
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 1280, height: 820), display: true)
    self.minSize = NSSize(width: 390, height: 500)
    self.center()
    _ = TrafficLightTitlebar(window: self)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      let channel = FlutterMethodChannel(name: "dev.hizip/task-window-host", binaryMessenger: controller.engine.binaryMessenger)
      let modalHost = AuxiliaryDialogModalHost(channel: channel)
      channel.setMethodCallHandler { [weak controller] call, result in
        guard let window = controller?.view.window else {
          result(FlutterError(code: "no_window", message: "Task window is unavailable", details: nil)); return
        }
        switch call.method {
        case "nativePointer": result(Int(bitPattern: Unmanaged.passUnretained(window).toOpaque()))
        case "beginModal":
          modalHost.begin(window)
          window.makeFirstResponder(controller?.view)
          result(nil)
        case "endModal": modalHost.end(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }

    super.awakeFromNib()
  }
}
