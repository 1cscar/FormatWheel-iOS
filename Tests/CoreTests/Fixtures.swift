import AVFoundation
import Foundation

/// Test inputs generated on the fly — no binary fixtures in the repo.
enum Fixtures {
    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fw-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

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
}
