import XCTest

/// Checks the app bundle is configured for Files-app access and "Open in…".
final class AppConfigurationTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testFilesAppAccess() {
        XCTAssertEqual(info["UIFileSharingEnabled"] as? Bool, true)
        XCTAssertEqual(info["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
        XCTAssertNotNil(info["NSPhotoLibraryAddUsageDescription"])
    }

    func testDeclaresDocumentTypes() throws {
        let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let all = Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        for uti in ["public.image", "com.adobe.pdf", "public.movie", "public.audio", "org.openxmlformats.wordprocessingml.document", "public.data"] {
            XCTAssertTrue(all.contains(uti), "missing \(uti)")
        }
    }

    func testFrameworksAreEmbedded() throws {
        let frameworks = try XCTUnwrap(Bundle.main.privateFrameworksURL)
        for name in ["FWFFmpeg", "FormatWheelCore", "FormatWheelArt"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("\(name).framework").path), "\(name).framework not embedded")
        }
    }
}
