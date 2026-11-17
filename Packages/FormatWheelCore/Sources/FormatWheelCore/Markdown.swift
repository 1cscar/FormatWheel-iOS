import Foundation

/// Port of upstream DocOps.swift `Markdown` — headings, emphasis, code, lists, quotes, links.
/// (Used by pdf.to.md in P1; the rest of DocOps lands in P3.)
enum Markdown {
    static func toHTML(_ source: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var list: String?
        var inCode = false
        var code: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                html.append("<p>" + paragraph.map(inline).joined(separator: "<br>") + "</p>")
                paragraph = []
            }
        }
        func closeList() {
            if let tag = list { html.append("</\(tag)>"); list = nil }
        }

        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode {
                    html.append("<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>")
                    code = []
                } else {
                    flushParagraph(); closeList()
                }
                inCode.toggle()
                continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { flushParagraph(); closeList(); continue }

            if let level = headingLevel(line) {
                flushParagraph(); closeList()
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                html.append("<h\(level)>\(inline(text))</h\(level)>")
            } else if line == "---" || line == "***" || line == "___" {
                flushParagraph(); closeList()
                html.append("<hr>")
            } else if line.hasPrefix(">") {
                flushParagraph(); closeList()
                html.append("<blockquote>\(inline(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))</blockquote>")
            } else if let item = bullet(line) {
                flushParagraph()
                if list != "ul" { closeList(); html.append("<ul>"); list = "ul" }
                html.append("<li>\(inline(item))</li>")
            } else if let item = numbered(line) {
                flushParagraph()
                if list != "ol" { closeList(); html.append("<ol>"); list = "ol" }
                html.append("<li>\(inline(item))</li>")
            } else {
                closeList()
                paragraph.append(line)
            }
        }
        if inCode { html.append("<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>") }
        flushParagraph(); closeList()
        // Named public fonts: "-apple-system" would embed private ".SFNS" names that other apps can't resolve.
        let style = "body{font-family:'Helvetica Neue','PingFang SC',sans-serif;font-size:14px;line-height:1.6;color:#111}h1,h2,h3{margin:18px 0 8px}p{margin:0 0 10px}ul,ol{margin:0 0 14px}code,pre{font-family:Menlo,monospace;font-size:12px}blockquote{color:#555}"
        return "<html><head><meta charset=\"utf-8\"><style>\(style)</style></head><body>\(html.joined(separator: "\n"))</body></html>"
    }

    static func plain(_ source: String) -> String {
        source.components(separatedBy: .newlines).map { raw -> String in
            var line = raw
            if headingLevel(line.trimmingCharacters(in: .whitespaces)) != nil {
                line = String(line.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            }
            for token in ["**", "__", "`"] { line = line.replacingOccurrences(of: token, with: "") }
            return line
        }.joined(separator: "\n")
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numbered(_ line: String) -> String? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func inline(_ text: String) -> String {
        var s = escape(text)
        let rules: [(String, String)] = [
            (#"!\[([^\]]*)\]\(([^)]+)\)"#, "$1"),
            (#"\[([^\]]+)\]\(([^)]+)\)"#, "<a href=\"$2\">$1</a>"),
            (#"`([^`]+)`"#, "<code>$1</code>"),
            (#"\*\*([^*]+)\*\*"#, "<b>$1</b>"),
            (#"__([^_]+)__"#, "<b>$1</b>"),
            (#"(?<![*\w])\*([^*]+)\*(?!\*)"#, "<i>$1</i>"),
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }

    /// Attributed text to Markdown, inferring headings from font size and weight.
    static func from(_ text: NSAttributedString) -> String {
        let full = NSRange(location: 0, length: text.length)
        var sizes: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            if let font = FontInfo(value) { sizes[font.pointSize.rounded(), default: 0] += range.length }
        }
        let body = sizes.max { $0.value < $1.value }?.key ?? 12

        var lines: [String] = []
        (text.string as NSString).enumerateSubstrings(in: full, options: .byParagraphs) { _, range, _, _ in
            let paragraph = text.attributedSubstring(from: range)
            let plain = paragraph.string.trimmingCharacters(in: .whitespaces)
            if plain.isEmpty {
                if lines.last != "" { lines.append("") }
                return
            }
            var largest: CGFloat = 0
            var allBold = true
            paragraph.enumerateAttribute(.font, in: NSRange(location: 0, length: paragraph.length)) { value, r, _ in
                guard let font = FontInfo(value) else { return }
                let piece = (paragraph.string as NSString).substring(with: r).trimmingCharacters(in: .whitespaces)
                if piece.isEmpty { return }
                largest = max(largest, font.pointSize)
                if !font.isBold { allBold = false }
            }
            let line: String
            if largest >= body * 1.55 {
                line = "# " + plain
            } else if largest >= body * 1.28 {
                line = "## " + plain
            } else if largest >= body * 1.1 || (allBold && plain.count <= 40) {
                line = "### " + plain
            } else {
                var md = emphasised(paragraph).trimmingCharacters(in: .whitespaces)
                if let first = md.first, "•◦▪●·–".contains(first) {
                    md = "- " + md.dropFirst().trimmingCharacters(in: .whitespaces)
                }
                line = md
            }
            if line.hasPrefix("#"), lines.last.map({ !$0.isEmpty }) == true { lines.append("") }
            lines.append(line)
            if line.hasPrefix("#") { lines.append("") }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func emphasised(_ paragraph: NSAttributedString) -> String {
        var out = ""
        paragraph.enumerateAttribute(.font, in: NSRange(location: 0, length: paragraph.length)) { value, r, _ in
            let piece = (paragraph.string as NSString).substring(with: r)
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if let font = FontInfo(value), font.isBold, !trimmed.isEmpty {
                let lead = piece.prefix(while: { $0 == " " }), tail = String(piece.reversed().prefix(while: { $0 == " " }))
                out += lead + "**" + trimmed + "**" + tail
            } else {
                out += piece
            }
        }
        return out
    }
}
