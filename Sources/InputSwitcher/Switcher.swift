import Foundation

struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
    /// 한/중/일/베트남어 — 조합·변환 과정이 있는 입력기. 경유지로 쓰면 안 된다.
    var isCJKV = false
    /// 커밋 창은 한글에만 쓴다 (아래 needsCommit 주석 참고)
    var isKorean = false
}

/// TIS API는 메인 스레드를 요구한다 — Tahoe에서 백그라운드 스레드 호출 시
/// HIToolbox의 dispatch assert로 크래시하므로 프로토콜 전체를 MainActor로 격리.
@MainActor
protocol InputSourceAPI {
    func currentSourceID() -> String?
    @discardableResult func select(_ id: String) -> Bool
    func selectableSources() -> [InputSource]
    /// CJKV 선택을 실제로 커밋한다. TISSelectInputSource는 백그라운드 앱에서 CJKV로
    /// 전환 시 아이콘만 바꾸고 실제 IME는 안 바꾸므로, 잠깐 자기 앱이 key가 됐다가
    /// 돌아오는 포커스 사이클로 커밋시킨다 (macism 방식).
    /// 반환: 실제로 커밋을 수행했으면 true, (패널 열림 등으로) 생략했으면 false.
    func commitSelection(waitMS: UInt64) async -> Bool
    /// 우리 앱을 잠깐 활성화했다가 원래 앱으로 돌려준다 (사용자의 "다른 앱 갔다 오기").
    /// 앱이 포커스를 되찾을 때 입력 세션이 새로 만들어지면서 현재 언어를 제대로 읽는다.
    /// 반환: 실제로 수행했으면 true, (런처 패널이 떠 있어) 생략했으면 false.
    func cycleAppFocus(waitMS: UInt64) async -> Bool
    func postSystemSwitchShortcut()
}

/// 전환 흐름: select → 검증 → 재시도 → 시스템 단축키 폴백.
@MainActor
final class Switcher {
    private let api: InputSourceAPI
    var verifyDelayMS: UInt64
    /// 포커스 커밋(보이지 않는 창이 키 입력을 받는 방식) 사용 여부.
    /// 사용자가 친 글자를 가로채는 게 실측돼 기본값은 꺼짐. 예전 방식 복원용.
    var focusCommitEnabled = false
    /// 복구 왕복의 경유지 체류 시간
    var recoveryDetourMS: UInt64 = 60

    /// 같은 소스 재입력 시 복구: 비CJKV 레이아웃을 잠깐 경유했다 목표로 돌아온다.
    /// 사용자가 손으로 하던 "영어로 갔다가 다시 한글" 조작의 자동화.
    ///
    /// 진입 직후 자동으로 돌리는 왕복은 넣지 않는다 — 막 타이핑을 시작하는 순간과
    /// 겹쳐 한글 조합을 끊었고(자소 분리 70%), 그래서 제거했다. 다시 누르는 시점은
    /// 이미 타이핑이 영어로 나오는 상태라 끊길 한글 조합이 없다.
    /// 경유지는 조합이 없는 비CJKV만 쓴다. CJKV 경유는 그 사이 타이핑을 한자로 바꾼다.
    /// 같은 소스 재입력 시 복구.
    ///
    /// 1순위는 앱 왕복이다. 사용자가 실제로 효과를 본 방법이 "다른 앱 갔다 오기"이고,
    /// 앱별 자동 전환(앱이 막 활성화되는 순간)만 실패율 5%로 유독 낮았던 것도 같은
    /// 이유로 보인다. 커밋 창은 키보드 포커스만 가져올 뿐 앱을 비활성화하지 않아
    /// 이 효과가 없었다.
    ///
    /// 런처 패널이 떠 있어 앱 왕복을 못 하면 예전의 언어 왕복으로 대체한다.
    private func recover(to id: String, sources: [InputSource]) async {
        if await api.cycleAppFocus(waitMS: recoveryDetourMS) {
            dbg("switchTo: 같은 소스 재입력 → 앱 왕복")
            return
        }
        dbg("switchTo: 앱 왕복 불가 → 언어 왕복으로 대체")
        guard let detour = sources.first(where: { !$0.isCJKV && $0.id != id }) else {
            dbg("switchTo: 같은 소스 재입력, 경유할 비CJKV 없음 → 무동작")
            return
        }
        dbg("switchTo: 같은 소스 재입력 → 복구 왕복 (\(detour.id) 경유)")
        api.select(detour.id)
        try? await Task.sleep(nanoseconds: recoveryDetourMS * 1_000_000)
        // 다음 전환이 끼어들어 취소됐으면 복귀하지 않는다 (뒤늦은 복귀가 새 전환과 엉킴)
        guard !Task.isCancelled else {
            dbg("switchTo: 복구 왕복 취소됨, 복귀 생략")
            return
        }
        api.select(id)
    }

    private func commit() async {
        _ = await api.commitSelection(waitMS: verifyDelayMS)
    }

    init(api: InputSourceAPI, verifyDelayMS: UInt64 = 150) {
        self.api = api
        self.verifyDelayMS = verifyDelayMS
    }

    func switchTo(_ id: String) async -> Bool {
        let sources = api.selectableSources()
        let current = api.currentSourceID()
        dbg("switchTo(\(id)) — current=\(current ?? "?")")

        func isCJKV(_ sourceID: String?) -> Bool {
            guard let sourceID else { return false }
            return sources.first { $0.id == sourceID }?.isCJKV ?? false
        }

        if current == id {
            // 사용자가 같은 소스를 다시 누름 = macOS는 이 소스라고 하는데(HUD도 그렇게
            // 뜸) 앱 안의 입력기는 이전 언어에 머문 상태. 로그 기준 한글 진입의 약 20%.
            await recover(to: id, sources: sources)
            return true
        }

        // 커밋 창은 한글에만, 그리고 select가 실패했을 때만 쓴다.
        //
        // 매번 띄우던 방식은 성공하는 전환(약 3분의 2)에까지 부작용을 지웠다 —
        // 창이 0.15초 key를 가져가는 동안 사용자가 친 글자를 먹는다(dev12 25시간 7회).
        // 먼저 select 해보고 읽어서 확인한 뒤, 안 됐을 때만 창을 띄우고 재시도한다.
        // (nuridol/SwitchIM 방식)
        //
        // 일본어는 실패해도 쓰지 않는다. IME가 우리 창에 붙었다 떨어지며 한자 변환
        // 후보창이 주인 없이 남는다. 이득도 없다 — 일본어 진입 실패율은 커밋 유무와
        // 무관하게 14%로 같았다(커밋 O 12/83, X 16/118).
        let canCommit = focusCommitEnabled
            && (sources.first { $0.id == id }?.isKorean ?? false)
        if isCJKV(current) && !canCommit {
            dbg("switchTo: CJKV 이탈, 커밋 없이 select만")
        }
        for attempt in 0..<2 {
            dbg("switchTo: attempt \(attempt) select")
            api.select(id)
            if api.currentSourceID() == id { return true }   // 한 번에 성공 = 창 불필요
            if attempt == 0, canCommit {
                await commit()                                // 실패했을 때만 창을 띄운다
                api.select(id)
                if api.currentSourceID() == id { return true }
            }
            if Task.isCancelled { return true }
            try? await Task.sleep(nanoseconds: verifyDelayMS * 1_000_000)
            if Task.isCancelled { return true }
            if api.currentSourceID() == id { return true }
        }
        // 폴백: 시스템 "다음 소스 선택" 단축키로 순환. 소스 개수만큼만 시도.
        dbg("switchTo: 검증 실패 → 폴백 진입 (current=\(api.currentSourceID() ?? "?"))")
        for _ in 0..<max(1, api.selectableSources().count) {
            api.postSystemSwitchShortcut()
            try? await Task.sleep(nanoseconds: verifyDelayMS * 1_000_000)
            if Task.isCancelled { return true }
            if api.currentSourceID() == id { return true }
        }
        return false
    }
}
