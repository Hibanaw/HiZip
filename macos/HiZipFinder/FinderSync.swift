import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
  override init() {
    super.init()
    // Finder also displays the menu in descendants and mounted volumes.
    FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    guard menuKind == .contextualMenuForItems,
      let urls = FIFinderSyncController.default().selectedItemURLs(),
      !urls.isEmpty, urls.allSatisfy({ $0.isFileURL }) else { return nil }
    return Self.compressionMenu()
  }

  static func compressionMenu() -> NSMenu {
    let menu = NSMenu()
    let root = NSMenuItem(title: "HiZip", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "HiZip")
    for (title, action) in [
      (NSLocalizedString("Create Archive", comment: "Finder menu"), FinderCompressionRequest.Action.create),
      (NSLocalizedString("Quick Create ZIP", comment: "Finder menu"), FinderCompressionRequest.Action.quickZip),
    ] {
      let item = NSMenuItem(title: title, action: #selector(compress(_:)), keyEquivalent: "")
      item.tag = action.menuTag
      submenu.addItem(item)
    }
    root.submenu = submenu
    menu.addItem(root)
    return menu
  }

  @objc private func compress(_ sender: NSMenuItem) {
    guard let request = FinderCompressionRequest.fromMenuAction(
      tag: sender.tag, selectedURLs: FIFinderSyncController.default().selectedItemURLs()),
      let url = request.launchURL else {
      NSLog("HiZip Finder action ignored: invalid menu tag or selection")
      return
    }
    // Use the containing app, including when launched from a development build.
    let appURL = Bundle.main.bundleURL.deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
      if let error = error { NSLog("HiZip Finder launch failed: %@", error.localizedDescription) }
    }
  }
}
