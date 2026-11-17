import CoreText
import Foundation
import PDFKit

/// pdf.mono on iOS. Upstream re-draws pages through macOS's Quartz "Gray Tone" filter (vector output);
/// iOS has no such filter, so (decided with the project owner, see PARITY.md §5):
///
/// 1. Each page is rasterised in DeviceGray at `dpi` (setting 150 / 200 / 300, default 200), unrotated,
///    into a page with the original crop box, then streamed straight into the output (one page in memory).
/// 2. An invisible text layer keeps the page selectable / searchable: the original PDF's own text and
///    positions when it has a text layer, otherwise Vision OCR (the pdf.ocr pipeline).
/// 3. `PDFWriter.assemble` restores each page's /Rotate and copies annotations (link destinations re-pointed
///    at the new pages), the outline (bookmarks), form fields and named destinations.
enum PDFMono {
    static let dpiKey = "pdfMonoDPI"
    static let allowedDPI = [150, 200, 300]

    /// The user's setting; 200 when unset.
    static var dpi: Int {
        let v = UserDefaults.standard.integer(forKey: dpiKey)
        return allowedDPI.contains(v) ? v : 200
    }

    static func convert(_ source: URL, to out: URL, dpi: Int, progress: ProgressFn) async throws {
        let cgDoc = try PDFOps.pages(source)
        let kitDoc = try PDFOps.open(source)
        let count = cgDoc.numberOfPages
        let tmp = try Out.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let raster = tmp.appendingPathComponent("gray.pdf")

        guard let ctx = CGContext(raster as CFURL, mediaBox: nil, [kCGPDFContextCreator: "格式轮盘"] as CFDictionary) else {
            throw FWError(L("无法创建 PDF"))
        }
        for i in 1...count {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = cgDoc.page(at: i) else { return }
                let box = page.getBoxRect(.cropBox)
                guard let gray = renderGray(page, box: box, dpi: dpi) else { throw FWError(L("页面渲染失败")) }
                var media = box
                ctx.beginPage(mediaBox: &media)
                ctx.interpolationQuality = .high
                ctx.draw(PDFMaker.jpegBacked(gray, quality: 0.85), in: box)
                let lines = textLines(kitDoc.page(at: i - 1)) ?? ocrLines(gray, box: box)
                drawInvisible(lines, in: ctx)
                ctx.endPage()
            }
            progress(Double(i) / Double(count) * 0.9)
        }
        ctx.closePDF()

        // Rotation, annotations (links re-pointed at the new pages), outline, form fields and named
        // destinations come from the original; written by PDFWriter because iOS PDFKit corrupts page
        // links it has to create in memory.
        guard let rasterDoc = CGPDFDocument(raster as CFURL) else { throw FWError(L("生成 PDF 失败")) }
        try PDFWriter.assemble(pages: rasterDoc, source: cgDoc, to: out)
        guard let check = PDFDocument(url: out), check.pageCount == count else { throw FWError(L("生成 PDF 失败")) }
        progress(1)
    }

    /// The page's crop box, unrotated, in DeviceGray at `dpi`.
    static func renderGray(_ page: CGPDFPage, box: CGRect, dpi: Int) -> CGImage? {
        var scale = CGFloat(dpi) / 72
        let maxPixels: CGFloat = 60_000_000
        if box.width * scale * box.height * scale > maxPixels { scale = sqrt(maxPixels / (box.width * box.height)) }
        let w = max(1, Int((box.width * scale).rounded())), h = max(1, Int((box.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(h) / box.height)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    struct TextLine {
        let text: String
        /// In page space (the crop box's coordinate system).
        let rect: CGRect
    }

    /// The original PDF's text, line by line with positions; nil when the page has no text layer.
    static func textLines(_ page: PDFPage?) -> [TextLine]? {
        guard let page, let selection = page.selection(for: page.bounds(for: .cropBox)) else { return nil }
        let lines = selection.selectionsByLine().compactMap { line -> TextLine? in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let rect = line.bounds(for: page)
            return rect.width > 0 && rect.height > 0 ? TextLine(text: text, rect: rect) : nil
        }
        return lines.isEmpty ? nil : lines
    }

    /// Vision OCR on the rendered page (scanned documents).
    static func ocrLines(_ image: CGImage, box: CGRect) -> [TextLine] {
        let found = (try? ImageOps.recognizeLines(image)) ?? []
        return found.map { line in
            TextLine(text: line.text, rect: CGRect(x: box.minX + line.box.minX * box.width, y: box.minY + line.box.minY * box.height,
                                                   width: line.box.width * box.width, height: line.box.height * box.height))
        }
    }

    /// Draws text in rendering mode "invisible", each line stretched to its original width.
    static func drawInvisible(_ lines: [TextLine], in ctx: CGContext) {
        guard !lines.isEmpty else { return }
        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        for line in lines {
            let size = max(1, line.rect.height * 0.85)
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributed = NSAttributedString(string: line.text, attributes: [.init(kCTFontAttributeName as String): font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, &descent, nil))
            guard width > 0 else { continue }
            ctx.textMatrix = CGAffineTransform(scaleX: line.rect.width / width, y: 1)
            ctx.textPosition = CGPoint(x: line.rect.minX, y: line.rect.minY + min(descent, line.rect.height * 0.2))
            CTLineDraw(ctLine, ctx)
        }
        ctx.restoreGState()
    }
}
