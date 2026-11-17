import CryptoKit
import Foundation
import ZIPFoundation

/// Port of upstream Engine.swift `GenericOps`. `ditto -c -k --keepParent` → ZIPFoundation.
enum GenericOps {
    static func zip(_ files: [URL]) async throws -> URL {
        guard let first = files.first else { throw FWError(L("没有文件")) }
        if files.count == 1 {
            let out = Out.url(for: first, ext: "zip")
            try archive(first, to: out)
            return out
        }
        let tmp = try Out.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bundle = tmp.appendingPathComponent(L("归档"))
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        for file in files {
            let base = file.deletingPathExtension().lastPathComponent
            let target = Out.unique(in: bundle, base: base, ext: file.pathExtension)
            try FileManager.default.copyItem(at: file, to: target)
        }
        let out = Out.unique(in: Out.dir(for: first), base: L("归档 %lld 项", files.count), ext: "zip")
        try archive(bundle, to: out)
        return out
    }

    private static func archive(_ item: URL, to out: URL) throws {
        do {
            try FileManager.default.zipItem(at: item, to: out, shouldKeepParent: true, compressionMethod: .deflate)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw FWError(L("打包失败：%@", error.localizedDescription))
        }
    }

    static func sha256(_ url: URL) async throws -> OpResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return OpResult(note: L("SHA-256 %@… 已复制", String(hex.prefix(12))), clip: hex)
    }
}

/// gen.path on iOS: sandbox paths mean nothing to users, so describe where the file is in the Files app
/// ("我的 iPhone › 格式轮盘 › a.png", "iCloud 云盘 › …"); anything else falls back to its file URL.
public enum FilesLocation {
    public static func describe(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL.path
        if path.hasPrefix(docs + "/") {
            let rest = path.dropFirst(docs.count + 1).split(separator: "/").map(String.init)
            return ([L("我的 %@", Platform.deviceName), L("格式轮盘")] + rest).joined(separator: " › ")
        }
        if let r = path.range(of: "/Mobile Documents/com~apple~CloudDocs/") {
            let rest = path[r.upperBound...].split(separator: "/").map(String.init)
            return ([L("iCloud 云盘")] + rest).joined(separator: " › ")
        }
        return url.absoluteString
    }
}
