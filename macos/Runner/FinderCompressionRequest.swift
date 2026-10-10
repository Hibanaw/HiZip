import Foundation

/// Shared wire format for the containing application and Finder extension.
struct FinderCompressionRequest: Codable {
  enum Action: String, Codable {
    case create, quickZip

    // Finder copies menu items across processes and preserves their tag,
    // but does not preserve representedObject.
    var menuTag: Int { self == .create ? 1 : 2 }

    init?(menuTag: Int) {
      switch menuTag {
      case 1: self = .create
      case 2: self = .quickZip
      default: return nil
      }
    }
  }
  let version: Int
  let id: UUID
  let action: Action
  let paths: [String]

  init(action: Action, paths: [String]) {
    version = 1
    id = UUID()
    self.action = action
    self.paths = paths
  }

  static func fromMenuAction(tag: Int, selectedURLs: [URL]?) -> Self? {
    guard let action = Action(menuTag: tag), let urls = selectedURLs,
      !urls.isEmpty, urls.allSatisfy({ $0.isFileURL }) else { return nil }
    return Self(action: action, paths: urls.map(\.path))
  }

  var launchURL: URL? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    var components = URLComponents()
    components.scheme = "hizip"
    components.host = "compress"
    components.queryItems = [URLQueryItem(name: "request", value: data.base64EncodedString())]
    return components.url
  }

  static func decode(_ url: URL) -> FinderCompressionRequest? {
    guard url.scheme == "hizip", url.host == "compress",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let payload = components.queryItems?.first(where: { $0.name == "request" })?.value,
      payload.utf8.count <= 4 * 1024 * 1024,
      let data = Data(base64Encoded: payload),
      let request = try? JSONDecoder().decode(Self.self, from: data),
      request.version == 1, !request.paths.isEmpty, request.paths.count <= 10000,
      request.paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { return nil }
    return request
  }

  var arguments: [String: Any] { ["action": action.rawValue, "paths": paths] }
}
