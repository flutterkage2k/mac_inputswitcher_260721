import XCTest
@testable import InputSwitcher

final class UpdateCheckerTests: XCTestCase {
    func test_버전_비교() {
        XCTAssertTrue(isVersion("0.1.0", olderThan: "0.2.0"))
        XCTAssertTrue(isVersion("v0.2.0", olderThan: "v0.10.0"))   // 숫자 비교 (문자열 비교 아님)
        XCTAssertTrue(isVersion("0.2", olderThan: "0.2.1"))
        XCTAssertFalse(isVersion("0.2.0", olderThan: "v0.2.0"))    // 같음
        XCTAssertFalse(isVersion("1.0.0", olderThan: "0.9.9"))
        XCTAssertFalse(isVersion("dev", olderThan: "0.0.0"))       // 파싱 불가 → 업데이트 아님
    }
}
