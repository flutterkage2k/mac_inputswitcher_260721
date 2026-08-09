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
    /// 같은 소스 재요청 강제 커밋의 디바운스 (연타로 커밋이 쏟아지지 않게)
    var sameSourceCommitInterval: TimeInterval = 2
    private var nextSameSourceCommit = Date.distantPast

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

        // 같은 소스를 다시 요청 = 표시와 실제 IME가 어긋났다는 사용자 신호.
        // 이때가 유일한 복구 기회이므로 커밋을 강제한다 (습관적 연타는 디바운스로 흡수).
        if current == id {
            guard Date() >= nextSameSourceCommit else {
                dbg("switchTo: 같은 소스 재요청, 디바운스로 생략")
                return true
            }
            nextSameSourceCommit = Date().addingTimeInterval(sameSourceCommitInterval)
            dbg("switchTo: 같은 소스 재요청 → 강제 커밋")
            await commit()
            return true
        }

        // CJKV로 들어갈 때뿐 아니라 CJKV에서 나올 때도 커밋해야 이전 IME 세션이 풀린다.
        let needsCommit = isCJKV(id) || isCJKV(current) || pendingCommit
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
