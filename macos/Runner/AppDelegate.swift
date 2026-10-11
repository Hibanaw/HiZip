import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingArchives: [String] = []
  private var archiveListenerReady = false
  private var pendingCompression: [FinderCompressionRequest] = []
  private var deliveredRequests: [UUID] = []
  private var deliveringCompression = false

  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(archiveReady),
      name: Notification.Name("HiZipArchiveListenerReady"), object: nil)
  }

  @objc private func archiveReady() {
    archiveListenerReady = true
    deliverArchives()
    deliverCompression()
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    pendingArchives.append(contentsOf: filenames)
    deliverArchives()
    sender.reply(toOpenOrPrint: .success)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.isFileURL {
        pendingArchives.append(url.path)
      } else if let request = FinderCompressionRequest.decode(url),
        !deliveredRequests.contains(request.id) {
        deliveredRequests.append(request.id)
        if deliveredRequests.count > 128 { deliveredRequests.removeFirst() }
        pendingCompression.append(request)
      }
    }
    deliverArchives()
    deliverCompression()
  }

  private func deliverCompression() {
    guard archiveListenerReady, !deliveringCompression, !pendingCompression.isEmpty,
      let window = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first,
      let controller = window.contentViewController as? FlutterViewController else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    deliveringCompression = true
    let request = pendingCompression.removeFirst()
    let channel = FlutterMethodChannel(name: "dev.hizip/native_files", binaryMessenger: controller.engine.binaryMessenger)
    channel.invokeMethod("compressFiles", arguments: request.arguments) { [weak self] result in
      if let error = result as? FlutterError { NSLog("HiZip compression request failed: %@", error.message ?? error.code) }
      self?.deliveringCompression = false
      self?.deliverCompression()
    }
  }

  private func deliverArchives() {
    guard archiveListenerReady,
      let window = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first,
      let controller = window.contentViewController as? FlutterViewController else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    let channel = FlutterMethodChannel(name: "dev.hizip/native_files", binaryMessenger: controller.engine.binaryMessenger)
    let paths = pendingArchives
    pendingArchives.removeAll()
    for path in paths { channel.invokeMethod("openArchive", arguments: path) }
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let window = sender.windows.compactMap({ $0 as? MainFlutterWindow }).first else { return .terminateNow }
    window.prepareForClose { success in sender.reply(toApplicationShouldTerminate: success) }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
