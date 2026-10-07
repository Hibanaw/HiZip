import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingArchives: [String] = []
  private var archiveListenerReady = false

  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(archiveReady),
      name: Notification.Name("HiZipArchiveListenerReady"), object: nil)
  }

  @objc private func archiveReady() {
    archiveListenerReady = true
    deliverArchives()
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    pendingArchives.append(contentsOf: filenames)
    deliverArchives()
    sender.reply(toOpenOrPrint: .success)
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
