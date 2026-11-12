import Foundation
@main struct GameLauncherTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = GameLauncher(root: root)
        try FileManager.default.createDirectory(at: launcher.official.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("official".utf8).write(to: launcher.official)
        for url in launcher.dependencies {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("dependency".utf8).write(to: url)
        }
        var checks = 0
        func check(_ value: Bool) { precondition(value); checks += 1 }
        func reset() throws {
            try Data("official".utf8).write(to: launcher.official)
            try Data("previous-copy".utf8).write(to: launcher.executable)
        }
        func rejected(_ action: () throws -> Void) { do { try action(); preconditionFailure("Expected rejection") } catch { checks += 1 } }
        try reset()
        rejected { try launcher.prepare(gameRunning: { true }, trusted: { _ in true }, sign: { _ in true }) }
        check(try Data(contentsOf: launcher.executable) == Data("previous-copy".utf8))
        rejected { try launcher.prepare(gameRunning: { false }, trusted: { _ in false }, sign: { _ in true }) }
        rejected { try launcher.prepare(gameRunning: { false }, trusted: { _ in true }, sign: { _ in false }) }
        check(try Data(contentsOf: launcher.executable) == Data("previous-copy".utf8))
        var calls = 0
        rejected { try launcher.prepare(gameRunning: { calls += 1; return calls == 2 }, trusted: { _ in true }, sign: { _ in true }) }
        check(try Data(contentsOf: launcher.executable) == Data("previous-copy".utf8))
        rejected { try launcher.prepare(gameRunning: { false }, trusted: { _ in true }, sign: { _ in
            try! Data("updated".utf8).write(to: launcher.official); return true
        }) }
        check(try Data(contentsOf: launcher.executable) == Data("previous-copy".utf8))
        try reset()
        try launcher.prepare(gameRunning: { false }, trusted: { _ in true }, sign: { url in
            try! Data("signed-copy".utf8).write(to: url); return true
        })
        check(try Data(contentsOf: launcher.official) == Data("official".utf8))
        check(try Data(contentsOf: launcher.executable) == Data("signed-copy".utf8))
        check(try FileManager.default.contentsOfDirectory(atPath: launcher.executable.deletingLastPathComponent().path).filter { $0.hasSuffix(".tmp") }.isEmpty)
        try FileManager.default.removeItem(at: launcher.dependencies[0])
        rejected { try launcher.prepare(gameRunning: { false }, trusted: { _ in true }, sign: { _ in true }) }
        print("PASS: \(checks) launch preparation assertions; official file preserved; no game launched")
    }
}
