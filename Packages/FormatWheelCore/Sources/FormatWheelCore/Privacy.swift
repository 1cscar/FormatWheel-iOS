import Foundation
import ImageIO
import PDFKit

/// GTA-style wanted level for a file: how much of it can be traced back to you (upstream `Wanted`).
public struct Wanted: Equatable, Sendable {
    public var level = 0
    public var reasons: [String] = []
    public init(level: Int = 0, reasons: [String] = []) {
        self.level = level
        self.reasons = reasons
    }
}

/// Port of upstream Sources/Privacy.swift — image and PDF parts (P1). Video (P2) and Word (P3) follow.
public enum Privacy {
    // MARK: - Scanning

    public static func scan(_ files: [URL]) async -> Wanted {
        var worst = Wanted()
        var flagged = 0
        for url in files.prefix(24) {
            let found = await scan(url)
            if found.level > 0 { flagged += 1 }
            if found.level > worst.level { worst = found }
        }
        if flagged > 1 { worst.reasons.append(L("%lld 个文件留有痕迹", flagged)) }
        return worst
    }

    public static func scan(_ url: URL) async -> Wanted {
        var found: Wanted
        switch FileKind.of(url) {
        case .image: found = image(url)
        case .pdf: found = pdf(url)
        // Video (ffprobe/AVFoundation tags) arrives in P2, Word docProps in P3.
        default: found = Wanted()
        }
        found.level = min(found.level, 5)
        return found
    }

    static func image(_ url: URL) -> Wanted {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, CGImageSourceGetPrimaryImageIndex(src), nil) as? [CFString: Any] else {
            return Wanted()
        }
        var found = Wanted()
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        if gps[kCGImagePropertyGPSLatitude] != nil {
            found.level += 2
            found.reasons.append(L("GPS 定位"))
        }
        if let model = nonEmpty(tiff[kCGImagePropertyTIFFModel]) ?? nonEmpty(exif[kCGImagePropertyExifLensModel]) {
            found.level += 1
            found.reasons.append(String(model.prefix(24)))
        }
        if exif[kCGImagePropertyExifDateTimeOriginal] != nil {
            found.level += 1
            found.reasons.append(L("拍摄时间"))
        }
        if nonEmpty(exif[kCGImagePropertyExifBodySerialNumber]) != nil || nonEmpty(exif[kCGImagePropertyExifCameraOwnerName]) != nil
            || nonEmpty(tiff[kCGImagePropertyTIFFArtist]) != nil {
            found.level += 1
            found.reasons.append(L("机身序列号 / 作者"))
        }
        return found
    }

    static func pdf(_ url: URL) -> Wanted {
        guard let attributes = PDFDocument(url: url)?.documentAttributes else { return Wanted() }
        var found = Wanted()
        if let author = nonEmpty(attributes[PDFDocumentAttribute.authorAttribute.rawValue]) {
            found.level += 2
            found.reasons.append(L("作者：%@", String(author.prefix(16))))
        }
        if nonEmpty(attributes[PDFDocumentAttribute.creatorAttribute.rawValue]) != nil {
            found.level += 1
            found.reasons.append(L("制作软件"))
        }
        if nonEmpty(attributes[PDFDocumentAttribute.keywordsAttribute.rawValue]) != nil
            || nonEmpty(attributes[PDFDocumentAttribute.subjectAttribute.rawValue]) != nil {
            found.level += 1
            found.reasons.append(L("主题 / 关键词"))
        }
        // Dates are left out on purpose: saving any PDF stamps a fresh one, so they aren't a trail.
        return found
    }

    static func nonEmpty(_ value: Any?) -> String? {
        let string: String?
        if let s = value as? String { string = s } else if let a = value as? [String] { string = a.joined(separator: " ") } else { string = nil }
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Lying low (去隐私)

    public static var evadedNote: String { L("已甩掉警察：定位、设备和作者信息都抹掉了") }

    static func stripPDF(_ url: URL) throws -> OpResult {
        guard let doc = PDFDocument(url: url) else { throw FWError(L("打不开这个 PDF")) }
        if doc.isLocked { throw FWError(L("这个 PDF 有密码保护")) }
        var attributes = doc.documentAttributes ?? [:]
        let personal: [PDFDocumentAttribute] = [.authorAttribute, .creatorAttribute, .producerAttribute, .subjectAttribute,
                                                .keywordsAttribute, .creationDateAttribute, .modificationDateAttribute]
        for key in personal { attributes.removeValue(forKey: key.rawValue) }
        doc.documentAttributes = attributes
        let out = Out.url(for: url, suffix: L("去隐私"), ext: "pdf")
        guard doc.write(to: out) else { throw FWError(L("保存失败")) }
        return OpResult(outputs: [out], note: evadedNote)
    }
}
