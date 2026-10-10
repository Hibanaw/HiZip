import Cocoa
import FinderSync

@main
struct FinderMenuTests {
  static func main() {
    let menu = FinderSync.compressionMenu()
    precondition(menu.items.count == 1 && menu.items[0].title == "HiZip")
    let items = menu.items[0].submenu!.items
    precondition(items.count == 2)
    let urls = [URL(fileURLWithPath: "/tmp/中文 & 空格.txt")]
    for (index, action) in [FinderCompressionRequest.Action.create, .quickZip].enumerated() {
      let original = items[index]
      // Simulate the fields Finder transfers to the clicked menu item.
      let clicked = NSMenuItem(title: original.title, action: original.action, keyEquivalent: "")
      clicked.tag = original.tag
      precondition(clicked.representedObject == nil)
      precondition(clicked.action != nil)
      let request = FinderCompressionRequest.fromMenuAction(tag: clicked.tag, selectedURLs: urls)!
      precondition(request.action == action && request.paths == urls.map(\.path))
    }
    print("Finder copied menu action tests passed")
  }
}
