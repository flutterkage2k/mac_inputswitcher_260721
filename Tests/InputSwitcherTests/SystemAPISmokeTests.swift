import XCTest
@testable import InputSwitcher

@MainActor
final class SystemAPISmokeTests: XCTestCase {
    func test_실제_소스목록과_현재소스_조회() {
        let api = SystemInputSourceAPI()
        XCTAssertFalse(api.selectableSources().isEmpty, "선택 가능한 입력소스가 최소 1개는 있어야 함")
        XCTAssertNotNil(api.currentSourceID())
    }
}
