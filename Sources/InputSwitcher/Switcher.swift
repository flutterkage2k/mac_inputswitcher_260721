import Foundation

struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
    var isCJKV = false
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

/// CJK 버그 우회의 핵심: select → (CJKV면 포커스 커밋) → 검증 → 재시도 → 시스템 단축키 폴백.
@MainActor
final class Switcher {
    private let api: InputSourceAPI
    var verifyDelayMS: UInt64
    /// CJKV가 커밋 없이 선택된 상태(패널 열림 중 전환). 이 상태를 떠나는 전환은
    /// 비CJKV 타깃이라도 커밋해야 실제 IME가 풀린다.
    private var pendingCommit = false
    /// 경유지 체류 시간. 앱이 소스 변경을 처리할 만큼은 길고, 오타 유발은 안 될 만큼 짧게.
    var roundTripDelayMS: UInt64 = 60

    private func recoverByRoundTrip(to id: String, sources: [InputSource]) async {
        // 경유지는 IME 세션을 새로 열지 않는 비CJKV 레이아웃을 우선
        let detour = sources.first { $0.id != id && !$0.isCJKV } ?? sources.first { $0.id != id }
        guard let detour else {
            dbg("switchTo: 같은 소스 재요청이나 경유할 소스 없음")
            return
        }
        dbg("switchTo: 같은 소스 재요청 → 왕복 복구 (\(detour.id) 경유)")
        api.select(detour.id)
        try? await Task.sleep(nanoseconds: roundTripDelayMS * 1_000_000)
        api.select(id)
    }

    private func commit() async {
        let committed = await api.commitSelection(waitMS: verifyDelayMS)
        pendingCommit = !committed
        if !committed { dbg("switchTo: 커밋 생략됨 → pendingCommit") }
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
            // 사용자가 같은 소스를 다시 요청 = TIS는 맞다고 하는데 앱 IME는 이전 언어에
            // 머물러 있다는 신호. TIS 값이 실제로 '바뀌어야' 앱에 전달되므로,
            // 다른 소스로 잠깐 갔다가 목표로 되돌아온다 (사용자가 손으로 하던 동작).
            // 포커스는 건드리지 않는다 — 커밋 방식은 키 삼킴/패널 닫힘을 유발했다.
            await recoverByRoundTrip(to: id, sources: sources)
            return true
        }

        let needsCommit = isCJKV(id) || pendingCommit
        if isCJKV(current) && !needsCommit {
            // CJKV 이탈 시 커밋은 카카오톡 회귀를 유발해 보류. 빈도만 계측.
            dbg("switchTo: CJKV 이탈, 커밋 없이 select만")
        }
        for attempt in 0..<2 {
            dbg("switchTo: attempt \(attempt) select")
            api.select(id)
            if needsCommit {
                await commit()
            }
            if Task.isCancelled { return true }
            if api.currentSourceID() == id { return true }
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
