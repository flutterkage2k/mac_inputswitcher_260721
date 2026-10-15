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

    /// 같은 소스 재입력 시 복구.
    ///
    /// 한글은 커밋 창(nonactivating)을 쓴다. 앱 왕복(우리 앱을 잠깐 활성화)은 복구율은
    /// 가장 좋았지만(왕복 뒤 또 누름 0.14회 vs 언어 왕복 1.2~1.5회) 앱을 비활성화해
    /// Finder 이름바꾸기를 끝내버렸다 (dev14 로그로 확인, v1.0.1에서 고쳤던 것과
    /// 같은 버그). 커밋 창은 앱 활성 상태를 유지한다.
    ///
    /// 그 외(일본어 등)나 커밋이 생략되면(런처 패널 열림) 언어 왕복: 비CJKV 레이아웃을
    /// 잠깐 경유했다 돌아온다. 경유지는 조합이 없는 비CJKV만 — CJKV 경유는 그 사이
    /// 타이핑을 한자로 바꾼다. 진입 직후 자동 왕복은 한글 조합을 끊어(자소 분리 70%)
    /// 넣지 않는다. 다시 누르는 시점은 이미 영어로 쳐지는 상태라 끊길 조합이 없다.
    private func recover(to id: String, sources: [InputSource], canCommit: Bool) async {
        if canCommit {
            // dev16: 커밋 창 전에 select를 한 번 더 한다. Keyboard Maestro의 Set Keyboard
            // Layout(같은 소스 재선택)을 앱과 같은 키에 병행했을 때 체감이 나았다는 보고 —
            // dev15(커밋 창만, 37%/105회)와의 유일한 차이가 이 재선택이다.
            api.select(id)
            if await api.commitSelection(waitMS: verifyDelayMS) {
                dbg("switchTo: 같은 소스 재입력 → 재선택 + 커밋 창")
                return
            }
        }
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

        // 커밋 창은 한글에만 쓴다 (일본어 이유는 아래)
        let canCommit = focusCommitEnabled
            && (sources.first { $0.id == id }?.isKorean ?? false)

        if current == id {
            // 사용자가 같은 소스를 다시 누름 = macOS는 이 소스라고 하는데(HUD도 그렇게
            // 뜸) 앱 안의 입력기는 이전 언어에 머문 상태. 로그 기준 한글 진입의 약 20%.
            await recover(to: id, sources: sources, canCommit: canCommit)
            return true
        }

        // 진입 시 커밋 창은 select가 실패했을 때만 쓴다.
        //
        // 매번 띄우던 방식은 성공하는 전환(약 3분의 2)에까지 부작용을 지웠다 —
        // 창이 0.15초 key를 가져가는 동안 사용자가 친 글자를 먹는다(dev12 25시간 7회).
        // 먼저 select 해보고 읽어서 확인한 뒤, 안 됐을 때만 창을 띄우고 재시도한다.
        // (nuridol/SwitchIM 방식)
        // 실측상 이 경로는 거의 안 탄다(dev13~14 9일간 0회). TIS는 실제 입력기가 안
        // 바뀌어도 바뀌었다고 보고하기 때문이다. 실패는 사용자의 재입력으로만 드러난다.
        //
        // 일본어는 실패해도 쓰지 않는다. IME가 우리 창에 붙었다 떨어지며 한자 변환
        // 후보창이 주인 없이 남는다. 이득도 없다 — 일본어 진입 실패율은 커밋 유무와
        // 무관하게 14%로 같았다(커밋 O 12/83, X 16/118).
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
