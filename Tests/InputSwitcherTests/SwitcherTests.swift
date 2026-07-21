import XCTest
@testable import InputSwitcher

final class MockAPI: InputSourceAPI {
    var current: String? = "en"
    /// select 호출이 이 횟수를 넘어야 실제 반영됨 (0 = 즉시 성공, 99 = select로는 불가)
    var selectSucceedsAfter = 0
    private var selectCalls = 0
    var sources = [InputSource(id: "en", name: "ABC"), InputSource(id: "ko", name: "한글")]
    var cycleOrder = ["en", "ko"]
    private var cycleIndex = 0
    private(set) var postShortcutCalls = 0

    func currentSourceID() -> String? { current }
    @discardableResult func select(_ id: String) -> Bool {
        selectCalls += 1
        if selectCalls > selectSucceedsAfter { current = id }
        return true
    }
    func selectableSources() -> [InputSource] { sources }
    func postSystemSwitchShortcut() {
        postShortcutCalls += 1
        cycleIndex = (cycleIndex + 1) % cycleOrder.count
        current = cycleOrder[cycleIndex]
    }
}

final class SwitcherTests: XCTestCase {
    private func makeSwitcher(_ api: MockAPI) -> Switcher {
        Switcher(api: api, verifyDelayMS: 0)
    }

    func test_직접_전환_성공() async {
        let api = MockAPI()
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.current, "ko")
    }

    func test_재시도로_성공() async {
        let api = MockAPI()
        api.selectSucceedsAfter = 1 // 첫 select는 무시됨 (CJK 버그 시뮬레이션)
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
    }

    func test_시스템단축키_순환_폴백으로_성공() async {
        let api = MockAPI()
        api.selectSucceedsAfter = 99 // select로는 절대 안 됨
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.current, "ko")
    }

    func test_폴백까지_실패하면_false() async {
        let api = MockAPI()
        api.selectSucceedsAfter = 99
        api.cycleOrder = ["en", "fr"] // 순환 목록에 목표가 없음
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertFalse(ok)
    }

    func test_취소된_전환은_폴백에_진입하지_않는다() async {
        let api = MockAPI()
        api.selectSucceedsAfter = 99 // select로는 절대 안 됨 → 폴백 직행 경로
        let switcher = Switcher(api: api, verifyDelayMS: 50)
        let task = Task { await switcher.switchTo("ko") }
        try? await Task.sleep(nanoseconds: 10_000_000) // 첫 검증 대기 도중 취소
        task.cancel()
        _ = await task.value
        XCTAssertEqual(api.postShortcutCalls, 0)
    }
}
