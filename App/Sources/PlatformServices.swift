import FormatWheelCore
import UIKit

/// UIKit implementations of the capabilities FormatWheelCore cannot reach itself.
enum PlatformServices {
    static func install() {
        Platform.clipboard = Pasteboard()
        Platform.richText = RichText()
        Platform.deviceName = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}

private struct Pasteboard: ClipboardService {
    func set(_ text: String) {
        DispatchQueue.main.async { UIPasteboard.general.string = text }
    }
}

/// NSAttributedString RTF / HTML (the document types are declared in UIKit on iOS).
private struct RichText: RichTextCodec {
    private func type(_ format: String) throws -> NSAttributedString.DocumentType {
        switch format {
        case "rtf": return .rtf
        case "html": return .html
        default: throw FWError("不支持写入 \(format.uppercased())")
        }
    }

    func data(from text: NSAttributedString, format: String) throws -> Data {
        let docType = try type(format)
        return try onMain {
            try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: docType])
        }
    }

    func attributedString(from data: Data, format: String) throws -> NSAttributedString {
        let docType = try type(format)
        return try onMain {
            try NSAttributedString(data: data, options: [.documentType: docType, .characterEncoding: String.Encoding.utf8.rawValue],
                                   documentAttributes: nil)
        }
    }

    /// HTML import/export must run on the main thread.
    private func onMain<T>(_ work: () throws -> T) throws -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }
}
