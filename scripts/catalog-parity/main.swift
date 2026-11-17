// Dumps upstream Catalog behaviour for a fixed list of scenarios as JSON (stdout).
// Built by scripts/catalog-parity/dump-upstream.sh together with upstream/Sources/Catalog.swift.
import Foundation

struct Scenario { let name: String; let files: [String]; let tools: String }

let scenarios: [Scenario] = {
    var s: [Scenario] = []
    let toolsets = ["all", "noFFmpeg", "noCwebp", "none"]
    let singles = ["photo.png", "photo.jpg", "photo.heic", "photo.webp", "photo.avif", "photo.gif", "photo.tiff", "photo.bmp", "photo.jpeg",
                   "doc.pdf", "clip.mp4", "clip.mov", "clip.m4v", "clip.webm", "clip.mkv", "clip.avi",
                   "song.mp3", "song.m4a", "song.aac", "song.wav", "song.flac", "song.aiff", "song.opus", "song.ogg", "song.caf",
                   "note.txt", "note.md", "note.docx", "note.doc", "note.rtf", "note.html", "note.odt",
                   "archive.zip", "folder/"]
    for t in toolsets {
        for f in singles { s.append(Scenario(name: "\(t):\(f)", files: [f], tools: t)) }
        s.append(Scenario(name: "\(t):3 images", files: ["a.jpg", "b.jpg", "c.png"], tools: t))
        s.append(Scenario(name: "\(t):2 pdfs", files: ["a.pdf", "b.pdf"], tools: t))
        s.append(Scenario(name: "\(t):2 docx", files: ["a.docx", "b.docx"], tools: t))
        s.append(Scenario(name: "\(t):mixed majority image", files: ["a.jpg", "b.png", "c.pdf"], tools: t))
        s.append(Scenario(name: "\(t):file + folder", files: ["a.zip", "folder/"], tools: t))
    }
    return s
}()

func toolset(_ name: String) -> Set<String> {
    switch name {
    case "all": return ["ffmpeg", "cwebp"]
    case "noFFmpeg": return ["cwebp"]
    case "noCwebp": return ["ffmpeg"]
    default: return []
    }
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-parity-\(UUID().uuidString)")
func materialize(_ names: [String]) -> [URL] {
    names.map { name in
        let url = root.appendingPathComponent(name)
        if name.hasSuffix("/") {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return url
    }
}

func slotJSON(_ o: WheelOption?) -> Any {
    guard let o else { return NSNull() }
    var d: [String: Any] = ["id": o.id, "ammo": o.ammo, "title": o.title, "detail": o.detail, "enabled": o.enabled]
    if let v = o.big { d["big"] = v }
    if let v = o.symbol { d["symbol"] = v }
    if let v = o.note { d["note"] = v }
    if let v = o.stats { d["stats"] = v }
    return d
}

var out: [[String: Any]] = []
for sc in scenarios {
    Shell.installed = toolset(sc.tools)
    let ctx = Catalog.context(for: materialize(sc.files))
    out.append([
        "name": sc.name, "files": sc.files, "tools": sc.tools,
        "kind": ctx.kind.rawValue, "headline": ctx.headline,
        "statLabels": ctx.statLabels, "base": ctx.base,
        "pages": ctx.pages.map { ["name": $0.name, "slots": $0.slots.map(slotJSON)] },
    ])
}

// Which tool each slot requires: slots that turn 「未装备」 when only that tool is missing.
var requires: [String: String] = [:]
for tool in ["ffmpeg", "cwebp"] {
    Shell.installed = toolset("all").subtracting([tool])
    for name in ["x.png", "x.jpg", "x.pdf", "x.mp4", "x.mov", "x.mp3", "x.wav", "x.docx", "x.zip"] {
        for page in Catalog.context(for: materialize([name])).pages {
            for case let slot? in page.slots where slot.ammo == "未装备" { requires[slot.id] = tool }
        }
    }
}
Shell.installed = toolset("all")

let result: [String: Any] = [
    "upstreamCommit": CommandLine.arguments.dropFirst().first ?? "",
    "allIDs": Catalog.allIDs,
    "requires": requires,
    "traits": ["image": Catalog.imageTraits, "pdf": Catalog.pdfTraits, "video": Catalog.videoTraits,
               "audio": Catalog.audioTraits, "doc": Catalog.docTraits],
    "scenarios": out,
]
let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
try? FileManager.default.removeItem(at: root)
