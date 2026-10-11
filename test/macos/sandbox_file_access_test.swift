import Cocoa

@main
struct SandboxAccessTests {
  static func main() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("hizip-access-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: root) }
    let directory = root.appendingPathComponent("授权 中文", isDirectory: true)
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("file.txt")
    try Data("original".utf8).write(to: file)
    let contents = try fm.contentsOfDirectory(atPath: directory.path)
    precondition(SandboxFileAccess.canRead(file))
    precondition(SandboxFileAccess.canWriteDirectory(directory))
    let after = try fm.contentsOfDirectory(atPath: directory.path)
    let data = try Data(contentsOf: file)
    precondition(after == contents)
    precondition(data == Data("original".utf8))
    precondition(SandboxFileAccess.contains(directory: directory, item: file))
    precondition(SandboxFileAccess.contains(directory: directory, item: directory))
    precondition(!SandboxFileAccess.contains(directory: directory, item: root.appendingPathComponent("授权 中文2/file.txt")))
    let link = root.appendingPathComponent("alias", isDirectory: true)
    try fm.createSymbolicLink(at: link, withDestinationURL: directory)
    precondition(SandboxFileAccess.contains(directory: directory, item: link.appendingPathComponent("file.txt")))
    let broken = directory.appendingPathComponent("broken")
    try fm.createSymbolicLink(atPath: broken.path, withDestinationPath: "/missing/hizip-target")
    precondition(SandboxFileAccess.canRead(broken))
    precondition(!SandboxFileAccess.canRead(root.appendingPathComponent("missing")))
    precondition(!SandboxFileAccess.canWriteDirectory(file))
    print("Sandbox path boundary and staging permission tests passed")
  }
}
