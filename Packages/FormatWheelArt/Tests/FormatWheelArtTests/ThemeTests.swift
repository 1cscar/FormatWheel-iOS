import XCTest
@testable import FormatWheelArt

final class ThemeTests: XCTestCase {
    func testCrewColoursMatchUpstream() {
        XCTAssertEqual(Crew.allCases.count, 4)
        XCTAssertEqual(Crew.online.rgb.b, 0.90, accuracy: 0.0001)
        XCTAssertEqual(Crew.trevor.rgb.r, 1.00, accuracy: 0.0001)
    }
}
