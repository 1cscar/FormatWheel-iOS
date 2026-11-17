import FWFFmpeg
import Foundation
import ImageIO

/// What this device / build can do. Replaces upstream `Shell.has(_:)` (Homebrew tools): slots whose
/// requirement is missing show as 「未装备」 with a reason instead of an install hint.
public struct Tools: Sendable, Equatable {
    /// The bundled FFmpeg is linked and runs.
    public var ffmpeg: Bool
    /// ImageIO can write HEIC.
    public var heicEncoder: Bool
    /// ImageIO can write AVIF (otherwise AVIF goes through FFmpeg's libsvtav1).
    public var avifImageIO: Bool
    /// libwebp is linked into the app (upstream needed `cwebp`).
    public var webp: Bool

    public init(ffmpeg: Bool, heicEncoder: Bool, avifImageIO: Bool, webp: Bool = true) {
        self.ffmpeg = ffmpeg
        self.heicEncoder = heicEncoder
        self.avifImageIO = avifImageIO
        self.webp = webp
    }

    /// AVIF can be written one way or the other.
    public var avif: Bool { avifImageIO || ffmpeg }

    public static func detect() -> Tools {
        let types = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let ffmpeg = !String(cString: fw_ffmpeg_version()).isEmpty
        return Tools(ffmpeg: ffmpeg, heicEncoder: types.contains("public.heic"), avifImageIO: types.contains("public.avif"))
    }

    /// The tools the engine uses; tests override it to exercise upstream's fallback paths.
    nonisolated(unsafe) public static var current = Tools.detect()

    public func has(_ requirement: Requirement) -> Bool {
        switch requirement {
        case .ffmpeg: return ffmpeg
        case .heicEncoder: return heicEncoder
        case .avifEncoder: return avif
        }
    }
}

/// What a slot needs to be usable.
public enum Requirement: String, Sendable, CaseIterable {
    case ffmpeg, heicEncoder, avifEncoder

    /// The upstream tool this replaces, for the catalog parity check (nil = iOS-only requirement).
    public var upstreamTool: String? {
        switch self {
        case .ffmpeg, .avifEncoder: return "ffmpeg"
        case .heicEncoder: return nil
        }
    }

    /// Why the slot is unavailable (replaces upstream's "brew install …" hint).
    public var unavailableReason: String {
        switch self {
        case .ffmpeg: return L("这个版本没有内置 FFmpeg，暂时用不了")
        case .heicEncoder: return L("此设备不支持 HEIC 编码")
        case .avifEncoder: return L("此设备不支持 AVIF 编码，也没有内置 FFmpeg")
        }
    }
}
