import Cocoa
import FlutterMacOS
import Quartz
import UniformTypeIdentifiers
import CoreServices

// Quick Look discovers its controller through the host window's responder chain.
open class HizipPreviewWindow: NSWindow {
  fileprivate var archivePreview: ArchivePreviewResponder?
  fileprivate var fileCommandsEnabled = false
  fileprivate var fileCommand: ((String) -> Void)?
  public override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if fileCommandsEnabled, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
       let key = event.charactersIgnoringModifiers?.lowercased(),
       let command = ["c": "copy", "v": "paste", "a": "selectAll"][key] {
      fileCommand?(command)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    archivePreview?.acceptsPreviewPanelControl(panel) ?? false
  }
  public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    archivePreview?.beginPreviewPanelControl(panel)
  }
  public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    archivePreview?.endPreviewPanelControl(panel)
  }
}

private final class ArchivePreviewResponder: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  var item: NSURL?
  var enabled = false
  var navigate: ((Int) -> Void)?

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { enabled && item != nil }
  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = self
    panel.delegate = self
  }
  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = nil
    panel.delegate = nil
  }
  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { item == nil ? 0 : 1 }
  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem { item! }
  func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
    guard event.type == .keyDown else { return false }
    switch event.keyCode {
    case 126: navigate?(-1); return true
    case 125: navigate?(1); return true
    case 49: panel.orderOut(nil); return true
    default: return false
    }
  }
}

private final class ArchiveDragSource: NSObject, NSDraggingSource {
  var movable = false
  var ended: ((NSDragOperation) -> Void)?
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    context == .withinApplication && movable ? [.copy, .move] : .copy
  }
  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    ended?(operation)
  }
}

public class HizipNativePlugin: NSObject, FlutterPlugin, NSMenuItemValidation {
  private let channel: FlutterMethodChannel
  private weak var viewController: NSViewController?
  private let preview = ArchivePreviewResponder()
  private var iconCache: [String: Data] = [:]
  private let dragSource = ArchiveDragSource()
  private let fileQueue = DispatchQueue(label: "dev.hizip.file-operations", qos: .userInitiated)
  private var dragEvent: NSEvent?
  private var eventMonitor: Any?
  private var keyMonitor: Any?
  private var preparedDragPaths: [String] = []
  private var preparedDragFrame = NSRect.zero
  private var dragOrigin = NSPoint.zero
  private var dragArmed = false
  private var dragInProgress = false
  private var menuBusy = false, menuHasDocument = false
  private var menuWritable = false, menuHasSelection = false
  private var menuEncoding = "auto"
  private var encodingMenu: NSMenu?
  private var recentMenu: NSMenu?
  private var nameAlert: NSAlert?

  private var menuLanguage = "zh", menusConfigured = false
  private var menuTranslations: [String: String] = [:]
  private var menuSources: [String: String] = [:]
  private func sourceTitle(_ text: String) -> String {
    menuSources[text] ?? text
  }
  private func localized(_ text: String) -> String {
    let source = sourceTitle(text)
    if let translated = menuTranslations[source] {
      menuSources[translated] = source
      return translated
    }
    let titles = ["新建文件夹…": "New Folder…", "新建空白文档…": "New Blank Document…", "删除…": "Delete…", "名称": "Name", "创建": "Create", "取消": "Cancel", "设置…": "Settings…", "文件": "File", "打开…": "Open…", "最近打开": "Open Recent", "暂无最近打开的文件": "No Recent Files", "清除菜单": "Clear Menu", "创建 ZIP…": "Create ZIP…", "创建压缩包": "Create Archive", "解压…": "Extract…", "编码": "Encoding", "自动识别": "Auto Detect", "简体中文（GB18030 / GBK）": "Chinese Simplified (GB18030 / GBK)", "繁体中文（Big5）": "Chinese Traditional (Big5)", "日文（Shift-JIS）": "Japanese (Shift-JIS)", "韩文（CP949）": "Korean (CP949)", "西欧（Windows-1252）": "Western European (Windows-1252)", "关闭窗口": "Close Window", "关闭标签页": "Close Tab", "显示": "View", "列表视图": "List View", "图标视图": "Icon View", "多栏视图": "Column View", "画廊视图": "Gallery View", "预览栏": "Preview Pane", "编辑": "Edit", "撤销": "Undo", "重做": "Redo", "剪切": "Cut", "复制": "Copy", "粘贴": "Paste", "全选": "Select All", "窗口": "Window", "最小化": "Minimize", "缩放": "Zoom", "全部置于最前": "Bring All to Front", "帮助": "Help"]
    return menuLanguage == "en" ? (titles[text] ?? text) : (titles.first(where: { $0.value == text })?.key ?? text)
  }
  private func menuItem(_ title: String, _ command: String, key: String = "") -> NSMenuItem {
    let item = NSMenuItem(title: localized(title), action: #selector(menuCommand(_:)), keyEquivalent: key)
    item.target = self
    item.representedObject = command
    return item
  }
  @objc private func menuCommand(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    if command == "clearRecent" {
      NSDocumentController.shared.clearRecentDocuments(sender)
      rebuildRecentMenu()
      channel.invokeMethod("clearRecent", arguments: nil)
    } else if command.hasPrefix("recent:") {
      channel.invokeMethod("openArchive", arguments: String(command.dropFirst(7)))
    } else {
      channel.invokeMethod("fileCommand", arguments: command)
    }
  }
  @objc private func editCommand(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    if let host = NSApp.keyWindow as? HizipPreviewWindow, host.fileCommandsEnabled {
      if !menuBusy { channel.invokeMethod("fileCommand", arguments: command) }
    } else {
      NSApp.sendAction(NSSelectorFromString("\(command):"), to: nil, from: sender)
    }
  }
  public func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if item.action == #selector(closeCurrent(_:)) {
      if nameAlert != nil { return true }
      let closesTab = NSApp.keyWindow === viewController?.view.window && menuHasDocument
      item.title = localized(closesTab ? "关闭标签页" : "关闭窗口")
      return !closesTab || !menuBusy
    }
    guard let command = item.representedObject as? String else { return true }
    if command == "settings" || command == "clearRecent" { return true }
    if ["newFolder", "newDocument", "delete"].contains(command) {
      if command == "delete", let host = NSApp.keyWindow as? HizipPreviewWindow,
         !host.fileCommandsEnabled { return false }
      return NSApp.keyWindow === viewController?.view.window && !menuBusy && menuHasDocument && menuWritable && (command != "delete" || menuHasSelection)
    }
    if command.hasPrefix("encoding:") { return !menuBusy && menuHasDocument }
    if ["extract", "closeArchive", "list", "grid", "columns", "gallery", "inspector"].contains(command) {
      return !menuBusy && menuHasDocument
    }
    return !menuBusy
  }
  @objc private func closeCurrent(_ sender: Any?) {
    if let alert = nameAlert, let parent = alert.window.sheetParent,
       NSApp.keyWindow === parent || NSApp.keyWindow === alert.window {
      parent.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
      return
    }
    guard let window = NSApp.keyWindow else { return }
    if window === viewController?.view.window && menuHasDocument {
      if !menuBusy { channel.invokeMethod("fileCommand", arguments: "closeArchive") }
    } else {
      window.performClose(sender)
    }
  }
  private func rebuildRecentMenu() {
    guard let menu = recentMenu else { return }
    menu.removeAllItems()
    let urls = Array(NSDocumentController.shared.recentDocumentURLs.prefix(10))
    for url in urls {
      let item = menuItem(url.lastPathComponent, "recent:\(url.path)")
      item.toolTip = url.path
      menu.addItem(item)
    }
    if urls.isEmpty { menu.addItem(NSMenuItem(title: localized("暂无最近打开的文件"), action: nil, keyEquivalent: "")) }
    menu.addItem(.separator())
    menu.addItem(menuItem("清除菜单", "clearRecent"))
  }
  private func configureMenus() {
    guard let main = NSApp.mainMenu else { return }
    menusConfigured = true
    if let appMenu = main.items.first?.submenu,
       let settings = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
      settings.title = localized("设置…")
      settings.target = self
      settings.action = #selector(menuCommand(_:))
      settings.representedObject = "settings"
    }
    if let old = main.items.first(where: { sourceTitle($0.title) == "文件" || $0.title == "File" }) { main.removeItem(old) }
    let fileMenu = NSMenu(title: localized("文件"))
    fileMenu.addItem(menuItem("打开…", "open", key: "o"))
    let recent = NSMenuItem(title: localized("最近打开"), action: nil, keyEquivalent: "")
    recentMenu = NSMenu(title: localized("最近打开"))
    recent.submenu = recentMenu
    fileMenu.addItem(recent)
    rebuildRecentMenu()
    fileMenu.addItem(.separator())
    let create = menuItem("创建 ZIP…", "create", key: "n")
    let createFormats = NSMenu(title: localized("创建压缩包"))
    for (ext, title) in [("zip", "ZIP"), ("7z", "7z"), ("tar", "TAR"), ("tar.gz", "TAR + gzip"), ("tar.bz2", "TAR + bzip2"), ("tar.xz", "TAR + xz"), ("tar.lzma", "TAR + LZMA"), ("cpio", "CPIO"), ("gz", "gzip"), ("bz2", "bzip2"), ("xz", "xz"), ("lzma", "LZMA")] {
      createFormats.addItem(menuItem(title, "create:\(ext)"))
    }
    let formats = NSMenuItem(title: localized("创建压缩包"), action: nil, keyEquivalent: "")
    formats.submenu = createFormats
    fileMenu.addItem(create)
    fileMenu.addItem(formats)
    fileMenu.addItem(menuItem("解压…", "extract", key: "e"))
    fileMenu.addItem(.separator())
    let newFolder = menuItem("新建文件夹…", "newFolder", key: "n")
    newFolder.keyEquivalentModifierMask = [.command, .shift]
    fileMenu.addItem(newFolder)
    fileMenu.addItem(menuItem("新建空白文档…", "newDocument"))
    fileMenu.addItem(menuItem("删除…", "delete", key: "\u{8}"))
    fileMenu.addItem(.separator())
    let encodingItem = NSMenuItem(title: localized("编码"), action: nil, keyEquivalent: "")
    encodingMenu = NSMenu(title: localized("编码"))
    for (code, title) in [("auto", "自动识别"), ("UTF-8", "UTF-8"), ("GB18030", "简体中文（GB18030 / GBK）"), ("BIG5", "繁体中文（Big5）"), ("CP932", "日文（Shift-JIS）"), ("CP949", "韩文（CP949）"), ("CP437", "DOS（CP437）"), ("WINDOWS-1252", "西欧（Windows-1252）")] {
      let item = menuItem(title, "encoding:\(code)")
      item.state = code == menuEncoding ? .on : .off
      encodingMenu?.addItem(item)
    }
    encodingItem.submenu = encodingMenu
    fileMenu.addItem(encodingItem)
    fileMenu.addItem(.separator())
    let close = NSMenuItem(title: localized("关闭窗口"), action: #selector(closeCurrent(_:)), keyEquivalent: "w")
    close.target = self
    fileMenu.addItem(close)
    let file = NSMenuItem(title: localized("文件"), action: nil, keyEquivalent: "")
    file.submenu = fileMenu
    main.insertItem(file, at: min(1, main.numberOfItems))
    if let edit = main.items.first(where: { sourceTitle($0.title) == "编辑" || $0.title == "Edit" })?.submenu {
      for item in edit.items {
        guard let action = item.action else { continue }
        let command = NSStringFromSelector(action).replacingOccurrences(of: ":", with: "")
        if ["copy", "paste", "selectAll"].contains(command) {
          item.target = self
          item.action = #selector(editCommand(_:))
          item.representedObject = command
        }
      }
    }
    if let viewItem = main.items.first(where: { sourceTitle($0.title) == "显示" || $0.title == "View" }), let view = viewItem.submenu {
      viewItem.title = localized("显示")
      view.title = localized("显示")
      for command in [("列表视图", "list"), ("图标视图", "grid"), ("多栏视图", "columns"), ("画廊视图", "gallery"), ("预览栏", "inspector")] {
        if let existing = view.items.first(where: { $0.representedObject as? String == command.1 }) {
          existing.title = localized(command.0)
        } else {
          view.insertItem(menuItem(command.0, command.1), at: 0)
        }
      }
    }
  }

  private init(channel: FlutterMethodChannel, viewController: NSViewController?) {
    self.channel = channel
    self.viewController = viewController
    super.init()
    preview.navigate = { [weak self] delta in self?.channel.invokeMethod("quickLookNavigate", arguments: delta) }
    dragSource.ended = { [weak self] operation in
      self?.dragInProgress = false
      self?.channel.invokeMethod("fileDragEnded", arguments: operation != [])
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let window = self?.viewController?.view.window, event.window === window,
        event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
        event.charactersIgnoringModifiers?.lowercased() == "w" else { return event }
      self?.closeCurrent(nil)
      return nil
    }
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
      guard let self = self, let view = self.viewController?.view,
        event.window === view.window else { return event }
      self.dragEvent = event
      let location = view.convert(event.locationInWindow, from: nil)
      if event.type == .leftMouseDown {
        self.dragOrigin = location
        self.dragArmed = self.preparedDragFrame.contains(location) && !self.preparedDragPaths.isEmpty
      } else if self.dragArmed && !self.preparedDragPaths.isEmpty && !self.dragInProgress &&
        hypot(location.x - self.dragOrigin.x, location.y - self.dragOrigin.y) > 8 {
        self.beginFileDrag(self.preparedDragPaths, view: view, event: event)
        return nil
      }
      return event
    }
  }
  deinit {
    if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
  }
  private func beginFileDrag(_ paths: [String], view: NSView, event: NSEvent) {
    dragInProgress = true
    dragArmed = false
    channel.invokeMethod("fileDragStarted", arguments: nil)
    let location = view.convert(event.locationInWindow, from: nil)
    let items = paths.map { path -> NSDraggingItem in
      let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: path) as NSURL)
      item.setDraggingFrame(NSRect(x: location.x - 16, y: location.y - 16, width: 32, height: 32),
        contents: NSWorkspace.shared.icon(forFile: path))
      return item
    }
    let session = view.beginDraggingSession(with: items, event: event, source: dragSource)
    session.draggingFormation = .pile
  }
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.hizip/native_files", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(HizipNativePlugin(channel: channel, viewController: registrar.viewController), channel: channel)
  }
  private func png(_ image: NSImage, pixelSize: Int = 128) -> Data? {
    let side = max(32, min(pixelSize, 1024))
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
  }
  private func installPreviewResponder() {
    guard let window = viewController?.view.window ?? NSApp.mainWindow else { return }
    if let host = window as? HizipPreviewWindow {
      host.archivePreview = preview
      return
    }
    if window.nextResponder !== preview {
      preview.nextResponder = window.nextResponder
      window.nextResponder = preview
    }
  }
  private func applicationInfo(_ url: URL, isDefault: Bool = false) -> [String: Any] {
    var info: [String: Any] = ["name": (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension,
      "path": url.path, "default": isDefault]
    if let data = png(NSWorkspace.shared.icon(forFile: url.path)) { info["icon"] = FlutterStandardTypedData(bytes: data) }
    return info
  }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "setDefaultArchiveHandler" {
      guard let identifier = Bundle.main.bundleIdentifier else {
        result(FlutterError(code: "bundle_id", message: "Application identifier is unavailable", details: nil)); return
      }
      let registration = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
      guard registration == noErr else {
        result(FlutterError(code: "registration", message: "Could not register application (\(registration))", details: nil)); return
      }
      let documents = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
      let types = Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
      var failed: [String] = []
      for type in types {
        let status = LSSetDefaultRoleHandlerForContentType(type as CFString, .all, identifier as CFString)
        if status != noErr { failed.append("\(type): \(status)") }
      }
      if failed.isEmpty { result(types.count) }
      else { result(FlutterError(code: "association", message: "Some file associations could not be changed", details: failed)) }
      return
    }
    if call.method == "configureMenus" {
      configureMenus()
      NotificationCenter.default.post(name: Notification.Name("HiZipArchiveListenerReady"), object: nil)
      result(Array(NSDocumentController.shared.recentDocumentURLs.prefix(10)).map { $0.path }); return
    }
    if call.method == "promptEntryName", let args = call.arguments as? [String: Any] {
      guard let window = viewController?.view.window else { result(nil); return }
      let alert = NSAlert()
      nameAlert = alert
      alert.messageText = args["title"] as? String ?? ""
      alert.informativeText = localized("名称")
      alert.addButton(withTitle: localized("创建"))
      alert.addButton(withTitle: localized("取消"))
      let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
      field.stringValue = args["name"] as? String ?? ""
      alert.accessoryView = field
      alert.window.initialFirstResponder = field
      alert.beginSheetModal(for: window) { [weak self] response in
        self?.nameAlert = nil
        result(response == .alertFirstButtonReturn ? field.stringValue : nil)
      }
      field.selectText(nil)
      return
    }
    if call.method == "menuState", let args = call.arguments as? [String: Any] {
      menuBusy = args["busy"] as? Bool ?? false
      menuHasDocument = args["hasDocument"] as? Bool ?? false
      menuWritable = args["writable"] as? Bool ?? false
      menuHasSelection = args["hasSelection"] as? Bool ?? false
      let encoding = args["encoding"] as? String ?? "auto"
      menuEncoding = encoding
      for item in encodingMenu?.items ?? [] {
        item.state = item.representedObject as? String == "encoding:\(encoding)" ? .on : .off
      }
      result(nil); return
    }
    if call.method == "noteRecentArchive", let args = call.arguments as? [String: Any], let path = args["path"] as? String {
      NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: path))
      rebuildRecentMenu()
      result(nil); return
    }
    if call.method == "language" {
      let payload = call.arguments as? [String: Any]
      let language = payload?["language"] as? String ?? call.arguments as? String ?? "zh"
      if let english = payload?["english"] as? [String: String] {
        for (source, title) in english { menuSources[title] = source }
      }
      menuTranslations = payload?["translations"] as? [String: String] ?? [:]
      if language != menuLanguage {
        menuLanguage = language
        if menusConfigured { configureMenus() }
      }
      for root in NSApp.mainMenu?.items ?? [] {
        if ["编辑", "窗口", "帮助", "Edit", "Window", "Help"].contains(sourceTitle(root.title)) {
          root.title = localized(root.title)
          root.submenu?.title = root.title
          for item in root.submenu?.items ?? [] { item.title = localized(item.title) }
        }
      }
      result(nil); return
    }
    if call.method == "appearance" {
      let mode = call.arguments as? String ?? "system"
      NSApp.appearance = mode == "dark" ? NSAppearance(named: .darkAqua) : mode == "light" ? NSAppearance(named: .aqua) : nil
      result(nil); return
    }
    if call.method == "replacementDirectory" || call.method == "commit" {
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "arguments", message: "Missing path", details: nil)); return
      }
      let operation = call.method
      fileQueue.async {
        do {
          let destination = URL(fileURLWithPath: path)
          if operation == "replacementDirectory" {
            let directory = try FileManager.default.url(for: .itemReplacementDirectory,
              in: .userDomainMask, appropriateFor: destination, create: true)
            DispatchQueue.main.async { result(directory.path) }
          } else {
            guard let source = args["source"] as? String else {
              DispatchQueue.main.async { result(FlutterError(code: "arguments", message: "Missing staged file", details: nil)) }; return
            }
            let staged = URL(fileURLWithPath: source)
            var coordinationError: NSError?
            var replacementError: Error?
            // Each coordinator is created and used solely on this serial worker queue.
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinated in
              do {
                if FileManager.default.fileExists(atPath: coordinated.path) {
                  _ = try FileManager.default.replaceItemAt(coordinated, withItemAt: staged)
                } else { try FileManager.default.moveItem(at: staged, to: coordinated) }
              } catch { replacementError = error }
            }
            if let error = coordinationError ?? replacementError as NSError? { throw error }
            DispatchQueue.main.async { result(nil) }
          }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "native_files", message: error.localizedDescription, details: nil)) }
        }
      }
      return
    }

    if call.method == "chooseApplication" {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.application]
      panel.directoryURL = URL(fileURLWithPath: "/Applications")
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.prompt = "打开"
      guard let window = viewController?.view.window else { result(nil); return }
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url, let self = self else { result(nil); return }
        result(self.applicationInfo(url))
      }
      return
    }
    if call.method == "prepareFileDrag" {
      guard let args = call.arguments as? [String: Any], let paths = args["paths"] as? [String],
        let frame = args["frame"] as? [Double], frame.count == 4, let view = viewController?.view else {
        result(FlutterError(code: "arguments", message: "Missing drag frame", details: nil)); return
      }
      preparedDragPaths = paths
      dragSource.movable = args["movable"] as? Bool ?? false
      preparedDragFrame = NSRect(x: frame[0], y: view.isFlipped ? frame[1] : view.bounds.height - frame[1] - frame[3], width: frame[2], height: frame[3])
      dragArmed = !paths.isEmpty && preparedDragFrame.contains(dragOrigin)
      result(nil); return
    }
    if call.method == "startFileDrag" {
      if dragInProgress { result(nil); return }
      guard let args = call.arguments as? [String: Any], let paths = args["paths"] as? [String],
        !paths.isEmpty, let view = viewController?.view, let event = dragEvent,
        NSEvent.pressedMouseButtons & 1 != 0 else {
        result(FlutterError(code: "drag_cancelled", message: "文件已准备好，请再次拖拽", details: nil)); return
      }
      dragSource.movable = args["movable"] as? Bool ?? false
      beginFileDrag(paths, view: view, event: event)
      result(nil); return
    }
    if call.method == "fileCommandsEnabled" {
      if let host = viewController?.view.window as? HizipPreviewWindow {
        host.fileCommandsEnabled = call.arguments as? Bool ?? false
        host.fileCommand = { [weak self] command in self?.channel.invokeMethod("fileCommand", arguments: command) }
      }
      result(nil); return
    }
    if call.method == "quickLookVisible" {
      result(QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible); return
    }
    if call.method == "closeQuickLook" {
      if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().orderOut(nil) }
      preview.enabled = false
      result(nil); return
    }
    guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
      result(FlutterError(code: "arguments", message: "Missing path", details: nil)); return
    }
    let destination = URL(fileURLWithPath: path)
    do {
      switch call.method {
      case "applicationsForFile":
        let type = UTType(filenameExtension: destination.pathExtension) ?? .data
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: type)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: type)
        if let preferred = preferred {
          apps.removeAll { $0 == preferred }
          apps.insert(preferred, at: 0)
        }
        result(apps.map { applicationInfo($0, isDefault: $0 == preferred) })
      case "openWith":
        guard let application = args["application"] as? String else {
          result(FlutterError(code: "arguments", message: "Missing application", details: nil)); return
        }
        NSWorkspace.shared.open([destination], withApplicationAt: URL(fileURLWithPath: application),
          configuration: NSWorkspace.OpenConfiguration()) { _, error in
          DispatchQueue.main.async {
            if let error = error { result(FlutterError(code: "open_application", message: error.localizedDescription, details: nil)) }
            else { result(nil) }
          }
        }
      case "fileIcon":
        let directory = args["directory"] as? Bool ?? false
        let pixelSize = max(32, min(args["pixelSize"] as? Int ?? 128, 1024))
        let ext = destination.pathExtension.lowercased()
        let key = "\(directory ? "folder" : ext):\(pixelSize)"
        if let cached = iconCache[key] { result(FlutterStandardTypedData(bytes: cached)); return }
        let type: UTType = directory ? .folder : (UTType(filenameExtension: ext) ?? .data)
        if let data = png(NSWorkspace.shared.icon(for: type), pixelSize: pixelSize) {
          iconCache[key] = data
          result(FlutterStandardTypedData(bytes: data))
        } else { result(nil) }
      case "defaultApplication":
        guard let type = UTType(filenameExtension: destination.pathExtension),
          let app = NSWorkspace.shared.urlForApplication(toOpen: type) else { result(nil); return }
        let name = (FileManager.default.displayName(atPath: app.path) as NSString).deletingPathExtension
        var info: [String: Any] = ["name": name]
        if let data = png(NSWorkspace.shared.icon(forFile: app.path)) { info["icon"] = FlutterStandardTypedData(bytes: data) }
        result(info)
      case "quickLook":
        installPreviewResponder()
        preview.item = destination as NSURL
        preview.enabled = true
        guard let panel = QLPreviewPanel.shared() else { throw NSError(domain: "HiZip", code: 1, userInfo: [NSLocalizedDescriptionKey: "System Quick Look is unavailable"]) }
        if !panel.isVisible {
          viewController?.view.window?.makeKeyAndOrderFront(nil)
          panel.makeKeyAndOrderFront(nil)
        }
        panel.updateController()
        guard panel.currentController as AnyObject? === preview ||
          (panel.currentController as? HizipPreviewWindow)?.archivePreview === preview else {
          preview.enabled = false
          panel.orderOut(nil)
          throw NSError(domain: "HiZip", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot acquire system Quick Look control"])
        }
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    } catch { result(FlutterError(code: "native_files", message: error.localizedDescription, details: nil)) }
  }
}
