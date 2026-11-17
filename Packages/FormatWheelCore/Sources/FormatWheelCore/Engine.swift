import Foundation

public struct RunSummary: Sendable {
    public var outputs: [URL]
    public var title: String
    public var detail: String
    /// Display name of the folder the results went to.
    public var saved: String? {
        outputs.first.map { FileManager.default.displayName(atPath: $0.deletingLastPathComponent().path) }
    }
}

/// The last few results, for 「最近转换」 (upstream `Recents`).
public final class Recents: @unchecked Sendable {
    public static let shared = Recents()
    private let key = "recentOutputs"

    public var items: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
    }

    public func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let merged = urls + items.filter { !urls.contains($0) }
        UserDefaults.standard.set(merged.prefix(8).map(\.path), forKey: key)
    }
}

/// Port of upstream Sources/Engine.swift `Engine`. The UI half (`Runner`: HUD, sounds, banner) is the app's.
public enum Engine {
    /// Runs one wheel option over the files.
    public static func run(_ id: String, label: String, files: [URL], progress: @escaping ProgressFn) async throws -> RunSummary {
        let name = files.count == 1 ? files[0].lastPathComponent : L("%lld 个文件", files.count)
        let title = "\(name)  →  \(label)"

        func savedDetail(_ out: URL) -> String {
            L("%@ · %@ · 存到「%@」", out.lastPathComponent, Fmt.bytes(Fmt.size(of: out)),
              FileManager.default.displayName(atPath: out.deletingLastPathComponent().path))
        }

        // Actions that take the whole selection at once.
        switch id {
        case "pdf.merge", "img.to.pdf" where files.count > 1:
            let out = try PDFOps.merge(files)
            return RunSummary(outputs: [out], title: title, detail: savedDetail(out))
        case "gen.zip":
            let out = try await GenericOps.zip(files)
            return RunSummary(outputs: [out], title: title, detail: savedDetail(out))
        case "gen.path":
            let text = files.map(FilesLocation.describe).joined(separator: "\n")
            Clipboard.set(text)
            return RunSummary(outputs: [], title: title, detail: files.count == 1 ? text : L("%lld 条路径已复制", files.count))
        case "gen.name":
            Clipboard.set(files.map(\.lastPathComponent).joined(separator: "\n"))
            return RunSummary(outputs: [], title: title, detail: L("已复制到剪贴板"))
        default:
            break
        }

        let kind = Catalog.context(for: files).kind
        let targets = files.filter { FileKind.of($0) == kind || id.hasPrefix("gen.") }
        var outputs: [URL] = []
        var notes: [String] = []
        var clips: [String] = []
        var failures: [Error] = []
        var before: Int64 = 0, after: Int64 = 0
        for (n, file) in targets.enumerated() {
            try Task.checkCancellation()
            let step: ProgressFn = { p in progress((Double(n) + p) / Double(targets.count)) }
            do {
                let result = try await runOne(id, file, progress: step)
                outputs += result.outputs
                if let note = result.note { notes.append(note) }
                if let clip = result.clip { clips.append(clip) }
                before += Fmt.size(of: file)
                after += result.outputs.reduce(Int64(0)) { $0 + Fmt.size(of: $1) }
            } catch is CancellationError {
                throw FWError.cancelled
            } catch let error as FWError where error == .cancelled {
                throw error
            } catch {
                failures.append(error)
            }
        }
        if outputs.isEmpty, notes.isEmpty, clips.isEmpty {
            throw failures.first ?? FWError(L("没有可以处理的文件"))
        }
        if !clips.isEmpty { Clipboard.set(clips.joined(separator: "\n\n")) }

        var detail: [String] = []
        if !outputs.isEmpty, after > 0, !id.hasPrefix("gen.") {
            detail.append("\(Fmt.bytes(before)) → \(Fmt.bytes(after))")
        }
        if targets.count == 1, let note = notes.first {
            detail.append(note)
        } else if !notes.isEmpty, id.hasSuffix("compress") {
            let saved = Int((1 - Double(after) / Double(max(before, 1))) * 100)
            detail.append(L("体积 -%lld%%", saved))
        } else if !clips.isEmpty {
            detail.append(L("文字已复制到剪贴板"))
        }
        if !failures.isEmpty { detail.append(L("%lld 个失败：%@", failures.count, failures[0].localizedDescription)) }
        var summary = RunSummary(outputs: outputs, title: title, detail: "")
        if let saved = summary.saved { detail.append(L("存到「%@」", saved)) }
        summary.detail = detail.joined(separator: " · ")
        return summary
    }

    static func runOne(_ id: String, _ file: URL, progress: @escaping ProgressFn) async throws -> OpResult {
        let parts = id.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { throw FWError(L("未知操作 %@", id)) }
        let target = parts.count == 3 && parts[1] == "to" ? parts[2] : nil

        switch parts[0] {
        case "img":
            if let target { return try await ImageOps.convert(file, to: target) }
            switch id {
            case "img.compress": return try await ImageOps.compress(file)
            case "img.half": return try await ImageOps.half(file)
            case "img.cutout": return try await ImageOps.cutout(file)
            case "img.ocr": return try await ImageOps.ocr(file)
            case "img.mono": return try await ImageOps.mono(file)
            case "img.rotate": return try await ImageOps.rotate(file)
            case "img.strip": return try await ImageOps.strip(file)
            case "img.backdrop": return try await ImageOps.backdrop(file)
            default: break
            }
        case "pdf":
            switch id {
            case "pdf.to.png": return try await PDFOps.toImages(file, fmt: "png", progress: progress)
            case "pdf.to.jpg": return try await PDFOps.toImages(file, fmt: "jpg", progress: progress)
            case "pdf.to.long": return try await PDFOps.longImage(file, progress: progress)
            case "pdf.compress": return try PDFOps.compress(file)
            case "pdf.split": return try PDFOps.split(file)
            case "pdf.rotate": return try PDFOps.rotate(file)
            case "pdf.mono": return try await PDFOps.mono(file, progress: progress)
            case "pdf.ocr": return try await PDFOps.ocr(file, progress: progress)
            case "pdf.strip": return try Privacy.stripPDF(file)
            default:
                if let target { return try await PDFOps.toText(file, fmt: target) }
            }
        case "vid", "aud", "doc":
            // MediaOps (P2) and DocOps (P3) are not ported yet.
            throw FWError(L("这个功能还在移植中"))
        case "gen":
            if id == "gen.sha" { return try await GenericOps.sha256(file) }
        default:
            break
        }
        throw FWError(L("未知操作 %@", id))
    }
}
