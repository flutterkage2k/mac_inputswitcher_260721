import XCTest
@testable import InputSwitcher

final class ChangeClassifierTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_우리가_요청한_값으로_곧바로_바뀌면_ours() {
        let tag = classifyChange(newID: "ko", lastTarget: "ko",
                                 lastSwitchAt: t0, now: t0.addingTimeInterval(0.2))
        XCTAssertEqual(tag, "ours")
    }

    /// 우리 전환 직후 다른 값으로 바뀜 = 시스템이나 다른 앱이 되돌렸다는 의심 신호
    func test_우리_전환_직후_다른_값이면_external_after_ours() {
        let tag = classifyChange(newID: "en", lastTarget: "ko",
                                 lastSwitchAt: t0, now: t0.addingTimeInterval(0.8))
        XCTAssertEqual(tag, "external-after-ours")
    }

    /// 복구 왕복의 영어 경유는 우리가 만든 변경이다 (외부 되돌림으로 오분류되던 버그)
    func test_복구_중_경유지_변경은_ours_detour() {
        let tag = classifyChange(newID: "en", lastTarget: "ko", lastSwitchAt: t0,
                                 recovering: true, now: t0.addingTimeInterval(0.05))
        XCTAssertEqual(tag, "ours-detour")
    }

    func test_한참_뒤의_변경은_external() {
        let tag = classifyChange(newID: "ko", lastTarget: "ko",
                                 lastSwitchAt: t0, now: t0.addingTimeInterval(30))
        XCTAssertEqual(tag, "external")
    }

    func test_우리가_전환한_적_없으면_external() {
        let tag = classifyChange(newID: "ko", lastTarget: nil,
                                 lastSwitchAt: .distantPast, now: t0)
        XCTAssertEqual(tag, "external")
    }
}
