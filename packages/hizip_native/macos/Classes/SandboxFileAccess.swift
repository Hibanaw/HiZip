import Cocoa
import Darwin

/// All Flutter engines and worker isolates share one process-wide set of grants.
/// Only the containing app prompts for access; Finder supplies paths, not grants.
final class SandboxFileAccess {
  static let shared = SandboxFileAccess()
  private let defaults: UserDefaults
  private let key = "hizip.securityScopedBookmarks.v1"
  private var bookmarks: [String: Data]
  private var scopes: [String: URL] = [:]
  private var requests: [Request] = []

  private final class Request {
    let requirements: [(URL, Bool)]
    weak var window: NSWindow?
    let message: String, prompt: String, chooseMessage: String, failureMessage: String
    let completion: (Result<Bool, Error>) -> Void
    var index = 0
    var panel: NSOpenPanel?
    var delegate: DirectoryValidator?

    init(readPaths: [String], writeDirectories: [String], window: NSWindow?,
      message: String, prompt: String, chooseMessage: String, failureMessage: String,
      completion: @escaping (Result<Bool, Error>) -> Void) {
      requirements = Array(Set(writeDirectories)).sorted().map { (URL(fileURLWithPath: $0), true) } +
        Array(Set(readPaths)).sorted().map { (URL(fileURLWithPath: $0), false) }
      self.window = window
      self.message = message
      self.prompt = prompt
      self.chooseMessage = chooseMessage
      self.failureMessage = failureMessage
      self.completion = completion
    }
  }

  private final class DirectoryValidator: NSObject, NSOpenSavePanelDelegate {
    let required: URL, message: String
    init(required: URL, message: String) { self.required = required; self.message = message }
    func panel(_ sender: Any, validate url: URL) throws {
      guard SandboxFileAccess.contains(directory: url, item: required) else {
        throw NSError(domain: "HiZipFileAccess", code: 1,
          userInfo: [NSLocalizedDescriptionKey: message])
      }
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    bookmarks = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
    restore()
  }

  deinit { for url in scopes.values { url.stopAccessingSecurityScopedResource() } }

  static func contains(directory: URL, item: URL) -> Bool {
    let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
    let path = item.standardizedFileURL.resolvingSymlinksInPath().path
    return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
  }

  static func canRead(_ url: URL) -> Bool {
    // Reading a symlink's metadata doesn't require access to its target.
    var metadata = stat()
    if lstat(url.path, &metadata) == 0 && (metadata.st_mode & S_IFMT) == S_IFLNK {
      return true
    }
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else { return false }
    close(descriptor)
    return true
  }

  static func canWriteDirectory(_ url: URL) -> Bool {
    // A file-only Powerbox grant is insufficient for safe sibling staging.
    let probe = url.appendingPathComponent(".hizip-access-\(UUID().uuidString)")
    let descriptor = open(probe.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { return false }
    close(descriptor)
    return unlink(probe.path) == 0
  }

  private func restore() {
    for (identifier, data) in Array(bookmarks) {
      do {
        var stale = false
        let url = try URL(resolvingBookmarkData: data,
          options: [.withSecurityScope, .withoutUI], relativeTo: nil,
          bookmarkDataIsStale: &stale)
        let started = url.startAccessingSecurityScopedResource()
        if started { scopes[identifier] = url }
        guard started || Self.canRead(url) else {
          bookmarks.removeValue(forKey: identifier)
          continue
        }
        if stale {
          let options: URL.BookmarkCreationOptions = identifier.hasPrefix("write:") ?
            [.withSecurityScope] : [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
          bookmarks[identifier] = try url.bookmarkData(options: options,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        }
      } catch {
        scopes.removeValue(forKey: identifier)?.stopAccessingSecurityScopedResource()
        bookmarks.removeValue(forKey: identifier)
      }
    }
    defaults.set(bookmarks, forKey: key)
  }

  private func remember(_ url: URL, writable: Bool) {
    // Container/cache access needs no persistent external grant.
    if Self.contains(directory: URL(fileURLWithPath: NSHomeDirectory()), item: url) ||
      Self.contains(directory: URL(fileURLWithPath: NSTemporaryDirectory()), item: url) { return }
    let identifier = (writable ? "write:" : "read:") + url.standardizedFileURL.path
    if scopes[identifier] != nil { return }
    if scopes.contains(where: { key, scope in
      (!writable || key.hasPrefix("write:")) && scope.hasDirectoryPath &&
        Self.contains(directory: scope, item: url)
    }) { return }
    let started = url.startAccessingSecurityScopedResource()
    let options: URL.BookmarkCreationOptions = writable ?
      [.withSecurityScope] : [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    do {
      let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
      if started { scopes[identifier] = url }
      bookmarks[identifier] = data
      defaults.set(bookmarks, forKey: key)
    } catch {
      // Keep this session's explicit grant even if persistence is unavailable.
      if started { scopes[identifier] = url }
      NSLog("HiZip could not persist a file access bookmark: %@", error.localizedDescription)
    }
  }

  func ensure(readPaths: [String], writeDirectories: [String], window: NSWindow?,
    message: String, prompt: String, chooseMessage: String, failureMessage: String,
    completion: @escaping (Result<Bool, Error>) -> Void) {
    precondition(Thread.isMainThread)
    requests.append(Request(readPaths: readPaths, writeDirectories: writeDirectories, window: window,
      message: message, prompt: prompt, chooseMessage: chooseMessage, failureMessage: failureMessage,
      completion: completion))
    if requests.count == 1 { advance() }
  }

  private func finish(_ result: Result<Bool, Error>) {
    let request = requests.removeFirst()
    request.completion(result)
    // A completion can synchronously enqueue another request.
    DispatchQueue.main.async { [weak self] in
      if self?.requests.isEmpty == false { self?.advance() }
    }
  }

  private func advance() {
    guard let request = requests.first, request.panel == nil else { return }
    while request.index < request.requirements.count {
      let (url, writable) = request.requirements[request.index]
      let accessible = writable ? Self.canWriteDirectory(url) : Self.canRead(url)
      if accessible {
        remember(url, writable: writable)
        request.index += 1
        continue
      }
      let directory = writable ? url : url.deletingLastPathComponent()
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = false
      panel.directoryURL = directory
      panel.message = request.message
      panel.prompt = request.prompt
      let validator = DirectoryValidator(required: directory, message: request.chooseMessage)
      panel.delegate = validator
      request.panel = panel
      request.delegate = validator
      let reply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
        guard let self = self else { return }
        request.panel = nil
        request.delegate = nil
        guard response == .OK, let selected = panel.url else {
          self.finish(.success(false)); return
        }
        self.remember(selected, writable: true)
        guard writable ? Self.canWriteDirectory(url) : Self.canRead(url) else {
          self.finish(.failure(NSError(domain: "HiZipFileAccess", code: 2,
            userInfo: [NSLocalizedDescriptionKey: request.failureMessage]))); return
        }
        request.index += 1
        self.advance()
      }
      NSApp.activate(ignoringOtherApps: true)
      if let window = request.window {
        window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: window, completionHandler: reply)
      } else {
        panel.begin(completionHandler: reply)
      }
      return
    }
    finish(.success(true))
  }
}
