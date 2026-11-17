import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Minimal PDF serializer over CGPDF objects (iOS PDFKit's writer ignores image options and corrupts
/// page links it creates in memory, so these two jobs are done here instead):
///
/// - pdf.compress fallback (`recompress`): re-serialises the document object by object and replaces only
///   big 8-bit RGB / gray images with downsampled JPEGs. Text, vector art, fonts, links, annotations,
///   forms and the outline are copied unchanged.
/// - pdf.mono assembly (`assemble`): new pages from one document, annotations / outline / form / named
///   destinations from another, with every page reference re-pointed (`pageMap`).
final class PDFWriter {
    /// Upstream-like "optimise for screen": long side ≤ 1600 px, JPEG quality 0.7.
    static let maxSide: CGFloat = 1600
    static let quality: Double = 0.7

    private let doc: CGPDFDocument
    private let recompressImages: Bool
    /// Source page dictionary → object number of the page that replaces it.
    private var pageMap: [UnsafeRawPointer: Int] = [:]
    private var numbers: [UnsafeRawPointer: Int] = [:]
    private var queue: [(Int, Item)] = []
    private var offsets: [Int: Int] = [:]
    private var output = OutputStreamWriter()
    private(set) var replacedImages = 0

    private enum Item {
        case dict(CGPDFDictionaryRef)
        case stream(CGPDFStreamRef)
    }

    init(_ doc: CGPDFDocument, recompressImages: Bool) {
        self.doc = doc
        self.recompressImages = recompressImages
    }

    private static func key(_ d: CGPDFDictionaryRef) -> UnsafeRawPointer { unsafeBitCast(d, to: UnsafeRawPointer.self) }

    static func recompress(_ source: URL, to out: URL) throws -> Int {
        guard let doc = CGPDFDocument(source as CFURL), let catalog = doc.catalog else { throw FWError(L("打不开这个 PDF")) }
        if doc.isEncrypted { throw FWError(L("这个 PDF 有密码保护")) }
        let writer = PDFWriter(doc, recompressImages: true)
        guard writer.output.open(out) else { throw FWError(L("保存失败")) }
        writer.output.append("%PDF-1.7\n%\u{E2}\u{E3}\u{CF}\u{D3}\n")
        let root = writer.number(.dict(catalog))
        let info = doc.info.map { writer.number(.dict($0)) }
        try writer.finish(root: root, info: info)
        return writer.replacedImages
    }

    /// Writes `pages` (one per page of `source`) with `source`'s /Rotate, annotations, outline, AcroForm,
    /// named destinations and document info. Page references inside copied objects point at the new pages.
    static func assemble(pages: CGPDFDocument, source: CGPDFDocument, to out: URL) throws {
        guard pages.numberOfPages == source.numberOfPages, let sourceCatalog = source.catalog else { throw FWError(L("生成 PDF 失败")) }
        let writer = PDFWriter(pages, recompressImages: false)
        guard writer.output.open(out) else { throw FWError(L("保存失败")) }
        writer.output.append("%PDF-1.7\n%\u{E2}\u{E3}\u{CF}\u{D3}\n")
        let count = pages.numberOfPages
        let root = writer.reserve(), tree = writer.reserve()
        var kids: [Int] = []
        for i in 1...count {
            let n = writer.reserve()
            kids.append(n)
            if let page = source.page(at: i), let dict = page.dictionary { writer.pageMap[key(dict)] = n }
        }
        for i in 1...count {
            guard let newPage = pages.page(at: i), let dict = newPage.dictionary, let old = source.page(at: i) else { continue }
            var extra = "/Parent \(tree) 0 R"
            let rotation = ((old.rotationAngle % 360) + 360) % 360
            if rotation != 0 { extra += " /Rotate \(rotation)" }
            var annots: CGPDFArrayRef?
            if let oldDict = old.dictionary, CGPDFDictionaryGetArray(oldDict, "Annots", &annots), let annots {
                extra += " /Annots " + writer.array(annots)
            }
            writer.write(kids[i - 1], "<< " + writer.entries(dict, drop: ["Parent", "Annots", "Rotate"]) + " " + extra + " >>")
        }
        writer.write(tree, "<< /Type /Pages /Kids [" + kids.map { "\($0) 0 R" }.joined(separator: " ") + "] /Count \(count) >>")
        var catalog = "/Type /Catalog /Pages \(tree) 0 R"
        for name in ["Outlines", "Dests", "Names", "AcroForm", "PageMode", "PageLayout", "ViewerPreferences", "Lang"] {
            var obj: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(sourceCatalog, name, &obj), let obj { catalog += " /\(name) " + writer.object(obj) }
        }
        writer.write(root, "<< " + catalog + " >>")
        let info = source.info.map { writer.number(.dict($0)) }
        try writer.finish(root: root, info: info)
    }

    private func reserve() -> Int {
        let n = numbers.count + reserved + 1
        reserved += 1
        return n
    }
    private var reserved = 0

    private func write(_ n: Int, _ body: String) {
        offsets[n] = output.position
        output.append("\(n) 0 obj\n" + body + "\nendobj\n")
    }

    private func finish(root: Int, info: Int?) throws {
        while !queue.isEmpty {
            let (n, item) = queue.removeFirst()
            try autoreleasepool { try emit(n, item) }
        }
        let xref = output.position
        let count = (offsets.keys.max() ?? 0) + 1
        var table = "xref\n0 \(count)\n0000000000 65535 f \n"
        for i in 1..<count {
            table += offsets[i].map { String(format: "%010d 00000 n \n", $0) } ?? "0000000000 65535 f \n"
        }
        output.append(table)
        output.append("trailer\n<< /Size \(count) /Root \(root) 0 R" + (info.map { " /Info \($0) 0 R" } ?? "") + " >>\nstartxref\n\(xref)\n%%EOF\n")
        guard output.close() else { throw FWError(L("保存失败")) }
    }

    private func number(_ item: Item) -> Int {
        let key: UnsafeRawPointer
        switch item {
        case .dict(let d): key = Self.key(d)
        case .stream(let s): key = unsafeBitCast(s, to: UnsafeRawPointer.self)
        }
        if let n = numbers[key] { return n }
        let n = numbers.count + reserved + 1
        numbers[key] = n
        queue.append((n, item))
        return n
    }

    private func emit(_ n: Int, _ item: Item) throws {
        offsets[n] = output.position
        switch item {
        case .dict(let d):
            output.append("\(n) 0 obj\n<< " + entries(d) + " >>\nendobj\n")
        case .stream(let s):
            guard let dict = CGPDFStreamGetDictionary(s) else { throw FWError(L("压缩失败")) }
            var format = CGPDFDataFormat.raw
            guard let data = CGPDFStreamCopyData(s, &format) as Data? else { throw FWError(L("压缩失败")) }
            var body = data
            var replace: [String: String] = [:]
            var drop: Set<String> = ["Filter", "DecodeParms", "Length", "DL", "F", "FFilter", "FDecodeParms"]
            if recompressImages, let jpeg = smallerJPEG(dict: dict, data: data, format: format) {
                body = jpeg.data
                replace = ["Filter": "/DCTDecode", "Width": "\(jpeg.width)", "Height": "\(jpeg.height)", "BitsPerComponent": "8"]
                drop.formUnion(["Width", "Height", "BitsPerComponent", "Decode"])
                replacedImages += 1
            } else {
                switch format {
                case .jpegEncoded: replace["Filter"] = "/DCTDecode"
                case .JPEG2000: replace["Filter"] = "/JPXDecode"
                default:
                    body = Self.zlib(data)
                    replace["Filter"] = "/FlateDecode"
                }
            }
            replace["Length"] = "\(body.count)"
            output.append("\(n) 0 obj\n<< " + entries(dict, drop: drop, add: replace) + " >>\nstream\n")
            output.append(body)
            output.append("\nendstream\nendobj\n")
        }
    }

    // MARK: - Objects

    private func entries(_ d: CGPDFDictionaryRef, drop: Set<String> = [], add: [String: String] = [:]) -> String {
        var parts: [String] = []
        CGPDFDictionaryApplyBlock(d, { key, value, _ in
            let name = String(cString: key)
            if !drop.contains(name) { parts.append("/" + Self.escapeName(name) + " " + self.object(value)) }
            return true
        }, nil)
        for (k, v) in add.sorted(by: { $0.key < $1.key }) { parts.append("/\(k) \(v)") }
        return parts.joined(separator: " ")
    }

    private func object(_ obj: CGPDFObjectRef) -> String {
        switch CGPDFObjectGetType(obj) {
        case .null: return "null"
        case .boolean:
            var b: CGPDFBoolean = 0
            CGPDFObjectGetValue(obj, .boolean, &b)
            return b != 0 ? "true" : "false"
        case .integer:
            var i: CGPDFInteger = 0
            CGPDFObjectGetValue(obj, .integer, &i)
            return "\(i)"
        case .real:
            var r: CGPDFReal = 0
            CGPDFObjectGetValue(obj, .real, &r)
            return String(format: "%.6f", Double(r)).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        case .name:
            var p: UnsafePointer<CChar>?
            CGPDFObjectGetValue(obj, .name, &p)
            return "/" + Self.escapeName(p.map { String(cString: $0) } ?? "")
        case .string:
            var s: CGPDFStringRef?
            CGPDFObjectGetValue(obj, .string, &s)
            guard let s, let bytes = CGPDFStringGetBytePtr(s) else { return "()" }
            let data = Data(bytes: bytes, count: CGPDFStringGetLength(s))
            return "<" + data.map { String(format: "%02x", $0) }.joined() + ">"
        case .array:
            var a: CGPDFArrayRef?
            CGPDFObjectGetValue(obj, .array, &a)
            guard let a else { return "[]" }
            return array(a)
        case .dictionary:
            var d: CGPDFDictionaryRef?
            CGPDFObjectGetValue(obj, .dictionary, &d)
            guard let d else { return "null" }
            if let page = pageMap[Self.key(d)] { return "\(page) 0 R" }
            return "\(number(.dict(d))) 0 R"
        case .stream:
            var s: CGPDFStreamRef?
            CGPDFObjectGetValue(obj, .stream, &s)
            guard let s else { return "null" }
            return "\(number(.stream(s))) 0 R"
        @unknown default:
            return "null"
        }
    }

    private func array(_ a: CGPDFArrayRef) -> String {
        var items: [String] = []
        for i in 0..<CGPDFArrayGetCount(a) {
            var o: CGPDFObjectRef?
            if CGPDFArrayGetObject(a, i, &o), let o { items.append(object(o)) }
        }
        return "[" + items.joined(separator: " ") + "]"
    }

    private static func escapeName(_ name: String) -> String {
        var out = ""
        for byte in name.utf8 {
            let c = Character(UnicodeScalar(byte))
            if byte < 0x21 || byte > 0x7E || "#()<>[]{}/%".contains(c) { out += String(format: "#%02X", byte) } else { out.append(c) }
        }
        return out
    }

    // MARK: - Images

    private func smallerJPEG(dict: CGPDFDictionaryRef, data: Data, format: CGPDFDataFormat) -> (data: Data, width: Int, height: Int)? {
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" else { return nil }
        var flag: CGPDFBoolean = 0
        if CGPDFDictionaryGetBoolean(dict, "ImageMask", &flag), flag != 0 { return nil }
        var decode: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "Decode", &decode) { return nil }
        var w: CGPDFInteger = 0, h: CGPDFInteger = 0, bpc: CGPDFInteger = 8, length: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(dict, "Width", &w), CGPDFDictionaryGetInteger(dict, "Height", &h), w > 0, h > 0 else { return nil }
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
        CGPDFDictionaryGetInteger(dict, "Length", &length)
        guard let components = colorComponents(dict), components == 1 || components == 3 else { return nil }

        let image: CGImage?
        switch format {
        case .raw:
            guard bpc == 8, data.count >= w * h * components else { return nil }
            let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            image = CGDataProvider(data: data as CFData).flatMap {
                CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8 * components, bytesPerRow: w * components, space: space,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: $0, decode: nil,
                        shouldInterpolate: true, intent: .defaultIntent)
            }
        case .jpegEncoded:
            image = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        default:
            return nil
        }
        guard var pixels = image else { return nil }
        let long = CGFloat(max(w, h))
        if long > Self.maxSide {
            let scale = Self.maxSide / long
            let nw = max(1, Int(CGFloat(w) * scale)), nh = max(1, Int(CGFloat(h) * scale))
            let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: components == 1 ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(pixels, in: CGRect(x: 0, y: 0, width: nw, height: nh))
            guard let small = ctx.makeImage() else { return nil }
            pixels = small
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, pixels, [kCGImageDestinationLossyCompressionQuality: Self.quality,
                                                  kCGImageDestinationEmbedThumbnail: false] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let jpeg = out as Data
        // Only worth it when clearly smaller than what is stored now.
        let stored = length > 0 ? length : data.count
        guard jpeg.count < Int(Double(stored) * 0.9) else { return nil }
        return (jpeg, pixels.width, pixels.height)
    }

    /// Component count of the image's colour space (DeviceGray/RGB, CalGray/RGB, ICCBased N).
    private func colorComponents(_ dict: CGPDFDictionaryRef) -> Int? {
        var name: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dict, "ColorSpace", &name), let name {
            switch String(cString: name) {
            case "DeviceGray", "CalGray", "G": return 1
            case "DeviceRGB", "CalRGB", "RGB": return 3
            default: return nil
            }
        }
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, "ColorSpace", &array), let array, CGPDFArrayGetCount(array) >= 2 else { return nil }
        var family: UnsafePointer<CChar>?
        guard CGPDFArrayGetName(array, 0, &family), let family else { return nil }
        switch String(cString: family) {
        case "ICCBased":
            var stream: CGPDFStreamRef?
            guard CGPDFArrayGetStream(array, 1, &stream), let stream, let d = CGPDFStreamGetDictionary(stream) else { return nil }
            var n: CGPDFInteger = 0
            return CGPDFDictionaryGetInteger(d, "N", &n) ? n : nil
        case "CalGray": return 1
        case "CalRGB": return 3
        default: return nil
        }
    }

    /// zlib (RFC 1950) wrapper around raw DEFLATE, as /FlateDecode expects.
    static func zlib(_ data: Data) -> Data {
        var out = Data([0x78, 0x9C])
        if !data.isEmpty {
            let capacity = data.count + data.count / 10 + 1024
            var buffer = [UInt8](repeating: 0, count: capacity)
            let written = data.withUnsafeBytes { src in
                compression_encode_buffer(&buffer, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
            if written > 0 {
                out.append(buffer, count: written)
            } else {
                // Incompressible or too big for one buffer: stored DEFLATE blocks.
                var offset = 0
                while offset < data.count {
                    let n = min(65_535, data.count - offset)
                    let last: UInt8 = offset + n >= data.count ? 1 : 0
                    out.append(contentsOf: [last, UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)])
                    out.append(data.subdata(in: offset..<offset + n))
                    offset += n
                }
            }
        } else {
            out.append(contentsOf: [0x03, 0x00])
        }
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        let adler = (b << 16) | a
        out.append(contentsOf: [UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])
        return out
    }
}

/// Buffered file writer that tracks the byte offset (needed for the xref table).
private struct OutputStreamWriter {
    private var handle: FileHandle?
    private var buffer = Data()
    private(set) var position = 0

    mutating func open(_ url: URL) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        return handle != nil
    }

    mutating func append(_ string: String) { append(Data(string.utf8)) }

    mutating func append(_ data: Data) {
        buffer.append(data)
        position += data.count
        if buffer.count > 1 << 20 { flush() }
    }

    private mutating func flush() {
        try? handle?.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    mutating func close() -> Bool {
        flush()
        do { try handle?.close() } catch { return false }
        return true
    }
}
