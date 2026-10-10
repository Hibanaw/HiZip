import Foundation

@main
struct FinderRequestTests {
  static func main() {
    let paths = ["/tmp/中文 & + #%/文件.txt", "/tmp/中文 & + #%/folder.v1"]
    for action in [FinderCompressionRequest.Action.create, .quickZip] {
      let request = FinderCompressionRequest(action: action, paths: paths)
      let decoded = FinderCompressionRequest.decode(request.launchURL!)!
      precondition(decoded.id == request.id && decoded.action == action && decoded.paths == paths)
      let clicked = FinderCompressionRequest.fromMenuAction(
        tag: action.menuTag, selectedURLs: paths.map { URL(fileURLWithPath: $0) })!
      precondition(clicked.action == action && clicked.paths == paths)
    }
    precondition(FinderCompressionRequest.fromMenuAction(tag: 0, selectedURLs: [URL(fileURLWithPath: "/tmp/a")]) == nil)
    precondition(FinderCompressionRequest.fromMenuAction(tag: 1, selectedURLs: nil) == nil)
    precondition(FinderCompressionRequest.fromMenuAction(tag: 1, selectedURLs: []) == nil)
    precondition(FinderCompressionRequest.fromMenuAction(tag: 2, selectedURLs: [URL(string: "https://example.com/a")!]) == nil)
    for paths in [[], ["relative/path"], ["/tmp/invalid\0"]] {
      precondition(FinderCompressionRequest.decode(FinderCompressionRequest(action: .create, paths: paths).launchURL!) == nil)
    }
    for value in ["other://compress?request=e30=", "hizip://other?request=e30=", "hizip://compress", "hizip://compress?request=invalid"] {
      precondition(FinderCompressionRequest.decode(URL(string: value)!) == nil)
    }
    print("Finder request transport tests passed")
  }
}
