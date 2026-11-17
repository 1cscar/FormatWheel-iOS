// Minimal stand-ins for the upstream symbols Catalog.swift uses, so the upstream file compiles alone.
import Foundation

enum Shell {
    /// Tools the current scenario pretends are installed.
    static var installed: Set<String> = ["ffmpeg", "cwebp"]
    static func has(_ name: String) -> Bool { installed.contains(name) }
    static func installHint(_ name: String) -> String {
        let formula = name == "cwebp" ? "webp" : name
        return "需要先装 \(name)：终端运行 brew install \(formula)"
    }
}

enum Fmt {
    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
    static func size(of url: URL) -> Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
}
