import CoreGraphics
@testable import FormatWheelCore
import PDFKit
import XCTest

final class PDFOpsTests: CoreTestCase {
    private func report() throws -> URL { try Fixtures.textPDF(in: dir) }

    func testToPNGFolderForMultiPage() async throws {
        let result = try await runOne("pdf.to.png", try report())
        let folder = result.outputs[0]
        XCTAssertEqual(folder.lastPathComponent, "report PNG")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(files, ["report-01.png", "report-02.png", "report-03.png"])
        XCTAssertEqual(result.note, "3 页 → 文件夹")
        XCTAssertEqual(Fixtures.image(at: folder.appendingPathComponent(files[0]))?.width, 1190)
    }

    func testToJPGSinglePage() async throws {
        let src = try Fixtures.textPDF(in: dir, name: "one.pdf", pages: [.init(title: "Only", body: ["x"])])
        let out = try await runOne("pdf.to.jpg", src).outputs[0]
        XCTAssertEqual(out.lastPathComponent, "one.jpg")
        XCTAssertEqual(Fixtures.type(of: out), "public.jpeg")
    }

    func testLongImage() async throws {
        let result = try await runOne("pdf.to.long", try report())
        XCTAssertEqual(result.note, "3 页拼成一张")
        let image = try XCTUnwrap(Fixtures.image(at: result.outputs[0]))
        XCTAssertEqual(image.width, 1242)
        let pageHeight = Int(842 * 1242.0 / 595)
        XCTAssertEqual(Double(image.height), Double(pageHeight * 3 + 32), accuracy: 6)
        XCTAssertEqual(result.outputs[0].lastPathComponent, "report 长图.jpg")
    }

    func testToTXTRebuildsParagraphs() async throws {
        let out = try await runOne("pdf.to.txt", try report()).outputs[0]
        let text = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(text.contains("Chapter 1"))
        XCTAssertTrue(text.contains("FormatWheel page 3 body text."))
    }

    func testToMarkdownInfersHeadings() async throws {
        let out = try await runOne("pdf.to.md", try report()).outputs[0]
        let md = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(md.contains("# Chapter 1"), md)
        XCTAssertTrue(md.contains("FormatWheel page 2 body text."), md)
    }

    func testToRTFAndHTML() async throws {
        XCTAssertNotNil(Platform.richText, "the host app installs the RTF/HTML codec")
        for fmt in ["rtf", "html"] {
            let out = try await runOne("pdf.to.\(fmt)", try report()).outputs[0]
            let back = try Platform.richText!.attributedString(from: Data(contentsOf: out), format: fmt)
            XCTAssertTrue(back.string.contains("Chapter 2"), fmt)
        }
    }

    func testTextExtractionFailsWithoutTextLayer() async throws {
        do {
            _ = try await runOne("pdf.to.txt", try Fixtures.scannedPDF(in: dir))
            XCTFail("expected an error")
        } catch let e as FWError {
            XCTAssertEqual(e.message, "这个 PDF 没有文字层，试试「工具 → 识字」")
        }
    }

    func testCompressShrinksImages() async throws {
        let src = try Fixtures.imagePDF(in: dir)
        let result = try await runOne("pdf.compress", src)
        XCTAssertLessThan(Fmt.size(of: result.outputs[0]), Fmt.size(of: src))
        XCTAssertEqual(result.outputs[0].lastPathComponent, "photos 压缩.pdf")
    }

    func testSplit() async throws {
        let result = try await runOne("pdf.split", try report())
        let files = try FileManager.default.contentsOfDirectory(atPath: result.outputs[0].path).sorted()
        XCTAssertEqual(files, ["report-1.pdf", "report-2.pdf", "report-3.pdf"])
        XCTAssertEqual(result.note, "拆成 3 个文件")
        XCTAssertEqual(result.outputs[0].lastPathComponent, "report 拆分")
    }

    func testMergePDFsAndImagesInOrder() async throws {
        let a = try report()
        let b = try Fixtures.textPDF(in: dir, name: "b.pdf", pages: [.init(title: "B", body: ["b"])])
        let img = try Fixtures.write(Fixtures.photo(), as: .png, to: dir.appendingPathComponent("c.png"))
        let summary = try await run("pdf.merge", [a, b, img])
        let merged = try XCTUnwrap(PDFDocument(url: summary.outputs[0]))
        XCTAssertEqual(merged.pageCount, 5)
        XCTAssertEqual(summary.outputs[0].lastPathComponent, "report 合并.pdf")
        XCTAssertTrue(merged.page(at: 3)?.string?.contains("B") == true)
    }

    func testRotate() async throws {
        let out = try await runOne("pdf.rotate", try report()).outputs[0]
        XCTAssertEqual(PDFDocument(url: out)?.page(at: 0)?.rotation, 90)
    }

    func testOCRScannedPDF() async throws {
        let summary = try await run("pdf.ocr", [try Fixtures.scannedPDF(in: dir)])
        let text = try String(contentsOf: summary.outputs[0], encoding: .utf8)
        XCTAssertTrue(text.contains("2049") && text.contains("Format"), text)
        XCTAssertEqual(clipboard.text, text)
    }

    func testStripRemovesAuthorAndLowersWantedLevel() async throws {
        let src = try report()
        let before = Privacy.pdf(src)
        XCTAssertEqual(before.level, 4)
        XCTAssertEqual(before.reasons, ["作者：Elise Chen", "制作软件", "主题 / 关键词"])
        let result = try await runOne("pdf.strip", src)
        let attrs = PDFDocument(url: result.outputs[0])?.documentAttributes ?? [:]
        XCTAssertNil(attrs[PDFDocumentAttribute.authorAttribute.rawValue])
        XCTAssertNil(attrs[PDFDocumentAttribute.keywordsAttribute.rawValue])
        XCTAssertEqual(Privacy.pdf(result.outputs[0]).level, 0)
        XCTAssertEqual(result.note, Privacy.evadedNote)
    }
}

/// pdf.mono: grayscale raster + invisible text layer + preserved rotation, annotations and outline.
final class PDFMonoTests: CoreTestCase {
    private func renderPage(_ page: CGPDFPage) -> CGImage { PDFOps.render(page, scale: 1)! }

    func testPagesAreGrayWithSameCountSizeAndSelectableText() async throws {
        let src = try Fixtures.textPDF(in: dir)
        let result = try await runOne("pdf.mono", src)
        let out = result.outputs[0]
        XCTAssertEqual(out.lastPathComponent, "report 黑白.pdf")
        let cg = try XCTUnwrap(CGPDFDocument(out as CFURL))
        XCTAssertEqual(cg.numberOfPages, 3)
        for i in 1...3 {
            let page = cg.page(at: i)!
            XCTAssertEqual(page.getBoxRect(.cropBox).size, CGSize(width: 595, height: 842))
            for s in Fixtures.samples(renderPage(page), grid: 16) {
                XCTAssertTrue(s.r == s.g && s.g == s.b, "page \(i) has a coloured pixel \(s)")
            }
        }
        let kit = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertTrue(kit.string?.contains("FormatWheel page 2 body text.") == true, kit.string ?? "")
        XCTAssertTrue(kit.page(at: 0)?.string?.contains("Chapter 1") == true)
        XCTAssertGreaterThan(kit.findString("Second line of page 3", withOptions: []).count, 0, "text must be searchable")
    }

    func testRotationAnnotationsAndOutlineSurvive() async throws {
        let src = try Fixtures.annotatedPDF(in: dir)
        let original = try XCTUnwrap(PDFDocument(url: src))
        XCTAssertEqual(original.page(at: 0)?.annotations.first { $0.type == "Link" && $0.url == nil }?.destination?.page.map(original.index(for:)), 2,
                       "fixture sanity: internal link resolves")
        let out = try await runOne("pdf.mono", src).outputs[0]
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 3)
        let p1 = try XCTUnwrap(doc.page(at: 0))
        XCTAssertEqual(p1.rotation, 90)
        XCTAssertEqual(p1.bounds(for: .cropBox).size, CGSize(width: 595, height: 842))

        let annotations = p1.annotations
        let web = annotations.first { $0.url?.absoluteString == "https://github.com/Elise616/FormatWheel" }
        XCTAssertNotNil(web, "URL link lost: \(annotations.map { $0.type ?? "?" })")
        XCTAssertEqual(web?.bounds, CGRect(x: 60, y: 300, width: 200, height: 30))
        let jump = annotations.first { $0.type == "Link" && $0.url == nil }
        let dest = jump?.destination ?? (jump?.action as? PDFActionGoTo)?.destination
        XCTAssertEqual(dest?.page.map(doc.index(for:)), 2, "internal link must point at the new page 3")
        XCTAssertTrue(annotations.contains { $0.type == "Highlight" && $0.contents == "check this" }, "highlight lost")
        XCTAssertNotNil(annotations.first { $0.type == "Highlight" }?.popup, "popup note lost")
        let field = annotations.first { $0.type == "Widget" }
        XCTAssertEqual(field?.fieldName, "customer")
        XCTAssertEqual(field?.widgetStringValue, "Ada")

        let chapter = try XCTUnwrap(doc.outlineRoot?.child(at: 0))
        XCTAssertEqual(chapter.label, "Chapter 3")
        XCTAssertEqual(chapter.destination?.page.map(doc.index(for:)), 2)
        XCTAssertEqual(chapter.child(at: 0)?.label, "Details")
        XCTAssertEqual(chapter.child(at: 0)?.destination?.page.map(doc.index(for:)), 1)
    }

    func testScannedPDFGetsOCRTextLayer() async throws {
        let out = try await runOne("pdf.mono", try Fixtures.scannedPDF(in: dir)).outputs[0]
        let text = PDFDocument(url: out)?.string ?? ""
        XCTAssertTrue(text.contains("2049") && text.contains("Format"), text)
    }

    func testResolutionSetting() async throws {
        let src = try Fixtures.textPDF(in: dir, name: "one.pdf", pages: [.init(title: "DPI", body: ["dots"])])
        var sizes: [Int: Int64] = [:]
        for dpi in [150, 300] {
            UserDefaults.standard.set(dpi, forKey: PDFMono.dpiKey)
            sizes[dpi] = Fmt.size(of: try await runOne("pdf.mono", src).outputs[0])
        }
        UserDefaults.standard.removeObject(forKey: PDFMono.dpiKey)
        XCTAssertEqual(PDFMono.dpi, 200)
        XCTAssertGreaterThan(sizes[300]!, sizes[150]!)
        let gray = PDFMono.renderGray(CGPDFDocument(src as CFURL)!.page(at: 1)!, box: CGRect(x: 0, y: 0, width: 595, height: 842), dpi: 200)!
        XCTAssertEqual(gray.width, Int((595.0 / 72 * 200).rounded()))
        XCTAssertEqual(gray.colorSpace?.model, .monochrome)
    }
}

/// The pdf.compress fallback re-serialises the whole document; nothing but big images may change.
final class PDFWriterTests: CoreTestCase {
    func testRecompressKeepsTextLinksFormsAndOutline() throws {
        let src = try Fixtures.annotatedPDF(in: dir)
        let out = dir.appendingPathComponent("rewritten.pdf")
        XCTAssertEqual(try PDFWriter.recompress(src, to: out), 0, "no big images to replace")
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 3)
        XCTAssertEqual(doc.page(at: 0)?.rotation, 90)
        XCTAssertTrue(doc.string?.contains("FormatWheel page 3 body text.") == true)
        let link = doc.page(at: 0)?.annotations.first { $0.type == "Link" && $0.url == nil }
        XCTAssertEqual(link?.destination?.page.map(doc.index(for:)), 2)
        XCTAssertEqual(doc.page(at: 0)?.annotations.first { $0.type == "Widget" }?.widgetStringValue, "Ada")
        XCTAssertEqual(doc.outlineRoot?.child(at: 0)?.label, "Chapter 3")
    }

    func testRecompressShrinksPhotoPages() throws {
        let src = try Fixtures.imagePDF(in: dir)
        let out = dir.appendingPathComponent("small.pdf")
        XCTAssertEqual(try PDFWriter.recompress(src, to: out), 1)
        XCTAssertLessThan(Fmt.size(of: out), Fmt.size(of: src) / 10)
        let page = try XCTUnwrap(CGPDFDocument(out as CFURL)?.page(at: 1))
        XCTAssertEqual(page.getBoxRect(.mediaBox).size, CGSize(width: 595, height: 842))
        XCTAssertNotNil(PDFOps.render(page, scale: 1))
    }
}
