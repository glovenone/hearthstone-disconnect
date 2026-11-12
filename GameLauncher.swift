import Foundation
import Darwin

struct GameLauncher {
    let root: URL
    var official: URL { root.appendingPathComponent("Hearthstone.app/Contents/MacOS/Hearthstone") }
    var executable: URL { official.deletingLastPathComponent().appendingPathComponent("Hearthstone.real") }
    var dependencies: [URL] {
        ["libdoorstop.dylib", "BepInEx/core/BepInEx.Preloader.dll", "BepInEx/unstripped_corlib/mscorlib.dll", "BepInEx/plugins/DisconnectOnly.dll"].map { root.appendingPathComponent($0) }
    }
    var available: Bool {
        ([official] + dependencies).allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }
    enum Failure: Error { case running, missingFiles, untrusted, changed, signing }

    // The official entry is only read. Publish a separately signed copy only
    // after checking the source is stable and no game was started in the meantime.
    func prepare(gameRunning: () -> Bool, trusted: (URL) -> Bool, sign: (URL) -> Bool) throws {
        guard !gameRunning() else { throw Failure.running }
        guard available else { throw Failure.missingFiles }
        guard trusted(official) else { throw Failure.untrusted }
        let snapshot = try Data(contentsOf: official)
        let staged = executable.deletingLastPathComponent().appendingPathComponent("Hearthstone.launch.\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: official, to: staged)
        guard trusted(official), try Data(contentsOf: staged) == snapshot else { throw Failure.changed }
        guard sign(staged) else { throw Failure.signing }
        guard !gameRunning() else { throw Failure.running }
        guard try Data(contentsOf: official) == snapshot else { throw Failure.changed }
        guard rename(staged.path, executable.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
