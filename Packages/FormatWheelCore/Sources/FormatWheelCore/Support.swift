import Foundation

/// An error whose message is shown to the user as-is (upstream `FWError`, Support.swift).
public struct FWError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }

    /// The user cancelled a running action.
    public static var cancelled: FWError { FWError(L("已取消")) }
}

/// Progress callback, 0...1 (upstream `ProgressFn`).
public typealias ProgressFn = @Sendable (Double) -> Void

/// What one action produced for one input file (upstream `OpResult`).
public struct OpResult: Sendable {
    public var outputs: [URL] = []
    public var note: String?
    /// Text to put on the clipboard once the whole batch is done.
    public var clip: String?

    public init(outputs: [URL] = [], note: String? = nil, clip: String? = nil) {
        self.outputs = outputs
        self.note = note
        self.clip = clip
    }
}

public enum Fmt {
    public static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    public static func size(of url: URL) -> Int64 {
        // Never reuse cached resource values: a file may be rewritten under the same URL (pdf.compress).
        var url = url
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true {
            let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            var total: Int64 = 0
            while let item = items?.nextObject() as? URL {
                total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }
        return Int64(values?.fileSize ?? 0)
    }

    public static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Where results go. Upstream writes next to the source (or ~/Downloads); on iOS the app picks the
/// folder (`Documents/FormatWheel` by default, or a user-chosen folder) and sets `Out.directory`.
/// Naming and conflict handling are upstream's.
public enum Out {
    /// Supplies the output folder; the app replaces it at launch, tests point it at a temp folder.
    nonisolated(unsafe) public static var directory: () -> URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("FormatWheel", isDirectory: true)
    }

    public static func dir(for source: URL) -> URL {
        let dir = directory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func url(for source: URL, suffix: String? = nil, ext: String) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + (suffix.map { " " + $0 } ?? "")
        return unique(in: dir(for: source), base: base, ext: ext)
    }

    public static func unique(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        let dot = ext.isEmpty ? "" : "." + ext
        var candidate = dir.appendingPathComponent(base + dot)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)\(dot)")
            n += 1
        }
        return candidate
    }

    public static func folder(for source: URL, suffix: String) throws -> URL {
        let url = unique(in: dir(for: source), base: source.deletingPathExtension().lastPathComponent + " " + suffix, ext: "")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FormatWheel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// UI-only capabilities the app injects (FormatWheelCore must not import UIKit).
public protocol ClipboardService: Sendable {
    func set(_ text: String)
}

/// NSAttributedString ⇄ RTF / HTML. On iOS the document types live in UIKit, so the app provides them.
public protocol RichTextCodec: Sendable {
    func data(from text: NSAttributedString, format: String) throws -> Data
    func attributedString(from data: Data, format: String) throws -> NSAttributedString
}

public enum Platform {
    nonisolated(unsafe) public static var clipboard: ClipboardService = MemoryClipboard()
    nonisolated(unsafe) public static var richText: RichTextCodec?
    /// "iPhone" or "iPad", used when describing Files-app locations (gen.path).
    nonisolated(unsafe) public static var deviceName = "iPhone"
}

/// Default clipboard (tests, previews): keeps the last text in memory.
public final class MemoryClipboard: ClipboardService, @unchecked Sendable {
    private let lock = NSLock()
    private var _text: String?
    public init() {}
    public var text: String? { lock.withLock { _text } }
    public func set(_ text: String) { lock.withLock { _text = text } }
}

enum Clipboard {
    static func set(_ text: String) { Platform.clipboard.set(text) }
}

/// A small rolling log in Library/Logs/FormatWheel.log (upstream: ~/Library/Logs/FormatWheel.log).
public enum Log {
    private static let queue = DispatchQueue(label: "formatwheel.log")
    public static var url: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/FormatWheel.log")
    }
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public static func write(_ message: String) {
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        let url = self.url
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > 512_000 {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
