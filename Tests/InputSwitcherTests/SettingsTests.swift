import XCTest
@testable import InputSwitcher

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")
    }

    func test_매핑_저장_후_다시_읽기() {
        let s = Settings(defaults: defaults)
        let combo = KeyCombo(keyCode: 40, carbonModifiers: 768, display: "⇧⌘K")
        s.mappings = ["com.apple.inputmethod.Korean.2SetKorean": combo]

        let reloaded = Settings(defaults: defaults)
        XCTAssertEqual(reloaded.mappings["com.apple.inputmethod.Korean.2SetKorean"], combo)
    }

    func test_빈_상태는_빈_매핑() {
        XCTAssertTrue(Settings(defaults: defaults).mappings.isEmpty)
    }

    func test_verifyDelay_기본값_30() {
        XCTAssertEqual(Settings(defaults: defaults).verifyDelayMS, 30)
    }

    func test_verifyDelay_저장() {
        let s = Settings(defaults: defaults)
        s.verifyDelayMS = 100
        XCTAssertEqual(Settings(defaults: defaults).verifyDelayMS, 100)
    }
}
