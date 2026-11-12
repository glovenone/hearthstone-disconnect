import Foundation
@main struct Check {
 static func main() throws {
  let source = URL(fileURLWithPath: "/Applications/Hearthstone")
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("hs-launch-check-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let helper = GameLauncher(root: root)
  try FileManager.default.createDirectory(at: helper.official.deletingLastPathComponent(), withIntermediateDirectories: true)
  try FileManager.default.copyItem(at: source.appendingPathComponent("Hearthstone.app/Contents/Info.plist"), to: root.appendingPathComponent("Hearthstone.app/Contents/Info.plist"))
  let actual = source.appendingPathComponent("Hearthstone.app/Contents/MacOS/Hearthstone")
  let before = try Data(contentsOf: actual)
  try FileManager.default.copyItem(at: actual, to: helper.official)
  for entry in ["libdoorstop.dylib", "BepInEx"] {
   try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(entry), withDestinationURL: source.appendingPathComponent(entry))
  }
  func codeSign(_ args: [String]) -> Bool {
   let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); p.arguments = args
   try! p.run(); p.waitUntilExit(); return p.terminationStatus == 0
  }
  try helper.prepare(gameRunning: {false}, trusted: { codeSign(["--verify", "--ignore-resources", "-R=anchor apple generic and certificate leaf[subject.OU] = \"G847MC6JZ5\"", $0.path]) }, sign: {
   codeSign(["--force", "--sign", "-", $0.path]) && codeSign(["--verify", "--strict", $0.path])
  })
  let after = try Data(contentsOf: actual)
  precondition(after == before)
  print("PASS: actual Blizzard signature and local signing verified on a temporary copy; installed game unchanged")
 }
}
