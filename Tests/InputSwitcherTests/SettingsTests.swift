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

    func test_앱규칙_저장_후_다시_읽기() {
        let s = Settings(defaults: defaults)
        let rule = AppRule(appName: "iTerm2", sourceID: "com.apple.keylayout.ABC")
        s.appRules = ["com.googlecode.iterm2": rule]
        XCTAssertEqual(Settings(defaults: defaults).appRules["com.googlecode.iterm2"], rule)
    }

    func test_앱규칙_빈_상태는_빈_딕셔너리() {
        XCTAssertTrue(Settings(defaults: defaults).appRules.isEmpty)
    }

    func test_showHUD_기본값_true_저장_유지() {
        XCTAssertTrue(Settings(defaults: defaults).showHUD)
        let s = Settings(defaults: defaults)
        s.showHUD = false
        XCTAssertFalse(Settings(defaults: defaults).showHUD)
    }

    func test_verifyDelay_기본값_150() {
        XCTAssertEqual(Settings(defaults: defaults).verifyDelayMS, 150)
    }

    func test_verifyDelay_저장() {
        let s = Settings(defaults: defaults)
        s.verifyDelayMS = 100
        XCTAssertEqual(Settings(defaults: defaults).verifyDelayMS, 100)
    }
}
