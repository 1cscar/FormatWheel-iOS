@testable import FormatWheelCore
import XCTest

/// Compares FormatWheelCore's Catalog with upstream's, compiled unmodified from
/// upstream/Sources/Catalog.swift by scripts/catalog-parity/dump-upstream.sh (run by scripts/test.sh).
/// Every slot's id, order, big, symbol, ammo, title, detail, enabled state, note and stats, every page,
/// stat label, base trait and trait table must match. The only allowed differences are listed in
/// `Exceptions` and are the iOS capability checks that replace Homebrew tools.
final class CatalogParityTests: XCTestCase {
    enum Exceptions {
        /// Slots whose upstream `requires` tool is replaced by an iOS capability check.
        static let requires: [String: String] = [
            "img.to.webp": "upstream requires cwebp; iOS has libwebp built in, so the slot is always available",
            "img.to.heic": "upstream needs nothing (macOS can always write HEIC); iOS checks for an ImageIO HEIC encoder",
            "img.to.avif": "upstream requires ffmpeg; iOS accepts an ImageIO AVIF encoder or the bundled FFmpeg",
        ]
        /// Upstream's 「未装备」 note is a `brew install` hint; iOS explains the missing capability instead.
        static let installHintPrefix = "需要先装 "
    }

    private var upstream: [String: Any] = [:]
    private var root: URL!

    override func setUpWithError() throws {
        Localization.language = "zh-Hans"
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let json = repo.appendingPathComponent("build/parity/upstream-catalog.json")
        guard let data = try? Data(contentsOf: json) else {
            XCTFail("missing \(json.path): run scripts/catalog-parity/dump-upstream.sh (scripts/test.sh does it)")
            throw XCTSkip("unreachable")
        }
        upstream = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root = FileManager.default.temporaryDirectory.appendingPathComponent("parity-\(UUID().uuidString)")
    }

    override func tearDown() {
        Localization.language = nil
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func tools(_ name: String) -> Tools {
        switch name {
        case "all", "noCwebp": return Tools(ffmpeg: true, heicEncoder: true, avifImageIO: false)
        default: return Tools(ffmpeg: false, heicEncoder: true, avifImageIO: false)
        }
    }

    private func materialize(_ names: [String]) throws -> [URL] {
        try names.map { name in
            let url = root.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            return url
        }
    }

    func testAllIDsMatch() throws {
        XCTAssertEqual(Catalog.allIDs, upstream["allIDs"] as? [String])
        XCTAssertEqual(Catalog.allIDs.count, 73)
    }

    func testTraitTablesMatch() throws {
        let traits = try XCTUnwrap(upstream["traits"] as? [String: [String: [Double]]])
        XCTAssertEqual(Catalog.imageTraits, traits["image"])
        XCTAssertEqual(Catalog.pdfTraits, traits["pdf"])
        XCTAssertEqual(Catalog.videoTraits, traits["video"])
        XCTAssertEqual(Catalog.audioTraits, traits["audio"])
        XCTAssertEqual(Catalog.docTraits, traits["doc"])
    }

    func testRequiresMatchExceptListedCapabilities() throws {
        let theirs = try XCTUnwrap(upstream["requires"] as? [String: String])
        var mine: [String: String] = [:]
        let none = Tools(ffmpeg: false, heicEncoder: false, avifImageIO: false)
        for name in ["x.png", "x.jpg", "x.pdf", "x.mp4", "x.mov", "x.mp3", "x.wav", "x.docx", "x.zip"] {
            for page in Catalog.context(for: try materialize([name]), tools: none).pages {
                for case let slot? in page.slots {
                    if let tool = slot.requires?.upstreamTool { mine[slot.id] = tool }
                }
            }
        }
        for id in Set(theirs.keys).union(mine.keys) where Exceptions.requires[id] == nil {
            XCTAssertEqual(mine[id], theirs[id], "requires differs for \(id)")
        }
        // Exceptions must stay real: each listed slot really differs from or extends upstream.
        XCTAssertEqual(theirs["img.to.webp"], "cwebp")
        XCTAssertNil(mine["img.to.webp"])
        XCTAssertNil(theirs["img.to.heic"])
    }

    func testEveryScenarioMatchesUpstream() throws {
        let scenarios = try XCTUnwrap(upstream["scenarios"] as? [[String: Any]])
        XCTAssertGreaterThan(scenarios.count, 100)
        for sc in scenarios {
            let name = sc["name"] as! String
            let files = try materialize(sc["files"] as! [String])
            let ctx = Catalog.context(for: files, tools: tools(sc["tools"] as! String))
            XCTAssertEqual(ctx.kind.rawValue, sc["kind"] as? String, name)
            XCTAssertEqual(ctx.headline, sc["headline"] as? String, name)
            XCTAssertEqual(ctx.statLabels, sc["statLabels"] as? [String], name)
            XCTAssertEqual(ctx.base, sc["base"] as? [Double], name)
            let pages = sc["pages"] as! [[String: Any]]
            XCTAssertEqual(ctx.pages.count, pages.count, name)
            for (p, page) in zip(ctx.pages, pages) {
                XCTAssertEqual(p.name, page["name"] as? String, name)
                let slots = page["slots"] as! [Any]
                XCTAssertEqual(p.slots.count, slots.count, "\(name) \(p.name)")
                for (i, (mine, theirs)) in zip(p.slots, slots).enumerated() {
                    compare(mine, theirs as? [String: Any], at: "\(name) [\(p.name)] #\(i)")
                }
            }
        }
    }

    private func compare(_ mine: WheelOption?, _ theirs: [String: Any]?, at place: String) {
        guard let mine, let theirs else {
            XCTAssertTrue(mine == nil && theirs == nil, "\(place): empty slot mismatch")
            return
        }
        let id = theirs["id"] as! String
        XCTAssertEqual(mine.id, id, place)
        XCTAssertEqual(mine.big, theirs["big"] as? String, "\(place) big")
        XCTAssertEqual(mine.symbol, theirs["symbol"] as? String, "\(place) symbol")
        XCTAssertEqual(mine.title, theirs["title"] as? String, "\(place) title")
        XCTAssertEqual(mine.detail, theirs["detail"] as? String, "\(place) detail")
        XCTAssertEqual(mine.stats, theirs["stats"] as? [Double], "\(place) stats")

        let theirNote = theirs["note"] as? String
        if let theirNote, theirNote.hasPrefix(Exceptions.installHintPrefix) {
            if Exceptions.requires[id] != nil, theirNote.contains("cwebp") {
                // libwebp is built in: the slot stays usable on iOS.
                XCTAssertTrue(mine.enabled, "\(place): \(id) should be available")
                return
            }
            // Same 「未装备」 state; iOS explains the missing capability instead of `brew install`.
            XCTAssertFalse(mine.enabled, place)
            XCTAssertEqual(mine.ammo, "未装备", place)
            XCTAssertEqual(mine.note, mine.requires?.unavailableReason, place)
            XCTAssertFalse(mine.note?.contains("brew") ?? true, place)
            return
        }
        XCTAssertEqual(mine.enabled, theirs["enabled"] as? Bool, "\(place) enabled")
        XCTAssertEqual(mine.ammo, theirs["ammo"] as? String, "\(place) ammo")
        XCTAssertEqual(mine.note, theirNote, "\(place) note")
    }

    func testHEICSlotUnequippedWithoutEncoder() throws {
        let ctx = Catalog.context(for: try materialize(["p.png"]), tools: Tools(ffmpeg: true, heicEncoder: false, avifImageIO: false))
        let heic = try XCTUnwrap(ctx.pages[0].slots[2])
        XCTAssertEqual(heic.id, "img.to.heic")
        XCTAssertFalse(heic.enabled)
        XCTAssertEqual(heic.ammo, "未装备")
        XCTAssertEqual(heic.note, "此设备不支持 HEIC 编码")
    }

    func testUnequippedHintsAreLocalised() {
        for (language, expected) in [("zh-Hant", "此裝置不支援 HEIC 編碼"), ("en", "This device can't encode HEIC")] {
            Localization.language = language
            XCTAssertEqual(Requirement.heicEncoder.unavailableReason, expected, language)
            for r in Requirement.allCases {
                XCTAssertFalse(r.unavailableReason.isEmpty)
                XCTAssertNotEqual(r.unavailableReason, { Localization.language = "zh-Hans"; defer { Localization.language = language }; return r.unavailableReason }(), "\(r) not translated to \(language)")
            }
        }
    }
}
