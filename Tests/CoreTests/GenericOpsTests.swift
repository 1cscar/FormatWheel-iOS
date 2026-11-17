import CryptoKit
@testable import FormatWheelCore
import XCTest
import ZIPFoundation

final class GenericOpsTests: CoreTestCase {
    private func file(_ name: String, _ text: String = "hello") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func entries(_ zip: URL) throws -> [String] {
        try Archive(url: zip, accessMode: .read).map(\.path).sorted()
    }

    func testZipSingleFile() async throws {
        let summary = try await run("gen.zip", [try file("notes.txt")])
        XCTAssertEqual(summary.outputs[0].lastPathComponent, "notes.zip")
        XCTAssertEqual(try entries(summary.outputs[0]), ["notes.txt"])
    }

    func testZipFolderKeepsParent() async throws {
        let folder = dir.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("a.txt"))
        let summary = try await run("gen.zip", [folder])
        XCTAssertTrue(try entries(summary.outputs[0]).contains("Album/a.txt"))
    }

    func testZipSeveralFilesIntoArchiveFolder() async throws {
        let files = try ["a.txt", "b.txt", "a.md"].map { try file($0) }
        let summary = try await run("gen.zip", files)
        XCTAssertEqual(summary.outputs[0].lastPathComponent, "归档 3 项.zip")
        XCTAssertEqual(try entries(summary.outputs[0]).filter { !$0.hasSuffix("/") }, ["归档/a.md", "归档/a.txt", "归档/b.txt"])
    }

    func testSHA256CopiesFullHash() async throws {
        let summary = try await run("gen.sha", [try file("x.bin", "hello")])
        let expected = SHA256.hash(data: Data("hello".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(clipboard.text, expected)
        XCTAssertTrue(summary.detail.contains("SHA-256 \(expected.prefix(12))… 已复制"), summary.detail)
    }

    func testCopyNames() async throws {
        let summary = try await run("gen.name", [try file("a.txt"), try file("b.png")])
        XCTAssertEqual(clipboard.text, "a.txt\nb.png")
        XCTAssertEqual(summary.detail, "已复制到剪贴板")
    }

    func testCopyPathDescribesFilesAppLocation() async throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FormatWheel/sub")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let inside = docs.appendingPathComponent("photo.png")
        try Data().write(to: inside)
        defer { try? FileManager.default.removeItem(at: docs) }
        let outside = try file("temp.txt")
        let summary = try await run("gen.path", [inside, outside])
        let lines = clipboard.text?.components(separatedBy: "\n") ?? []
        XCTAssertEqual(lines.first, "我的 \(Platform.deviceName) › 格式轮盘 › FormatWheel › sub › photo.png")
        XCTAssertEqual(lines.last, outside.absoluteString)
        XCTAssertEqual(summary.detail, "2 条路径已复制")
    }
}

final class EngineTests: CoreTestCase {
    func testSkipsFilesOfOtherKindsAndReportsSizes() async throws {
        let a = try Fixtures.write(Fixtures.photo(), as: .png, to: dir.appendingPathComponent("a.png"))
        let b = try Fixtures.write(Fixtures.photo(seed: 2), as: .png, to: dir.appendingPathComponent("b.png"))
        let pdf = try Fixtures.textPDF(in: dir)
        XCTAssertEqual(Catalog.context(for: [a, b, pdf]).summary.hasSuffix("另有 1 个会跳过"), true)
        let summary = try await run("img.to.jpg", [a, b, pdf])
        XCTAssertEqual(summary.outputs.map(\.lastPathComponent), ["a.jpg", "b.jpg"])
        XCTAssertTrue(summary.detail.contains(" → "), summary.detail)
        XCTAssertEqual(summary.title, "3 个文件  →  img.to.jpg")
    }

    func testFailureMessageWhenNothingWorked() async throws {
        let bad = dir.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: bad)
        do {
            _ = try await run("img.to.jpg", [bad])
            XCTFail("expected failure")
        } catch let e as FWError {
            XCTAssertEqual(e.message, "打不开这张图片")
        }
    }

    func testRecentsKeepsEightNewestFirst() {
        let key = "recentOutputs"
        let saved = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        for i in 0..<10 { Recents.shared.add([URL(fileURLWithPath: "/tmp/\(i).png")]) }
        XCTAssertEqual(Recents.shared.items.count, 8)
        XCTAssertEqual(Recents.shared.items.first?.lastPathComponent, "9.png")
    }

    func testPrivacyScanAcrossFiles() async throws {
        let jpg = try Fixtures.trackedJPEG(in: dir)
        let pdf = try Fixtures.textPDF(in: dir)
        let wanted = await Privacy.scan([jpg, pdf])
        XCTAssertEqual(wanted.level, 5)
        XCTAssertEqual(wanted.reasons, ["GPS 定位", "iPhone 15 Pro", "拍摄时间", "机身序列号 / 作者", "2 个文件留有痕迹"])
    }
}
