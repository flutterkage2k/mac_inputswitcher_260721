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
    func commitSelection(waitMS: UInt64) async
    func postSystemSwitchShortcut()
}

/// CJK 버그 우회의 핵심: select → (CJKV면 포커스 커밋) → 검증 → 재시도 → 시스템 단축키 폴백.
@MainActor
final class Switcher {
    private let api: InputSourceAPI
    var verifyDelayMS: UInt64

    init(api: InputSourceAPI, verifyDelayMS: UInt64 = 150) {
        self.api = api
        self.verifyDelayMS = verifyDelayMS
    }

    func switchTo(_ id: String) async -> Bool {
        dbg("switchTo(\(id)) — current=\(api.currentSourceID() ?? "?")")
        if api.currentSourceID() == id {
            dbg("switchTo: 이미 현재 소스, no-op")
            return true
        }
        let isCJKV = api.selectableSources().first { $0.id == id }?.isCJKV ?? false
        for attempt in 0..<2 {
            dbg("switchTo: attempt \(attempt) select")
            api.select(id)
            if isCJKV {
                await api.commitSelection(waitMS: verifyDelayMS)
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
