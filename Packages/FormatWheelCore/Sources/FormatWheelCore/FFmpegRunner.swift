import FWFFmpeg
import Foundation

/// Runs the bundled `ffmpeg` in-process (replaces upstream `Shell.run(ffmpeg, …)`).
///
/// - One session at a time: callers queue on an actor, and the C side holds a lock as a backstop.
/// - Progress: `-progress pipe:1` in upstream argument lists is redirected to a temp file that is
///   polled for `out_time_us=` lines.
/// - Cancellation: cancelling the calling Task asks ffmpeg to stop (like SIGINT); the half-written
///   output is the caller's to remove (upstream `MediaOps.ff` already does that on any error).
/// - Errors become `FWError("ffmpeg 出错：<last error line>")`, matching upstream wording.
public final class FFmpegRunner: @unchecked Sendable {
    public static let shared = FFmpegRunner()

    /// Version string of the bundled FFmpeg, e.g. "9.0.2".
    public var version: String { String(cString: fw_ffmpeg_version()) }
    /// One line per bundled library ("FFmpeg 9.0.2", "LAME 3.100", …).
    public var components: [String] {
        String(cString: fw_component_versions()).split(separator: "\n").map(String.init)
    }
    public var configuration: String { String(cString: fw_ffmpeg_configuration()) }
    public var license: String { String(cString: fw_ffmpeg_license()) }
    public func hasEncoder(_ name: String) -> Bool { fw_has_encoder(name) != 0 }
    public func hasFilter(_ name: String) -> Bool { fw_has_filter(name) != 0 }

    private let queue = SessionQueue()

    public init() {}

    /// Runs `ffmpeg <arguments>`; `arguments` excludes the program name. `duration` (seconds) turns
    /// `out_time_us` into 0...1 progress. Returns the collected log lines.
    @discardableResult
    public func run(_ arguments: [String], duration: Double = 0, progress: ProgressFn? = nil) async throws -> [String] {
        try await queue.enqueue {
            try await self.runNow(arguments, duration: duration, progress: progress)
        }
    }

    private func runNow(_ arguments: [String], duration: Double, progress: ProgressFn?) async throws -> [String] {
        try Task.checkCancellation()
        let progressFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fw-progress-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: progressFile) }
        var args = arguments
        if let i = args.firstIndex(of: "-progress"), args.indices.contains(i + 1) {
            args[i + 1] = progressFile.path
        } else if progress != nil {
            args.insert(contentsOf: ["-progress", progressFile.path], at: 0)
        }

        let session = Session()
        let poller: Task<Void, Never>? = (progress != nil && duration > 0) ? Task.detached {
            var last = -1.0
            while !Task.isCancelled {
                if let p = Self.readProgress(progressFile, duration: duration), p != last {
                    last = p
                    progress?(p)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        } : nil
        defer { poller?.cancel() }

        let code: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Int32, Error>) in
                // ffmpeg needs a deep stack; a dedicated thread also keeps the cooperative pool free.
                let thread = Thread {
                    let code = Self.execute(["ffmpeg"] + args, session: session)
                    done.resume(returning: code)
                }
                thread.stackSize = 16 << 20
                thread.qualityOfService = .userInitiated
                thread.name = "FormatWheel.ffmpeg"
                thread.start()
            }
        } onCancel: {
            session.cancelled = true
            fw_ffmpeg_cancel()
        }

        if session.cancelled || Task.isCancelled { throw FWError.cancelled }
        guard code == 0 else {
            let last = session.errorLines.last ?? "退出码 \(code)"
            throw FWError("ffmpeg 出错：\(last.prefix(140))")
        }
        if duration > 0 { progress?(1) }
        return session.lines
    }

    private static func execute(_ argv: [String], session: Session) -> Int32 {
        var cStrings = argv.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        let context = Unmanaged.passRetained(session)
        defer { context.release() }
        return cStrings.withUnsafeMutableBufferPointer { buffer -> Int32 in
            buffer.baseAddress!.withMemoryRebound(to: UnsafeMutablePointer<CChar>.self, capacity: buffer.count) { argvPtr in
                fw_ffmpeg_execute(Int32(argv.count), argvPtr, { ctx, level, line in
                    guard let ctx else { return }
                    Unmanaged<Session>.fromOpaque(ctx).takeUnretainedValue().append(level: level, line: String(cString: line))
                }, context.toOpaque())
            }
        }
    }

    static func readProgress(_ url: URL, duration: Double) -> Double? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let line = text.split(separator: "\n").last(where: { $0.hasPrefix("out_time_us=") }),
              let us = Double(line.dropFirst("out_time_us=".count)) else { return nil }
        return min(1, max(0, us / 1_000_000 / duration))
    }

    // MARK: - Probe (replaces ffprobe)

    public struct Probe: Sendable {
        public var duration: Double
        public var bitRate: Int
        public var videoBitRate: Int
        public var sampleRate: Int
        public var channels: Int
        public var hasVideo: Bool
        public var hasAudio: Bool
        /// Container and stream tags, keys as FFmpeg reports them (e.g. "com.apple.quicktime.model").
        public var tags: [(key: String, value: String)]
    }

    public func probe(_ url: URL) -> Probe? {
        var result = fw_probe_result()
        var buffer = [CChar](repeating: 0, count: 64 * 1024)
        let status = fw_probe(url.path, &result, &buffer, buffer.count)
        guard status == 0 else { return nil }
        let text = String(cString: buffer)
        var tags: [(key: String, value: String)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            tags.append((key: String(parts[0]), value: String(parts[1])))
        }
        return Probe(duration: result.duration, bitRate: Int(result.bit_rate), videoBitRate: Int(result.video_bit_rate),
                     sampleRate: Int(result.sample_rate), channels: Int(result.channels),
                     hasVideo: result.has_video != 0, hasAudio: result.has_audio != 0, tags: tags)
    }
}

/// Log sink and cancel flag for one ffmpeg run (touched from ffmpeg's threads).
private final class Session: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    private var _errors: [String] = []
    private var _cancelled = false

    var cancelled: Bool {
        get { lock.withLock { _cancelled } }
        set { lock.withLock { _cancelled = newValue } }
    }
    var lines: [String] { lock.withLock { _lines } }
    var errorLines: [String] { lock.withLock { _errors } }

    func append(level: Int32, line: String) {
        lock.withLock {
            if _lines.count < 2000 { _lines.append(line) }
            if level <= 16 { _errors.append(line) } // AV_LOG_ERROR and worse
        }
    }
}

/// Runs async jobs strictly one after another, in submission order.
private actor SessionQueue {
    private var tail: Task<Void, Never>?

    func enqueue<T: Sendable>(_ job: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await job()
        }
        tail = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
