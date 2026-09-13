import XCTest
@testable import BatteryLens

final class BatteryLensTests: XCTestCase {
    func testApplicationNameIsStable() {
        XCTAssertEqual("BatteryLens", "BatteryLens")
    }
}
