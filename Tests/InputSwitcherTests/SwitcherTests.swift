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
        InputSource(id: "ko", name: "한글", isCJKV: true),
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

    /// 같은 소스 재요청 = 앱 IME가 표시와 어긋났다는 신호.
    /// 실제 소스 변경만이 앱에 전달되므로 다른 소스로 갔다가 되돌아온다.
    func test_같은_소스_재요청은_왕복으로_복구() async {
        let api = MockAPI()
        api.current = "ko"
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.selectedIDs, ["en", "ko"]) // 중간 경유 후 목표 복귀
        XCTAssertEqual(api.current, "ko")
    }

    /// 경유지는 IME 세션을 새로 열지 않는 비CJKV 레이아웃을 우선한다
    func test_왕복_경유지는_비CJKV_우선() async {
        let api = MockAPI()
        api.sources = [
            InputSource(id: "ko", name: "한글", isCJKV: true),
            InputSource(id: "ja", name: "일본어", isCJKV: true),
            InputSource(id: "en", name: "ABC"),
        ]
        api.current = "ko"
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs.first, "en")
    }

    func test_소스가_하나뿐이면_왕복_없음() async {
        let api = MockAPI()
        api.sources = [InputSource(id: "en", name: "ABC")]
        api.current = "en"
        let ok = await makeSwitcher(api).switchTo("en")
        XCTAssertTrue(ok)
        XCTAssertTrue(api.selectedIDs.isEmpty)
    }

    /// CJKV 진입은 성공 후에도 선제 왕복을 한 번 돌린다 (한글 실패율 25.7% 대응)
    func test_CJKV_진입은_선제_왕복() async {
        let api = MockAPI()
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko", "en", "ko"])
        XCTAssertEqual(api.current, "ko")
    }

    /// 경유지로 CJKV를 쓰면 그 사이 타이핑이 한자로 변환돼 사용자가 지워야 한다.
    /// 절대 금지 — 다른 비CJKV가 없으면 출발지(영어)라도 경유한다.
    func test_경유지로_CJKV를_쓰지_않는다() async {
        let api = MockAPI()
        api.sources = [
            InputSource(id: "en", name: "ABC"),
            InputSource(id: "ko", name: "한글", isCJKV: true),
            InputSource(id: "ja", name: "일본어", isCJKV: true),
        ]
        api.current = "en"
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko", "en", "ko"])
    }

    /// 비CJKV가 여럿이면 그 안에서 출발지를 피한다
    func test_비CJKV가_여럿이면_출발지_회피() async {
        let api = MockAPI()
        api.sources = [
            InputSource(id: "en", name: "ABC"),
            InputSource(id: "fr", name: "French"),
            InputSource(id: "ko", name: "한글", isCJKV: true),
        ]
        api.current = "en"
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko", "fr", "ko"])
    }

    /// 비CJKV 경유지가 아예 없으면 왕복을 건너뛴다 (CJKV 경유보다 안 하는 게 낫다)
    func test_비CJKV_경유지_없으면_왕복_생략() async {
        let api = MockAPI()
        api.sources = [
            InputSource(id: "ko", name: "한글", isCJKV: true),
            InputSource(id: "ja", name: "일본어", isCJKV: true),
        ]
        api.current = "ja"
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko"])
    }

    /// 일본어→한글이면 출발지가 아닌 비CJKV(영어)를 경유
    func test_CJKV_출발이면_비CJKV_경유() async {
        let api = MockAPI()
        api.sources = [
            InputSource(id: "en", name: "ABC"),
            InputSource(id: "ko", name: "한글", isCJKV: true),
            InputSource(id: "ja", name: "일본어", isCJKV: true),
        ]
        api.current = "ja"
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko", "en", "ko"])
    }

    /// 소스가 둘뿐이면 피할 수 없으므로 출발지 경유 허용 (기존 동작)
    func test_소스_둘뿐이면_출발지_경유() async {
        let api = MockAPI()
        api.current = "en"
        _ = await makeSwitcher(api).switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko", "en", "ko"])
    }

    func test_선제_왕복_끄면_평소대로() async {
        let api = MockAPI()
        let s = makeSwitcher(api)
        s.preemptiveRoundTrip = false
        _ = await s.switchTo("ko")
        XCTAssertEqual(api.selectedIDs, ["ko"])
    }

    /// 비CJKV 진입에는 선제 왕복을 걸지 않는다 (실패율 낮고 지연만 늘어남)
    func test_비CJKV_진입은_선제_왕복_없음() async {
        let api = MockAPI()
        api.current = "ko"
        _ = await makeSwitcher(api).switchTo("en")
        XCTAssertEqual(api.selectedIDs, ["en"])
    }

    func test_비CJKV끼리_전환은_커밋_없음() async {
        let api = MockAPI()
        api.sources.append(InputSource(id: "fr", name: "French"))
        _ = await makeSwitcher(api).switchTo("fr")
        XCTAssertEqual(api.commitCalls, 0)
    }

    /// 왕복 모드에서는 글자를 가로채는 커밋 창을 띄우지 않는다
    func test_왕복_모드에서는_포커스_커밋을_쓰지_않는다() async {
        let api = MockAPI()
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.commitCalls, 0)
        XCTAssertEqual(api.selectedIDs, ["ko", "en", "ko"])
    }

    /// 왕복 도중 다음 전환이 끼어들면, 끊긴 왕복은 뒤늦게 복귀하면 안 된다
    func test_끊긴_왕복은_뒤늦게_복귀하지_않는다() async {
        let api = MockAPI()
        let switcher = makeSwitcher(api)
        switcher.roundTripDelayMS = 50
        let task = Task { await switcher.switchTo("ko") }
        try? await Task.sleep(nanoseconds: 10_000_000) // 경유지(en)에서 대기 중일 때 취소
        task.cancel()
        _ = await task.value
        XCTAssertEqual(api.selectedIDs, ["ko", "en"]) // 복귀 select("ko") 없음
    }

    /// 선제 왕복을 끄면 예전 커밋 방식으로 돌아간다
    func test_CJKV_전환은_포커스_커밋을_호출한다() async {
        let api = MockAPI()
        let switcher = makeSwitcher(api)
        switcher.preemptiveRoundTrip = false
        let ok = await switcher.switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.commitCalls, 1)
    }

    func test_비CJKV_전환은_포커스_커밋을_호출하지_않는다() async {
        let api = MockAPI()
        api.sources.append(InputSource(id: "fr", name: "French"))
        let ok = await makeSwitcher(api).switchTo("fr")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.commitCalls, 0)
    }

    func test_커밋_생략된_CJKV_이후에는_비CJKV_전환도_커밋한다() async {
        let api = MockAPI()
        let switcher = makeSwitcher(api)
        switcher.preemptiveRoundTrip = false // 커밋 방식에서만 해당
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
