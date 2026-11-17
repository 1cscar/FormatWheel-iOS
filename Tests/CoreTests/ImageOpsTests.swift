import ImageIO
@testable import FormatWheelCore
import UniformTypeIdentifiers
import XCTest

final class ImageOpsTests: CoreTestCase {
    private func png(alpha: Bool = false, name: String = "photo.png") throws -> URL {
        try Fixtures.write(Fixtures.photo(alpha: alpha), as: .png, to: dir.appendingPathComponent(name))
    }

    private func assertImage(_ url: URL, type: UTType, width: Int? = nil, height: Int? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Fixtures.type(of: url), type.identifier, file: file, line: line)
        let image = Fixtures.image(at: url)
        XCTAssertNotNil(image, "unreadable \(url.lastPathComponent)", file: file, line: line)
        if let width { XCTAssertEqual(image?.width, width, file: file, line: line) }
        if let height { XCTAssertEqual(image?.height, height, file: file, line: line) }
    }

    // MARK: Convert

    func testToPNG() async throws {
        let src = try Fixtures.trackedJPEG(in: dir)
        let out = try await runOne("img.to.png", src).outputs[0]
        XCTAssertEqual(out.lastPathComponent, "IMG_2049.png")
        assertImage(out, type: .png, width: 640, height: 480)
    }

    func testToJPGFlattensAlpha() async throws {
        let out = try await runOne("img.to.jpg", try png(alpha: true)).outputs[0]
        assertImage(out, type: .jpeg, width: 640, height: 480)
        XCTAssertFalse(ImageOps.hasAlpha(Fixtures.image(at: out)!))
    }

    func testToHEIC() async throws {
        XCTAssertTrue(Tools.current.heicEncoder, "the iOS simulator and devices ship an ImageIO HEIC encoder")
        let out = try await runOne("img.to.heic", try png()).outputs[0]
        assertImage(out, type: .heic, width: 640, height: 480)
    }

    func testToWebPKeepsAlphaAndICC() async throws {
        let p3 = Fixtures.photo(alpha: true).copy(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)!
        let src = try Fixtures.write(p3, as: .png, to: dir.appendingPathComponent("p3.png"))
        let out = try await runOne("img.to.webp", src).outputs[0]
        assertImage(out, type: UTType.webP, width: 640, height: 480)
        let data = try Data(contentsOf: out)
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        XCTAssertNotNil(data.range(of: Data("ICCP".utf8)), "ICC profile should be embedded like cwebp -metadata icc")
        XCTAssertTrue(ImageOps.hasAlpha(Fixtures.image(at: out)!))
    }

    func testToAVIFViaImageIOOrFFmpeg() async throws {
        let out = try await runOne("img.to.avif", try png(alpha: true)).outputs[0]
        XCTAssertEqual(Fixtures.type(of: out), "public.avif")
        XCTAssertNotNil(Fixtures.image(at: out))
    }

    func testToAVIFFallsBackToFFmpeg() async throws {
        Tools.current.avifImageIO = false
        let out = try await runOne("img.to.avif", try png()).outputs[0]
        let data = try Data(contentsOf: out)
        XCTAssertEqual(data.subdata(in: 4..<12), Data("ftypavif".utf8), "FFmpeg libsvtav1 should write an AVIF file")
    }

    func testToGIF() async throws {
        assertImage(try await runOne("img.to.gif", try png()).outputs[0], type: .gif, width: 640, height: 480)
    }

    func testToTIFF() async throws {
        let out = try await runOne("img.to.tiff", try png()).outputs[0]
        assertImage(out, type: .tiff, width: 640, height: 480)
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(out as CFURL, nil)!, 0, nil) as! [CFString: Any]
        XCTAssertEqual((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int, 5, "LZW")
    }

    func testToPDFSingle() async throws {
        let out = try await runOne("img.to.pdf", try png()).outputs[0]
        XCTAssertEqual(CGPDFDocument(out as CFURL)?.numberOfPages, 1)
    }

    func testToPDFMergesSeveralImagesInOrder() async throws {
        let files = try (1...3).map { try Fixtures.write(Fixtures.photo(seed: UInt32($0)), as: .jpeg, to: dir.appendingPathComponent("\($0).jpg")) }
        let summary = try await run("img.to.pdf", files)
        XCTAssertEqual(summary.outputs.count, 1)
        XCTAssertEqual(summary.outputs[0].lastPathComponent, "1 合并.pdf")
        XCTAssertEqual(CGPDFDocument(summary.outputs[0] as CFURL)?.numberOfPages, 3)
        XCTAssertTrue(summary.detail.contains("存到「"), summary.detail)
    }

    func testConvertKeepsGPSLikeUpstream() async throws {
        // Upstream carries EXIF/GPS over on plain conversions (only 去隐私 removes it).
        let out = try await runOne("img.to.png", try Fixtures.trackedJPEG(in: dir)).outputs[0]
        XCTAssertGreaterThanOrEqual(Privacy.image(out).level, 2)
    }

    // MARK: Tools

    func testCompressShrinksPhoto() async throws {
        let src = try Fixtures.write(Fixtures.photo(width: 2000, height: 1500), as: .jpeg, to: dir.appendingPathComponent("big.jpg"), quality: 1)
        let result = try await runOne("img.compress", src)
        XCTAssertEqual(result.outputs[0].lastPathComponent, "big 压缩.jpg")
        XCTAssertLessThan(Fmt.size(of: result.outputs[0]), Fmt.size(of: src))
        XCTAssertTrue(result.note?.hasPrefix("体积 -") == true, result.note ?? "")
    }

    func testCompressTransparentPNGBecomesWebP() async throws {
        let src = try Fixtures.write(Fixtures.photo(width: 1600, height: 1200, alpha: true), as: .png, to: dir.appendingPathComponent("logo.png"))
        let out = try await runOne("img.compress", src).outputs[0]
        XCTAssertEqual(out.pathExtension, "webp")
        XCTAssertTrue(ImageOps.hasAlpha(Fixtures.image(at: out)!))
    }

    func testCompressRefusesWhenAlreadySmall() async throws {
        let src = try Fixtures.write(Fixtures.photo(width: 64, height: 48), as: .jpeg, to: dir.appendingPathComponent("tiny.jpg"), quality: 0.1)
        do {
            _ = try await runOne("img.compress", src)
            XCTFail("expected 已经很小了")
        } catch let e as FWError {
            XCTAssertEqual(e.message, "已经很小了，压不动了")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("tiny 压缩.jpg").path))
    }

    func testHalf() async throws {
        let result = try await runOne("img.half", try png())
        assertImage(result.outputs[0], type: .png, width: 320, height: 240)
        XCTAssertEqual(result.note, "320×240")
        XCTAssertEqual(result.outputs[0].lastPathComponent, "photo 缩小.png")
    }

    func testCutoutProducesTransparentPNG() async throws {
        let src = try Fixtures.write(Fixtures.subjectImage(), as: .png, to: dir.appendingPathComponent("subject.png"))
        let result: OpResult
        #if targetEnvironment(simulator)
        do {
            result = try await runOne("img.cutout", src)
        } catch let e as FWError where e.message == ImageOps.cutoutUnavailable || e.message == "没找到能抠出来的主体" {
            // Hardware-dependent like VideoToolbox: Vision's foreground-mask model needs the Neural Engine or a
            // usable GPU. Simulators either can't create an inference context (Xcode 27) or return no instances
            // even for an obvious subject (Xcode 26 CI). On a device this test must pass — no skip there.
            throw XCTSkip("img.cutout: Vision foreground mask unavailable in the iOS Simulator (\(e.message)); verified on device")
        }
        #else
        result = try await runOne("img.cutout", src)
        #endif
        let out = result.outputs[0]
        XCTAssertEqual(out.lastPathComponent, "subject 抠图.png")
        XCTAssertEqual(result.note, "背景已去掉")
        let corners = Fixtures.samples(Fixtures.image(at: out)!, grid: 12)
        XCTAssertEqual(corners.first?.a, 0, "background should be transparent")
    }

    func testOCRWritesTextAndCopies() async throws {
        let src = try Fixtures.write(Fixtures.textImage(["FormatWheel 2049", "Hello wheel"]), as: .png, to: dir.appendingPathComponent("text.png"))
        let summary = try await run("img.ocr", [src])
        let text = try String(contentsOf: summary.outputs[0], encoding: .utf8)
        // OCR accuracy varies between Vision versions; check tokens every version reads reliably.
        XCTAssertTrue(text.contains("2049") && text.contains("Hello"), text)
        XCTAssertEqual(summary.outputs[0].lastPathComponent, "text 文字.txt")
        XCTAssertEqual(clipboard.text, text)
        XCTAssertTrue(summary.detail.contains("已复制"), summary.detail)
    }

    func testMonoIsGray() async throws {
        let out = try await runOne("img.mono", try png()).outputs[0]
        XCTAssertEqual(out.lastPathComponent, "photo 黑白.png")
        for s in Fixtures.samples(Fixtures.image(at: out)!) {
            XCTAssertLessThanOrEqual(abs(Int(s.r) - Int(s.g)), 1)
            XCTAssertLessThanOrEqual(abs(Int(s.g) - Int(s.b)), 1)
        }
    }

    func testRotateClockwise() async throws {
        let out = try await runOne("img.rotate", try Fixtures.trackedJPEG(in: dir)).outputs[0]
        assertImage(out, type: .jpeg, width: 480, height: 640)
        XCTAssertEqual(out.lastPathComponent, "IMG_2049 旋转.jpg")
    }

    func testStripRemovesTrackingMetadata() async throws {
        let src = try Fixtures.trackedJPEG(in: dir)
        XCTAssertEqual(Privacy.image(src).level, 5)
        let result = try await runOne("img.strip", src)
        let out = result.outputs[0]
        XCTAssertEqual(out.lastPathComponent, "IMG_2049 去隐私.jpg")
        XCTAssertEqual(result.note, "已甩掉警察：定位、设备和作者信息都抹掉了")
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(out as CFURL, nil)!, 0, nil) as! [CFString: Any]
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(tiff[kCGImagePropertyTIFFModel])
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertNil(exif[kCGImagePropertyExifBodySerialNumber])
        XCTAssertEqual(Privacy.image(out), Wanted())
        assertImage(out, type: .jpeg, width: 640, height: 480)
    }

    func testBackdropAddsPadding() async throws {
        let out = try await runOne("img.backdrop", try png()).outputs[0]
        let pad = Int((640.0 * 0.09).rounded())
        assertImage(out, type: .png, width: 640 + pad * 2, height: 480 + pad * 2)
        XCTAssertEqual(out.lastPathComponent, "photo 加背景.png")
    }

    func testOutputNamesNeverOverwrite() async throws {
        let src = try png()
        let a = try await runOne("img.to.jpg", src).outputs[0]
        let b = try await runOne("img.to.jpg", src).outputs[0]
        XCTAssertEqual(a.lastPathComponent, "photo.jpg")
        XCTAssertEqual(b.lastPathComponent, "photo 2.jpg")
    }
}
