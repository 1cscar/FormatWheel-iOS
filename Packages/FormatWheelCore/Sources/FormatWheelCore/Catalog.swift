import Foundation
import ImageIO
import UniformTypeIdentifiers

// Port of upstream Sources/Catalog.swift. Pages, slot order, labels, traits and multi-file logic are
// verbatim; the only changes are `L()` for localisation and `Requirement` (device capabilities) in
// place of `Shell.has` (Homebrew tools). `Tests/CoreTests/CatalogParityTests` checks it against upstream.

public enum FileKind: String, Sendable {
    case image, pdf, video, audio, document, other

    public var title: String {
        switch self {
        case .image: return L("图片")
        case .pdf: return "PDF"
        case .video: return L("视频")
        case .audio: return L("音频")
        case .document: return L("文档")
        case .other: return L("文件")
        }
    }

    static let documentExts: Set<String> = ["txt", "text", "md", "markdown", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive"]
    static let extraVideoExts: Set<String> = ["webm", "mkv", "flv", "avi", "wmv", "ts", "m2ts", "mts", "3gp", "ogv"]
    static let extraAudioExts: Set<String> = ["opus", "ogg", "oga", "wma", "ape", "amr", "flac"]

    public static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return ext == "rtfd" ? .document : .other
        }
        if ext == "pdf" { return .pdf }
        if documentExts.contains(ext) { return .document }
        if extraVideoExts.contains(ext) { return .video }
        if extraAudioExts.contains(ext) { return .audio }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image), ImageSupport.readable.contains(type.identifier) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .other
    }
}

enum ImageSupport {
    static let readable: Set<String> = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
}

/// One slot on the wheel.
public struct WheelOption: Sendable {
    public let id: String
    /// Big label drawn in the slot (format name); `symbol` is used when this is nil.
    public var big: String?
    public var symbol: String?
    /// Small caption under the icon — the slot's "ammo count".
    public var ammo: String
    public var title: String
    public var detail: String
    public var enabled = true
    /// Why the slot is unavailable.
    public var note: String?
    /// Stat bar values (0...1) after the action, compared with the source's.
    public var stats: [Double]?
    /// Capability the slot needs (upstream: an external tool).
    public var requires: Requirement?

    public init(id: String, big: String? = nil, symbol: String? = nil, ammo: String, title: String, detail: String,
                enabled: Bool = true, note: String? = nil, stats: [Double]? = nil, requires: Requirement? = nil) {
        self.id = id
        self.big = big
        self.symbol = symbol
        self.ammo = ammo
        self.title = title
        self.detail = detail
        self.enabled = enabled
        self.note = note
        self.stats = stats
        self.requires = requires
    }

    /// Marks the slot 「未装备」 when its requirement is missing.
    mutating func equip(_ requirement: Requirement, tools: Tools) {
        requires = requirement
        guard !tools.has(requirement) else { return }
        enabled = false
        ammo = L("未装备")
        note = requirement.unavailableReason
    }
}

public struct WheelPage: Sendable {
    public let name: String
    public var slots: [WheelOption?]
}

public struct WheelContext: Sendable {
    public let files: [URL]
    public let kind: FileKind
    public var pages: [WheelPage]
    public var headline: String
    public var summary: String
    public let statLabels: [String]
    public let base: [Double]
}

public enum Catalog {
    public static func context(for files: [URL], tools: Tools = Tools.current) -> WheelContext {
        let kinds = files.map(FileKind.of)
        // The wheel follows the most common kind among the dragged files.
        var tally: [FileKind: Int] = [:]
        for k in kinds { tally[k, default: 0] += 1 }
        // Ties break on upstream's case order so the result is deterministic.
        let order: [FileKind] = [.image, .pdf, .video, .audio, .document, .other]
        let kind = files.count == 0 ? .other : (tally.max { a, b in
            a.value != b.value ? a.value < b.value : order.firstIndex(of: a.key)! > order.firstIndex(of: b.key)!
        }?.key ?? .other)
        let sameKind = files.filter { FileKind.of($0) == kind }
        let exts = Set(sameKind.map { canonicalExt($0.pathExtension) })
        let currentExt: String? = exts.count == 1 ? exts.first : nil

        var pages: [WheelPage]
        var labels: [String] = []
        var base: [Double] = []
        switch kind {
        case .image:
            labels = [L("画质"), L("压缩率"), L("兼容性"), L("透明")]
            base = imageTraits[currentExt ?? ""] ?? imageTraits["other"]!
            pages = [imageConvert(current: currentExt, count: sameKind.count, tools: tools), imageTools(base: base, count: sameKind.count)]
        case .pdf:
            labels = [L("版式还原"), L("可编辑"), L("体积小"), L("兼容性")]
            base = pdfTraits["pdf"]!
            pages = [pdfConvert(), pdfTools(base: base, count: sameKind.count)]
        case .video:
            labels = [L("画质"), L("压缩率"), L("兼容性")]
            base = videoTraits[currentExt ?? ""] ?? videoTraits["other"]!
            pages = [videoConvert(current: currentExt, tools: tools), videoTools(base: base, tools: tools)]
        case .audio:
            labels = [L("音质"), L("压缩率"), L("兼容性")]
            base = audioTraits[currentExt ?? ""] ?? audioTraits["other"]!
            pages = [audioConvert(current: currentExt, tools: tools), audioTools(base: base, tools: tools)]
        case .document:
            labels = [L("排版还原"), L("可编辑"), L("兼容性")]
            base = docTraits[currentExt ?? ""] ?? docTraits["other"]!
            pages = [docConvert(current: currentExt), docTools(word: exts == ["docx"])]
        case .other:
            pages = [genericPage(files: files)]
        }

        let headline: String
        let summary: String
        if files.count == 1, let f = files.first {
            headline = f.lastPathComponent
            summary = describe(f, kind: kind)
        } else {
            headline = L("%lld 个文件", files.count)
            let total = files.reduce(Int64(0)) { $0 + Fmt.size(of: $1) }
            let skipped = files.count - sameKind.count
            summary = Fmt.bytes(total) + " · " + kind.title + (skipped > 0 ? L(" · 另有 %lld 个会跳过", skipped) : "")
        }
        return WheelContext(files: files, kind: kind, pages: pages, headline: headline, summary: summary, statLabels: labels, base: base)
    }

    /// Every option id the engine understands (upstream `--ids`, tests, App Intents).
    public static var allIDs: [String] {
        let all = Tools(ffmpeg: true, heicEncoder: true, avifImageIO: true)
        let sample: [[WheelPage]] = [
            [imageConvert(current: nil, count: 1, tools: all), imageTools(base: imageTraits["png"]!, count: 1)],
            [pdfConvert(), pdfTools(base: pdfTraits["pdf"]!, count: 2)],
            [videoConvert(current: nil, tools: all), videoTools(base: videoTraits["mp4"]!, tools: all)],
            [audioConvert(current: nil, tools: all), audioTools(base: audioTraits["mp3"]!, tools: all)],
            [docConvert(current: nil), docTools(word: true)],
            [genericPage(files: [])],
        ]
        var seen = Set<String>()
        return sample.flatMap { $0 }.flatMap { $0.slots }.compactMap { $0?.id }.filter { seen.insert($0).inserted }
    }

    public static func canonicalExt(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg", "jpe": return "jpg"
        case "tif": return "tiff"
        case "heif": return "heic"
        case "htm": return "html"
        case "markdown": return "md"
        case "aif", "aifc": return "aiff"
        case "oga", "ogg": return "opus"
        default: return ext.lowercased()
        }
    }

    private static func describe(_ url: URL, kind: FileKind) -> String {
        var parts = [Fmt.bytes(Fmt.size(of: url))]
        if kind == .image, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, CGImageSourceGetPrimaryImageIndex(src), nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            parts.append("\(w)×\(h)")
        }
        let ext = url.pathExtension.uppercased()
        parts.append(ext.isEmpty ? kind.title : ext)
        return parts.joined(separator: " · ")
    }

    // MARK: - Stats tables

    public static let imageTraits: [String: [Double]] = [
        "png": [1.00, 0.35, 1.00, 1.00],
        "jpg": [0.74, 0.78, 1.00, 0.00],
        "heic": [0.84, 0.90, 0.55, 1.00],
        "webp": [0.80, 0.86, 0.82, 1.00],
        "avif": [0.86, 0.95, 0.60, 0.00],
        "pdf": [1.00, 0.40, 0.95, 1.00],
        "gif": [0.30, 0.55, 1.00, 0.50],
        "tiff": [1.00, 0.20, 0.70, 1.00],
        "bmp": [1.00, 0.05, 0.85, 0.00],
        "other": [0.92, 0.30, 0.45, 0.50],
    ]

    public static let pdfTraits: [String: [Double]] = [
        "pdf": [1.00, 0.15, 0.60, 0.95],
        "png": [0.95, 0.00, 0.40, 1.00],
        "jpg": [0.88, 0.00, 0.72, 1.00],
        "long": [0.90, 0.00, 0.62, 1.00],
        "docx": [0.55, 0.95, 0.70, 0.90],
        "txt": [0.08, 1.00, 1.00, 1.00],
        "md": [0.35, 1.00, 0.95, 0.80],
        "rtf": [0.50, 0.90, 0.60, 0.75],
        "html": [0.45, 0.80, 0.75, 0.95],
    ]

    public static let videoTraits: [String: [Double]] = [
        "mp4": [0.85, 0.70, 1.00],
        "m4v": [0.85, 0.70, 0.90],
        "mov": [0.95, 0.45, 0.75],
        "hevc": [0.90, 0.88, 0.70],
        "webm": [0.82, 0.85, 0.70],
        "mkv": [0.90, 0.72, 0.50],
        "avi": [0.70, 0.40, 0.55],
        "gif": [0.20, 0.10, 1.00],
        "mp3": [0.00, 0.97, 1.00],
        "m4a": [0.00, 0.96, 0.92],
        "wav": [0.00, 0.80, 0.95],
        "other": [0.80, 0.60, 0.50],
    ]

    public static let audioTraits: [String: [Double]] = [
        "mp3": [0.70, 0.80, 1.00],
        "m4a": [0.80, 0.82, 0.92],
        "aac": [0.78, 0.82, 0.85],
        "wav": [1.00, 0.00, 0.95],
        "aiff": [1.00, 0.00, 0.70],
        "flac": [1.00, 0.50, 0.65],
        "opus": [0.82, 0.92, 0.55],
        "alac": [1.00, 0.45, 0.70],
        "m4r": [0.80, 0.82, 0.40],
        "caf": [0.95, 0.30, 0.40],
        "other": [0.75, 0.60, 0.50],
    ]

    public static let docTraits: [String: [Double]] = [
        "pdf": [1.00, 0.15, 1.00],
        "docx": [0.85, 1.00, 0.95],
        "doc": [0.75, 0.90, 0.85],
        "txt": [0.10, 1.00, 1.00],
        "md": [0.40, 1.00, 0.75],
        "html": [0.70, 0.80, 0.95],
        "rtf": [0.75, 0.90, 0.80],
        "rtfd": [0.80, 0.90, 0.60],
        "odt": [0.80, 0.95, 0.60],
        "other": [0.60, 0.80, 0.60],
    ]

    private static func adjusted(_ base: [Double], _ changes: [Int: (Double) -> Double]) -> [Double] {
        base.enumerated().map { i, v in min(1, max(0, changes[i]?(v) ?? v)) }
    }

    // MARK: - Pages

    private static func format(_ id: String, _ key: String, big: String, ammo: String, title: String, detail: String,
                               current: String?, traits: [String: [Double]], aliases: Set<String> = [],
                               requires requirement: Requirement? = nil, tools: Tools = Tools.current) -> WheelOption {
        var o = WheelOption(id: id, big: big, ammo: ammo, title: title, detail: detail, stats: traits[key], requires: requirement)
        if let current, current == key || aliases.contains(current) {
            o.enabled = false
            o.ammo = L("当前")
            o.note = L("已经是 %@ 了", big)
        } else if let requirement {
            o.equip(requirement, tools: tools)
        }
        return o
    }

    private static func imageConvert(current: String?, count: Int, tools: Tools) -> WheelPage {
        let t = imageTraits
        var pdf = format("img.to.pdf", "pdf", big: "PDF", ammo: L("文档"), title: "PDF", detail: L("一张图一页，方便发送和打印"), current: nil, traits: t)
        if count > 1 {
            pdf.title = L("合并成 PDF")
            pdf.detail = L("%lld 张图按顺序合成一个 PDF", count)
            pdf.ammo = L("合并")
        }
        return WheelPage(name: L("格式转换"), slots: [
            format("img.to.png", "png", big: "PNG", ammo: L("无损"), title: "PNG", detail: L("无损画质，支持透明背景"), current: current, traits: t),
            format("img.to.jpg", "jpg", big: "JPG", ammo: L("通用"), title: "JPG", detail: L("到哪都能打开，体积适中"), current: current, traits: t),
            // iOS: needs an ImageIO HEIC encoder (upstream: always available on macOS).
            format("img.to.heic", "heic", big: "HEIC", ammo: L("苹果"), title: "HEIC", detail: L("苹果相册格式，小而清晰"), current: current, traits: t, requires: .heicEncoder, tools: tools),
            // iOS: libwebp is built in (upstream: requires cwebp).
            format("img.to.webp", "webp", big: "WEBP", ammo: L("网页"), title: "WebP", detail: L("网页常用，小体积高画质"), current: current, traits: t),
            pdf,
            // iOS: ImageIO AVIF encoder or FFmpeg (upstream: requires ffmpeg).
            format("img.to.avif", "avif", big: "AVIF", ammo: L("极小"), title: "AVIF", detail: L("新一代格式，体积最小（不保留透明）"), current: current, traits: t, requires: .avifEncoder, tools: tools),
            format("img.to.gif", "gif", big: "GIF", ammo: L("256色"), title: "GIF", detail: L("老牌格式，只有 256 种颜色"), current: current, traits: t),
            format("img.to.tiff", "tiff", big: "TIFF", ammo: L("印刷"), title: "TIFF", detail: L("无损大文件，适合印刷和存档"), current: current, traits: t),
        ])
    }

    private static func imageTools(base: [Double], count: Int) -> WheelPage {
        WheelPage(name: L("工具"), slots: [
            WheelOption(id: "img.compress", symbol: "arrow.down.right.and.arrow.up.left", ammo: L("压缩"), title: L("压缩"),
                        detail: L("肉眼几乎看不出差别，体积大幅缩小"), stats: adjusted(base, [0: { $0 * 0.9 }, 1: { $0 + 0.35 }])),
            WheelOption(id: "img.half", symbol: "minus.magnifyingglass", ammo: L("缩小一半"), title: L("缩小一半"),
                        detail: L("长宽各减半，体积约剩四分之一"), stats: adjusted(base, [0: { $0 * 0.7 }, 1: { $0 + 0.3 }])),
            WheelOption(id: "img.cutout", symbol: "scissors", ammo: L("抠图"), title: L("抠图"),
                        detail: L("自动识别主体，去掉背景，导出透明 PNG"), stats: adjusted(base, [3: { _ in 1 }])),
            WheelOption(id: "img.ocr", symbol: "text.viewfinder", ammo: L("识字"), title: L("识字"),
                        detail: L("认出图里的文字，直接复制到剪贴板")),
            WheelOption(id: "img.mono", symbol: "circle.lefthalf.filled", ammo: L("黑白"), title: L("黑白"),
                        detail: L("一键变成黑白照片")),
            WheelOption(id: "img.rotate", symbol: "rotate.right", ammo: L("旋转"), title: L("旋转"),
                        detail: L("顺时针转 90°")),
            WheelOption(id: "img.strip", symbol: "location.slash", ammo: L("去隐私"), title: L("去隐私"),
                        detail: L("抹掉 GPS 位置和拍摄信息，发图更安心")),
            WheelOption(id: "img.backdrop", symbol: "photo.artframe", ammo: L("加背景"), title: L("加背景"),
                        detail: L("加渐变背景、圆角和阴影，截图秒变精致")),
        ])
    }

    private static func pdfConvert() -> WheelPage {
        let t = pdfTraits
        func o(_ id: String, _ key: String, _ big: String, _ ammo: String, _ title: String, _ detail: String) -> WheelOption {
            WheelOption(id: id, big: big, ammo: ammo, title: title, detail: detail, stats: t[key])
        }
        return WheelPage(name: L("格式转换"), slots: [
            o("pdf.to.png", "png", "PNG", L("每页一张"), L("PNG 图片"), L("每页导出一张清晰图片")),
            o("pdf.to.jpg", "jpg", "JPG", L("每页一张"), L("JPG 图片"), L("每页一张，体积更小")),
            o("pdf.to.long", "long", L("长图"), L("拼接"), L("长图"), L("所有页面拼成一张长图，方便发朋友圈")),
            o("pdf.to.docx", "docx", "DOCX", "Word", L("Word 文档"), L("提取文字和格式，可以继续编辑")),
            o("pdf.to.txt", "txt", "TXT", L("纯文字"), L("纯文本"), L("只要文字，最干净")),
            o("pdf.to.md", "md", "MD", "Markdown", "Markdown", L("带标题层级的纯文本，适合喂给 AI")),
            o("pdf.to.rtf", "rtf", "RTF", L("富文本"), "RTF", L("保留基本格式的文本")),
            o("pdf.to.html", "html", "HTML", L("网页"), L("HTML 网页"), L("转成网页，浏览器直接打开")),
        ])
    }

    private static func pdfTools(base: [Double], count: Int) -> WheelPage {
        var merge = WheelOption(id: "pdf.merge", symbol: "square.stack.3d.down.right", ammo: L("合并"), title: L("合并"),
                                detail: L("把拖进来的 %lld 个 PDF 按顺序合成一个", count))
        if count < 2 {
            merge.enabled = false
            merge.note = L("同时拖 2 个以上 PDF 才能合并")
        }
        return WheelPage(name: L("工具"), slots: [
            WheelOption(id: "pdf.compress", symbol: "arrow.down.right.and.arrow.up.left", ammo: L("压缩"), title: L("压缩"),
                        detail: L("压缩里面的图片，体积变小"), stats: adjusted(base, [0: { $0 * 0.92 }, 2: { $0 + 0.3 }])),
            WheelOption(id: "pdf.split", symbol: "scissors", ammo: L("拆页"), title: L("拆页"), detail: L("每一页拆成单独的 PDF")),
            merge,
            WheelOption(id: "pdf.rotate", symbol: "rotate.right", ammo: L("旋转"), title: L("旋转"), detail: L("所有页面顺时针转 90°")),
            WheelOption(id: "pdf.mono", symbol: "circle.lefthalf.filled", ammo: L("黑白"), title: L("黑白"), detail: L("转成灰度，打印省彩墨")),
            WheelOption(id: "pdf.ocr", symbol: "text.viewfinder", ammo: L("识字"), title: L("识字"), detail: L("扫描件也能认出文字，复制到剪贴板")),
            strip("pdf.strip", detail: L("抹掉作者、制作软件和创建时间，甩掉警察")),
            zipOption,
        ])
    }

    /// 去隐私: clears the wanted level (location, device, author…).
    static func strip(_ id: String, detail: String) -> WheelOption {
        WheelOption(id: id, symbol: "location.slash", ammo: L("去隐私"), title: L("去隐私"), detail: detail)
    }

    private static func videoConvert(current: String?, tools: Tools) -> WheelPage {
        let t = videoTraits
        return WheelPage(name: L("格式转换"), slots: [
            format("vid.to.mp4", "mp4", big: "MP4", ammo: L("通用"), title: "MP4", detail: L("最通用的视频格式"), current: current, traits: t, aliases: ["m4v"]),
            format("vid.to.mov", "mov", big: "MOV", ammo: L("苹果"), title: "MOV", detail: L("苹果剪辑软件最爱"), current: current, traits: t),
            format("vid.to.hevc", "hevc", big: "HEVC", ammo: "H.265", title: "HEVC / H.265", detail: L("画质不变，体积约减半"), current: nil, traits: t),
            format("vid.to.webm", "webm", big: "WEBM", ammo: L("网页"), title: "WebM", detail: L("网页播放用的开源格式"), current: current, traits: t, requires: .ffmpeg, tools: tools),
            format("vid.to.gif", "gif", big: "GIF", ammo: L("动图"), title: L("GIF 动图"), detail: L("转成动图（最多取前 30 秒）"), current: current, traits: t),
            format("vid.to.mp3", "mp3", big: "MP3", ammo: L("提取音频"), title: L("MP3 音频"), detail: L("只要声音，最通用"), current: nil, traits: t, requires: .ffmpeg, tools: tools),
            format("vid.to.m4a", "m4a", big: "M4A", ammo: L("提取音频"), title: L("M4A 音频"), detail: L("只要声音，苹果设备友好"), current: nil, traits: t),
            format("vid.to.wav", "wav", big: "WAV", ammo: L("无损音频"), title: L("WAV 音频"), detail: L("只要声音，无损大文件"), current: nil, traits: t, requires: .ffmpeg, tools: tools),
        ])
    }

    private static func videoTools(base: [Double], tools: Tools) -> WheelPage {
        let hasFFmpeg = tools.ffmpeg
        var fast = WheelOption(id: "vid.fast", big: "2×", ammo: L("加速"), title: L("2 倍速"), detail: L("整体加速一倍，声音同步变快"))
        var slow = WheelOption(id: "vid.slow", symbol: "tortoise.fill", ammo: L("慢放"), title: L("慢放"), detail: L("0.5 倍速，就像开了子弹时间"))
        let compress = WheelOption(id: "vid.compress", symbol: "arrow.down.right.and.arrow.up.left", ammo: L("压缩"), title: L("压缩"),
                                   detail: hasFFmpeg ? L("1080P 以内，体积通常小一半以上") : L("缩到 720P，体积变小"),
                                   stats: adjusted(base, [0: { $0 * 0.88 }, 1: { $0 + 0.3 }, 2: { _ in 1 }]))
        fast.equip(.ffmpeg, tools: tools)
        slow.equip(.ffmpeg, tools: tools)
        return WheelPage(name: L("工具"), slots: [
            compress,
            WheelOption(id: "vid.mute", symbol: "speaker.slash.fill", ammo: L("静音"), title: L("静音"), detail: L("去掉声音，画面不动")),
            WheelOption(id: "vid.720p", big: "720P", ammo: L("降分辨率"), title: "720P", detail: L("缩到 720P，发消息更快"),
                        stats: adjusted(base, [0: { min($0, 0.6) }, 1: { $0 + 0.25 }])),
            WheelOption(id: "vid.cover", symbol: "photo", ammo: L("封面"), title: L("截封面"), detail: L("截取一帧存成 JPG")),
            fast, slow,
            strip("vid.strip", detail: L("抹掉拍摄地点、机型和时间，不重新压缩")),
            zipOption,
        ])
    }

    private static func audioConvert(current: String?, tools: Tools) -> WheelPage {
        let t = audioTraits
        return WheelPage(name: L("格式转换"), slots: [
            format("aud.to.mp3", "mp3", big: "MP3", ammo: L("通用"), title: "MP3", detail: L("最通用的音频格式"), current: current, traits: t, requires: .ffmpeg, tools: tools),
            format("aud.to.m4a", "m4a", big: "M4A", ammo: "AAC", title: "M4A", detail: L("苹果默认，同体积音质更好"), current: current, traits: t, aliases: ["aac"]),
            format("aud.to.wav", "wav", big: "WAV", ammo: L("无损"), title: "WAV", detail: L("无损大文件，剪辑常用"), current: current, traits: t),
            format("aud.to.flac", "flac", big: "FLAC", ammo: L("无损压缩"), title: "FLAC", detail: L("无损，体积约为 WAV 的一半"), current: current, traits: t),
            format("aud.to.aiff", "aiff", big: "AIFF", ammo: L("苹果无损"), title: "AIFF", detail: L("苹果的无损格式"), current: current, traits: t),
            format("aud.to.opus", "opus", big: "OPUS", ammo: L("极小"), title: "Opus", detail: L("体积极小，人声特别清晰"), current: current, traits: t, requires: .ffmpeg, tools: tools),
            format("aud.to.alac", "alac", big: "ALAC", ammo: L("苹果无损"), title: "ALAC", detail: L("苹果无损压缩，音乐 App 直接播"), current: nil, traits: t),
            WheelOption(id: "aud.to.m4r", symbol: "bell.fill", ammo: L("铃声"), title: L("iPhone 铃声"), detail: L("截取前 40 秒，做成 iPhone 铃声"), stats: t["m4r"]),
        ])
    }

    private static func audioTools(base: [Double], tools: Tools) -> WheelPage {
        var slots: [WheelOption?] = [
            WheelOption(id: "aud.compress", symbol: "arrow.down.right.and.arrow.up.left", ammo: L("压缩"), title: L("压缩"),
                        detail: L("转成 96 kbps AAC，体积极小"), stats: adjusted(base, [0: { $0 * 0.8 }, 1: { _ in 0.95 }])),
            WheelOption(id: "aud.mono", symbol: "speaker.wave.1.fill", ammo: L("单声道"), title: L("单声道"), detail: L("左右声道合成一个")),
            WheelOption(id: "aud.loud", symbol: "speaker.wave.3.fill", ammo: L("响度统一"), title: L("响度统一"), detail: L("音量拉到标准响度，不再忽大忽小")),
            WheelOption(id: "aud.fast", big: "1.5×", ammo: L("加速"), title: L("1.5 倍速"), detail: L("整体加速，听播客更快")),
            nil, nil, zipOption, pathOption,
        ]
        for i in 1...3 { slots[i]?.equip(.ffmpeg, tools: tools) }
        return WheelPage(name: L("工具"), slots: slots)
    }

    private static func docConvert(current: String?) -> WheelPage {
        let t = docTraits
        return WheelPage(name: L("格式转换"), slots: [
            format("doc.to.pdf", "pdf", big: "PDF", ammo: L("打印"), title: "PDF", detail: L("排版固定，发给谁看都一样"), current: current, traits: t),
            format("doc.to.docx", "docx", big: "DOCX", ammo: "Word", title: L("Word 文档"), detail: L("最常见的可编辑文档"), current: current, traits: t),
            format("doc.to.txt", "txt", big: "TXT", ammo: L("纯文字"), title: L("纯文本"), detail: L("只要文字，最干净"), current: current, traits: t),
            format("doc.to.md", "md", big: "MD", ammo: "Markdown", title: "Markdown", detail: L("带标题层级的纯文本，适合喂给 AI"), current: current, traits: t),
            format("doc.to.html", "html", big: "HTML", ammo: L("网页"), title: L("HTML 网页"), detail: L("浏览器直接打开"), current: current, traits: t),
            format("doc.to.rtf", "rtf", big: "RTF", ammo: L("富文本"), title: "RTF", detail: L("保留基本格式的文本"), current: current, traits: t),
            format("doc.to.odt", "odt", big: "ODT", ammo: L("开源"), title: "ODT", detail: L("LibreOffice / WPS 的开放格式"), current: current, traits: t),
            format("doc.to.doc", "doc", big: "DOC", ammo: L("旧版"), title: L("旧版 Word"), detail: L("兼容老版本 Office"), current: current, traits: t),
        ])
    }

    private static func docTools(word: Bool) -> WheelPage {
        var lieLow = strip("doc.strip", detail: L("抹掉作者、修改人和公司名"))
        if !word {
            lieLow.enabled = false
            lieLow.note = L("只有 Word（.docx）文档会带作者信息")
        }
        return WheelPage(name: L("工具"), slots: [
            WheelOption(id: "doc.count", symbol: "textformat.123", ammo: L("字数"), title: L("字数统计"), detail: L("数一数一共多少字")),
            nil,
            WheelOption(id: "doc.copy", symbol: "doc.on.clipboard", ammo: L("复制全文"), title: L("复制全文"), detail: L("把文字全部复制到剪贴板")),
            nil, lieLow, nil, zipOption, pathOption,
        ])
    }

    static var zipOption: WheelOption { WheelOption(id: "gen.zip", symbol: "doc.zipper", ammo: L("压缩包"), title: L("打包 ZIP"), detail: L("打包成 .zip 压缩包")) }
    static var pathOption: WheelOption { WheelOption(id: "gen.path", symbol: "link", ammo: L("复制路径"), title: L("复制路径"), detail: L("把文件路径复制到剪贴板")) }

    private static func genericPage(files: [URL]) -> WheelPage {
        var sha = WheelOption(id: "gen.sha", symbol: "number", ammo: "SHA-256", title: "SHA-256", detail: L("算出校验值并复制"))
        if files.contains(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) {
            sha.enabled = false
            sha.note = L("文件夹算不了校验值")
        }
        return WheelPage(name: L("通用"), slots: [
            zipOption, nil,
            pathOption, nil,
            WheelOption(id: "gen.name", symbol: "character.cursor.ibeam", ammo: L("复制文件名"), title: L("复制文件名"), detail: L("把文件名复制到剪贴板")),
            nil,
            sha, nil,
        ])
    }
}
