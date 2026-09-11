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
    /// CJKV 진입 후 선제 왕복 여부. 한글 진입 재요청률이 25.7%로 영·일(9%)의 3배라
    /// 사후 복구만으로는 부족해 진입 직후에도 같은 왕복을 한 번 돌린다.
    /// 켜져 있으면 포커스 커밋을 대체한다 (끄면 예전 커밋 방식으로 돌아감).
    var preemptiveRoundTrip = true

    /// 경유지 선택. 절대 규칙: CJKV는 경유지로 쓰지 않는다.
    /// 일본어를 경유하게 했더니 60ms 사이에 들어간 타이핑이 한자로 변환돼
    /// 사용자가 지워야 하는 상황이 생겼다 — 전환이 씹히는 것보다 나쁜 결과다.
    /// 영문 레이아웃은 조합이 없어 최악이라도 알파벳 몇 글자가 스치는 정도다.
    /// 그 안에서만 출발지를 피하고, 피할 수 없으면 출발지라도 쓴다.
    private func detour(target: String, from: String?, sources: [InputSource]) -> InputSource? {
        let plain = sources.filter { !$0.isCJKV && $0.id != target }
        return plain.first { $0.id != from } ?? plain.first
    }

    private func roundTrip(to id: String, from: String?, sources: [InputSource], reason: String) async {
        guard !Task.isCancelled else { return }
        guard let detour = detour(target: id, from: from, sources: sources) else {
            dbg("switchTo: \(reason) 필요하나 경유할 소스 없음")
            return
        }
        dbg("switchTo: \(reason) (\(detour.id) 경유)")
        api.select(detour.id)
        try? await Task.sleep(nanoseconds: roundTripDelayMS * 1_000_000)
        // 다음 전환이 이 왕복을 취소했다면 복귀하지 않는다. 뒤늦은 복귀 select가
        // 새 전환과 엉켜 검증 실패, 재시도, 커밋 창 재등장으로 이어졌다.
        guard !Task.isCancelled else {
            dbg("switchTo: \(reason) 취소됨, 복귀 생략")
            return
        }
        api.select(id)
    }

    /// TIS 수준 전환 성공 후, 앱 IME 세션까지 따라오게 만드는 마무리 단계.
    private func settle(_ id: String, from: String?, _ sources: [InputSource]) async -> Bool {
        guard preemptiveRoundTrip,
              sources.first(where: { $0.id == id })?.isCJKV == true else { return true }
        await roundTrip(to: id, from: from, sources: sources, reason: "선제 왕복")
        return true
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
            // 복구 왕복은 출발지 개념이 없다 (이미 목표에 있음) — 비CJKV 경유 우선
            await roundTrip(to: id, from: nil, sources: sources, reason: "같은 소스 재요청 → 왕복 복구")
            return true
        }

        // 선제 왕복 모드에서는 포커스 커밋(보이지 않는 창이 0.15초 동안 키 입력을 받는
        // 방식)을 쓰지 않는다. 그 창이 사용자가 친 글자를 가로채 버리는 게 실측됐다
        // (dev4 1.8일간 11회). 왕복은 입력소스 값만 바꾸고 창을 띄우지 않아 글자를 먹을 수 없다.
        let needsCommit = (isCJKV(id) && !preemptiveRoundTrip) || pendingCommit
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
            if api.currentSourceID() == id { return await settle(id, from: current, sources) }
            try? await Task.sleep(nanoseconds: verifyDelayMS * 1_000_000)
            if Task.isCancelled { return true }
            if api.currentSourceID() == id { return await settle(id, from: current, sources) }
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
