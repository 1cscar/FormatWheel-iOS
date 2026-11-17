@testable import FormatWheelCore
import XCTest

/// Common setup: outputs go to a fresh temp folder, the clipboard is in memory, upstream (zh-Hans) wording.
class CoreTestCase: XCTestCase {
    var dir: URL!
    var outDir: URL!
    var clipboard: MemoryClipboard!
    private var savedClipboard: ClipboardService!

    override func setUpWithError() throws {
        dir = try Fixtures.tempDir()
        outDir = dir.appendingPathComponent("out", isDirectory: true)
        let target = outDir!
        Out.directory = { target }
        savedClipboard = Platform.clipboard
        clipboard = MemoryClipboard()
        Platform.clipboard = clipboard
        Localization.language = "zh-Hans"
        Tools.current = Tools.detect()
    }

    override func tearDownWithError() throws {
        Tools.current = Tools.detect()
        Platform.clipboard = savedClipboard
        Localization.language = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// Runs one action through the engine exactly as the wheel does.
    @discardableResult
    func run(_ id: String, _ files: [URL]) async throws -> RunSummary {
        try await Engine.run(id, label: id, files: files) { _ in }
    }

    func runOne(_ id: String, _ file: URL) async throws -> OpResult {
        try await Engine.runOne(id, file) { _ in }
    }
}
