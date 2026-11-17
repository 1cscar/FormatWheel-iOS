import AVFoundation
@testable import FormatWheelCore
import XCTest

/// P0 FFmpeg spike: the bundled FFmpeg runs in-process on iOS, encodes, reports progress, cancels.
final class FFmpegRunnerTests: XCTestCase {
    let runner = FFmpegRunner.shared

    func testVersionRunsAndReturnsZero() async throws {
        try await runner.run(["-hide_banner", "-version"])
        XCTAssertFalse(runner.version.isEmpty)
        XCTAssertTrue(runner.components.first?.hasPrefix("FFmpeg") == true, "\(runner.components)")
    }

    func testBuildIsLGPLWithRequiredComponents() {
        XCTAssertFalse(runner.configuration.contains("--enable-gpl"))
        XCTAssertFalse(runner.configuration.contains("--enable-nonfree"))
        XCTAssertTrue(runner.license.hasPrefix("LGPL"), runner.license)
        for encoder in ["libmp3lame", "libopus", "libvpx-vp9", "libwebp", "libsvtav1", "h264_videotoolbox", "hevc_videotoolbox", "aac", "flac", "alac"] {
            XCTAssertTrue(runner.hasEncoder(encoder), "missing encoder \(encoder)")
        }
        for encoder in ["libx264", "libx265", "libfdk_aac"] {
            XCTAssertFalse(runner.hasEncoder(encoder), "GPL / non-free encoder \(encoder) must not be bundled")
        }
        for filter in ["loudnorm", "palettegen", "paletteuse", "atempo", "setpts", "scale"] {
            XCTAssertTrue(runner.hasFilter(filter), "missing filter \(filter)")
        }
    }

    func testSineWaveToMP3() async throws {
        let dir = try Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try Fixtures.sineWAV(seconds: 1, in: dir)
        let output = dir.appendingPathComponent("sine.mp3")
        let progress = ProgressBox()
        // Same arguments as upstream MediaOps.audio("aud.to.mp3").
        try await runner.run(["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats",
                              "-i", input.path, "-vn", "-c:a", "libmp3lame", "-q:a", "2", output.path],
                             duration: 1) { progress.add($0) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let seconds = try await Fixtures.duration(output)
        XCTAssertEqual(seconds, 1, accuracy: 0.15)
        let probe = try XCTUnwrap(runner.probe(output))
        XCTAssertEqual(probe.sampleRate, 44_100)
        XCTAssertEqual(probe.channels, 2)
        XCTAssertTrue(probe.hasAudio)
        XCTAssertFalse(probe.hasVideo)
        XCTAssertEqual(progress.values.last ?? 0, 1, accuracy: 0.0001)
    }

    func testFailureBecomesFWError() async throws {
        do {
            try await runner.run(["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", "/nonexistent/in.wav", "/tmp/out.mp3"])
            XCTFail("expected an error")
        } catch let error as FWError {
            XCTAssertTrue(error.message.hasPrefix("ffmpeg 出错："), error.message)
        }
    }

    func testCancelStopsRunAndNextRunStillWorks() async throws {
        let dir = try Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try Fixtures.sineWAV(seconds: 1, in: dir)
        let output = dir.appendingPathComponent("endless.flac")
        // -stream_loop -1 never ends on its own; only cancellation can stop it.
        let task = Task {
            try await runner.run(["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-stream_loop", "-1", "-i", input.path,
                                  "-c:a", "flac", "-compression_level", "12", output.path], duration: 3600)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch let error as FWError {
            XCTAssertEqual(error, .cancelled)
        }
        // The runner must be reusable after a cancelled session.
        try await testSineWaveToMP3()
    }

    func testManyRunsInARowReuseGlobalState() async throws {
        let dir = try Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try Fixtures.sineWAV(seconds: 1, in: dir)
        for n in 0..<5 {
            let out = dir.appendingPathComponent("\(n).wav")
            try await runner.run(["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", input.path, "-ac", "1", "-c:a", "pcm_s16le", out.path])
            XCTAssertEqual(runner.probe(out)?.channels, 1)
            // An error in between must not poison the next run.
            _ = try? await runner.run(["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", "/nonexistent.wav", out.path + ".mp3"])
        }
    }

    func testSessionsRunOneAtATime() async throws {
        let dir = try Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try Fixtures.sineWAV(seconds: 1, in: dir)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for n in 0..<3 {
                group.addTask {
                    try await self.runner.run(["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", input.path,
                                               "-c:a", "libopus", "-b:a", "64k", dir.appendingPathComponent("\(n).opus").path])
                }
            }
            try await group.waitForAll()
        }
        for n in 0..<3 {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(n).opus").path))
        }
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Double] = []
    var values: [Double] { lock.withLock { _values } }
    func add(_ v: Double) { lock.withLock { _values.append(v) } }
}
