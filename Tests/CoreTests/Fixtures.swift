import AVFoundation
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Test inputs generated on the fly — no binary fixtures in the repo.
enum Fixtures {
    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fw-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Audio

    /// A 16-bit PCM WAV with a sine tone.
    static func sineWAV(seconds: Double = 1, frequency: Double = 440, sampleRate: Double = 44_100,
                        channels: AVAudioChannelCount = 2, in dir: URL, name: String = "sine.wav") throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<Int(channels) {
            let data = buffer.floatChannelData![c]
            for i in 0..<Int(frames) { data[i] = Float(sin(2 * .pi * frequency * Double(i) / sampleRate) * 0.5) }
        }
        try file.write(from: buffer)
        return url
    }

    static func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    // MARK: - Images

    /// A photo-like picture: colour gradients plus deterministic noise (so it compresses like a photo).
    static func photo(width: Int = 640, height: Int = 480, alpha: Bool = false, seed: UInt32 = 1) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var state = seed
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 1_664_525 &+ 1_013_904_223
                let noise = Int(state >> 27) - 16
                let i = (y * width + x) * 4
                let inside = !alpha || hypot(Double(x - width / 2), Double(y - height / 2)) < Double(min(width, height)) * 0.4
                let a = inside ? 255 : 0
                func c(_ v: Int) -> UInt8 { UInt8(max(0, min(255, v + noise)) * a / 255) }
                px[i] = c(x * 255 / width)
                px[i + 1] = c(y * 255 / height)
                px[i + 2] = c(128 + Int(60 * sin(Double(x + y) / 40)))
                px[i + 3] = UInt8(a)
            }
        }
        return ctx.makeImage()!
    }

    /// Big black text on white, for OCR.
    static func textImage(_ lines: [String], width: Int = 1200, height: Int = 500) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (n, text) in lines.enumerated() {
            drawText(text, size: 64, at: CGPoint(x: 40, y: CGFloat(height) - 110 - CGFloat(n) * 110), in: ctx)
        }
        return ctx.makeImage()!
    }

    /// A dog (Apple Color Emoji, rendered large) on a plain light background — a clear, natural
    /// foreground subject for Vision's foreground-instance mask.
    static func subjectImage() -> CGImage {
        let w = 900, h = 700
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 480, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "🐕", attributes: [.init(kCTFontAttributeName as String): font]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: (CGFloat(w) - CGFloat(width)) / 2, y: 140)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    static func drawText(_ text: String, size: CGFloat, at point: CGPoint, in ctx: CGContext, bold: Bool = false) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        ctx.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
    }

    static func write(_ image: CGImage, as type: UTType, to url: URL, quality: Double = 1, properties: [CFString: Any] = [:]) throws -> URL {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props = properties
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "fixtures", code: 1) }
        return url
    }

    /// A JPEG with GPS, device model, capture date and body serial number — wanted level 5 upstream.
    static func trackedJPEG(in dir: URL, name: String = "IMG_2049.jpg") throws -> URL {
        let props: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 25.0330, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 121.5654, kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:21 14:39:22",
                kCGImagePropertyExifBodySerialNumber: "F2LXK0QJ1234",
            ],
        ]
        return try write(photo(), as: .jpeg, to: dir.appendingPathComponent(name), quality: 0.95, properties: props)
    }

    // MARK: - PDF

    struct PageSpec {
        var title: String
        var body: [String]
    }

    /// A text PDF (real text layer) with document info. Titles are drawn larger than body text.
    static func textPDF(in dir: URL, name: String = "report.pdf", pages: [PageSpec]? = nil,
                        author: String? = "Elise Chen", creator: String? = "Pages", keywords: String? = "secret, plan",
                        size: CGSize = CGSize(width: 595, height: 842)) throws -> URL {
        let url = dir.appendingPathComponent(name)
        var info: [CFString: Any] = [kCGPDFContextTitle: "Report"]
        if let author { info[kCGPDFContextAuthor] = author }
        if let creator { info[kCGPDFContextCreator] = creator }
        if let keywords { info[kCGPDFContextKeywords] = keywords }
        var box = CGRect(origin: .zero, size: size)
        let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary)!
        let specs = pages ?? (1...3).map { PageSpec(title: "Chapter \($0)", body: ["FormatWheel page \($0) body text.", "Second line of page \($0)."]) }
        for spec in specs {
            ctx.beginPDFPage(nil)
            drawText(spec.title, size: 28, at: CGPoint(x: 60, y: size.height - 100), in: ctx, bold: true)
            for (n, line) in spec.body.enumerated() {
                drawText(line, size: 14, at: CGPoint(x: 60, y: size.height - 150 - CGFloat(n) * 22), in: ctx)
            }
            ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 60, y: 100, width: 200, height: 80))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// A "scanned" PDF: each page is only an image of text, no text layer.
    static func scannedPDF(in dir: URL, lines: [String] = ["FormatWheel Scanner", "Invoice 2049"]) throws -> URL {
        let url = dir.appendingPathComponent("scan.pdf")
        var box = CGRect(x: 0, y: 0, width: 600, height: 250)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.draw(textImage(lines), in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }

    /// A PDF whose single page embeds a big uncompressed-looking photo (pdf.compress has work to do).
    static func imagePDF(in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("photos.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.draw(photo(width: 2400, height: 3200), in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }

    /// A hand-written 3-page PDF (real text layer; page 1 rotated 90°) with a URL link, an internal link
    /// to page 3, a highlight with a popup note, a form text field (AcroForm) and a two-level outline.
    /// Written by hand because iOS PDFKit corrupts page links it creates in memory.
    static func annotatedPDF(in dir: URL) throws -> URL {
        func content(_ title: String, _ body: String) -> String {
            let ops = "BT /F1 28 Tf 60 740 Td (\(title)) Tj ET BT /F1 14 Tf 60 700 Td (\(body)) Tj ET 1 0 0 rg 60 100 200 80 re f"
            return "<< /Length \(ops.utf8.count) >>\nstream\n\(ops)\nendstream"
        }
        let objects = [
            /* 1 */ "<< /Type /Catalog /Pages 2 0 R /Outlines 12 0 R /AcroForm << /Fields [11 0 R] >> >>",
            /* 2 */ "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 /MediaBox [0 0 595 842] /Resources << /Font << /F1 15 0 R >> >> >>",
            /* 3 */ "<< /Type /Page /Parent 2 0 R /Rotate 90 /Contents 6 0 R /Annots [8 0 R 9 0 R 10 0 R 11 0 R 16 0 R] >>",
            /* 4 */ "<< /Type /Page /Parent 2 0 R /Contents 7 0 R >>",
            /* 5 */ "<< /Type /Page /Parent 2 0 R /Contents 17 0 R >>",
            /* 6 */ content("Chapter 1", "FormatWheel page 1 body text."),
            /* 7 */ content("Chapter 2", "FormatWheel page 2 body text."),
            /* 8 */ "<< /Type /Annot /Subtype /Link /Rect [60 300 260 330] /Border [0 0 0] /A << /S /URI /URI (https://github.com/Elise616/FormatWheel) >> >>",
            /* 9 */ "<< /Type /Annot /Subtype /Link /Rect [60 250 260 280] /Border [0 0 0] /Dest [5 0 R /XYZ 0 842 0] >>",
            /* 10 */ "<< /Type /Annot /Subtype /Highlight /Rect [55 735 355 770] /QuadPoints [55 770 355 770 55 735 355 735] /C [1 1 0] /Contents (check this) /Popup 16 0 R /P 3 0 R >>",
            /* 11 */ "<< /Type /Annot /Subtype /Widget /FT /Tx /T (customer) /V (Ada) /Rect [60 400 260 424] /P 3 0 R /F 4 /DA (/Helv 12 Tf 0 g) >>",
            /* 12 */ "<< /Type /Outlines /First 13 0 R /Last 13 0 R /Count 1 >>",
            /* 13 */ "<< /Title (Chapter 3) /Parent 12 0 R /Dest [5 0 R /XYZ 0 842 0] /First 14 0 R /Last 14 0 R /Count 1 >>",
            /* 14 */ "<< /Title (Details) /Parent 13 0 R /Dest [4 0 R /XYZ 0 0 0] >>",
            /* 15 */ "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            /* 16 */ "<< /Type /Annot /Subtype /Popup /Rect [360 735 560 835] /Parent 10 0 R /Open false >>",
            /* 17 */ content("Chapter 3", "FormatWheel page 3 body text."),
        ]
        var pdf = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n" + offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = dir.appendingPathComponent("annotated.pdf")
        try Data(pdf.utf8).write(to: url)
        return url
    }

    // MARK: - Pixels

    /// RGBA samples of a CGImage on a grid (for gray / alpha checks).
    static func samples(_ image: CGImage, grid: Int = 12) -> [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var out: [(UInt8, UInt8, UInt8, UInt8)] = []
        for gy in 0..<grid {
            for gx in 0..<grid {
                let x = min(w - 1, gx * w / grid + w / (2 * grid)), y = min(h - 1, gy * h / grid + h / (2 * grid))
                let i = (y * w + x) * 4
                out.append((px[i], px[i + 1], px[i + 2], px[i + 3]))
            }
        }
        return out
    }

    static func image(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func type(of url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceGetType(src) as String?
    }
}
