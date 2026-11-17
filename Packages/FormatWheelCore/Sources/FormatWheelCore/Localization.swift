import Foundation

/// Localised UI text. Keys are upstream's original zh-Hans strings (the String Catalog's source language).
/// `Localization.language` can pin a language (tests pin zh-Hans to compare with upstream verbatim).
public enum Localization {
    nonisolated(unsafe) public static var language: String? {
        didSet { cached = nil }
    }
    nonisolated(unsafe) private static var cached: Bundle?

    static var bundle: Bundle {
        if let cached { return cached }
        var result = Bundle.module
        if let language, let path = Bundle.module.path(forResource: language, ofType: "lproj"), let b = Bundle(path: path) {
            result = b
        }
        cached = result
        return result
    }
}

/// Looks up `key`; with arguments it is used as a format string (`%@`, `%lld`).
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Localization.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
}
