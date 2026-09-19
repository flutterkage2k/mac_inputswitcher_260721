import XCTest
@testable import InputSwitcher

@MainActor
final class ModifierWaitTests: XCTestCase {
    func test_보조키가_안_눌려_있으면_즉시_반환() async {
        let r = await waitForModifierRelease(isDown: { false })
        XCTAssertEqual(r.waitedMS, 0)
        XCTAssertFalse(r.timedOut)
    }

    func test_뗄_때까지_기다린다() async {
        var remaining = 3 // 세 번은 눌린 상태, 그다음 해제
        let r = await waitForModifierRelease(isDown: {
            remaining -= 1
            return remaining >= 0
        }, timeoutMS: 1000, pollMS: 5)
        XCTAssertEqual(r.waitedMS, 15)
        XCTAssertFalse(r.timedOut)
    }

    /// 계속 누르고 있으면 무한정 기다리지 않고 진행한다
    func test_계속_누르고_있으면_시간초과() async {
        let r = await waitForModifierRelease(isDown: { true }, timeoutMS: 30, pollMS: 5)
        XCTAssertTrue(r.timedOut)
        XCTAssertEqual(r.waitedMS, 30)
    }

    /// 다음 단축키가 끼어들어 취소되면 곧바로 빠져나온다
    func test_취소되면_바로_반환() async {
        let task = Task { @MainActor in
            await waitForModifierRelease(isDown: { true }, timeoutMS: 5000, pollMS: 5)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let r = await task.value
        XCTAssertFalse(r.timedOut)
        XCTAssertLessThan(r.waitedMS, 1000)
    }
}
