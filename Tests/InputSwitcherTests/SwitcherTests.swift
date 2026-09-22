import XCTest
@testable import InputSwitcher

@MainActor
final class MockAPI: InputSourceAPI {
    var current: String? = "en"
    /// select 호출이 이 횟수를 넘어야 실제 반영됨 (0 = 즉시 성공, 99 = select로는 불가)
    var selectSucceedsAfter = 0
    private(set) var selectCalls = 0
    private(set) var selectedIDs: [String] = []
    var sources = [
        InputSource(id: "en", name: "ABC"),
        InputSource(id: "ko", name: "한글", isCJKV: true, isKorean: true),
        InputSource(id: "ja", name: "일본어", isCJKV: true),
    ]
    var cycleOrder = ["en", "ko"]
    private var cycleIndex = 0
    private(set) var postShortcutCalls = 0
    private(set) var commitCalls = 0

    /// false면 패널 열림 등으로 커밋이 생략된 상황 시뮬레이션
    var commitRuns = true

    func currentSourceID() -> String? { current }
    @discardableResult func select(_ id: String) -> Bool {
        selectCalls += 1
        selectedIDs.append(id)
        if selectCalls > selectSucceedsAfter { current = id }
        return true
    }
    func selectableSources() -> [InputSource] { sources }
    func commitSelection(waitMS: UInt64) async -> Bool {
        commitCalls += 1
        return commitRuns
    }
    func postSystemSwitchShortcut() {
        postShortcutCalls += 1
        cycleIndex = (cycleIndex + 1) % cycleOrder.count
        current = cycleOrder[cycleIndex]
    }
}

@MainActor
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

    /// 한글 진입도 select 한 번으로 끝난다. 예전의 "왕복"(다른 소스를 경유했다
    /// 돌아오기)은 조합 중인 한글을 끊어 자소 분리를 일으켜 제거했다.
    func test_CJKV_진입도_select_한_번() async {
        let api = MockAPI()
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko"])
        XCTAssertEqual(api.commitCalls, 0)
    }

    /// 같은 소스 재입력 = "HUD는 한글인데 영어로 쳐진다"는 사용자 신호.
    /// 사용자가 손으로 하던 복구(영어로 갔다가 한글로)를 대신한다.
    func test_같은_소스_재입력은_복구_왕복() async {
        let api = MockAPI()
        api.current = "ko"
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.selectedIDs, ["en", "ko"])
        XCTAssertEqual(api.current, "ko")
        XCTAssertEqual(api.commitCalls, 0)
    }

    /// 경유지는 조합이 없는 비CJKV 레이아웃만. CJKV 경유는 그 사이 타이핑을 한자로 바꾼다.
    func test_복구_경유지는_비CJKV만() async {
        let api = MockAPI()
        api.sources = [
            InputSource(id: "ko", name: "한글", isCJKV: true),
            InputSource(id: "ja", name: "일본어", isCJKV: true),
            InputSource(id: "en", name: "ABC"),
        ]
        api.current = "ko"
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["en", "ko"])
    }

    func test_비CJKV_경유지_없으면_재입력은_무동작() async {
        let api = MockAPI()
        api.sources = [
            InputSource(id: "ko", name: "한글", isCJKV: true),
            InputSource(id: "ja", name: "일본어", isCJKV: true),
        ]
        api.current = "ko"
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertTrue(api.selectedIDs.isEmpty)
    }

    /// 경유 중 다음 전환이 끼어들면 뒤늦게 복귀하지 않는다 (새 전환과 엉킴 방지)
    func test_복구_왕복_취소되면_복귀_생략() async {
        let api = MockAPI()
        api.current = "ko"
        let switcher = makeSwitcher(api)
        switcher.recoveryDetourMS = 50
        let task = Task { await switcher.switchTo("ko") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        _ = await task.value
        XCTAssertEqual(api.selectedIDs, ["en"])
    }

    func test_기본값은_포커스_커밋을_쓰지_않는다() async {
        let api = MockAPI()
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.commitCalls, 0)
    }

    /// 일본어는 커밋 창을 쓰지 않는다. 커밋 창이 뜨면 일본어 IME가 우리 창에
    /// 달라붙었다 떨어지면서 한자 변환 후보창이 주인 없이 화면에 남는다.
    /// 실패율도 커밋 유무와 무관하게 14%로 같아 이득이 없다.
    func test_일본어_진입은_커밋하지_않는다() async {
        let api = MockAPI()
        let switcher = makeSwitcher(api)
        switcher.focusCommitEnabled = true
        _ = await switcher.switchTo("ja")
        XCTAssertEqual(api.commitCalls, 0)
        XCTAssertEqual(api.selectedIDs, ["ja"])
    }

    /// 한글만 커밋 창을 쓴다 (실패율 23% vs 미사용 33%)
    func test_포커스_커밋_켜면_한글_진입에_커밋() async {
        let api = MockAPI()
        let switcher = makeSwitcher(api)
        switcher.focusCommitEnabled = true
        let ok = await switcher.switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.commitCalls, 1)
    }

    func test_포커스_커밋_켜도_비CJKV는_커밋_안함() async {
        let api = MockAPI()
        api.sources.append(InputSource(id: "fr", name: "French"))
        let switcher = makeSwitcher(api)
        switcher.focusCommitEnabled = true
        _ = await switcher.switchTo("fr")
        XCTAssertEqual(api.commitCalls, 0)
    }

    func test_커밋_생략된_CJKV_이후에는_비CJKV_전환도_커밋한다() async {
        let api = MockAPI()
        let switcher = makeSwitcher(api)
        switcher.focusCommitEnabled = true
        api.commitRuns = false               // 패널 열림: 한글 선택, 커밋 생략
        _ = await switcher.switchTo("ko")
        XCTAssertEqual(api.commitCalls, 1)
        api.commitRuns = true                // 패널 닫힘
        _ = await switcher.switchTo("en")    // 미커밋 상태 → 비CJKV여도 커밋 수행
        XCTAssertEqual(api.commitCalls, 2)
        api.sources.append(InputSource(id: "fr", name: "French"))
        _ = await switcher.switchTo("fr")    // 미커밋 해소됨 → 커밋 없음
        XCTAssertEqual(api.commitCalls, 2)
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
