import Foundation

struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
}

protocol InputSourceAPI {
    func currentSourceID() -> String?
    @discardableResult func select(_ id: String) -> Bool
    func selectableSources() -> [InputSource]
    func postSystemSwitchShortcut()
}

/// CJK 버그 우회의 핵심: select → 검증 → 재시도 → 시스템 전환 단축키 순환 폴백.
final class Switcher {
    private let api: InputSourceAPI
    var verifyDelayMS: UInt64

    init(api: InputSourceAPI, verifyDelayMS: UInt64 = 30) {
        self.api = api
        self.verifyDelayMS = verifyDelayMS
    }

    func switchTo(_ id: String) async -> Bool {
        for _ in 0..<2 {
            api.select(id)
            try? await Task.sleep(nanoseconds: verifyDelayMS * 1_000_000)
            if api.currentSourceID() == id { return true }
        }
        // 폴백: 시스템 "다음 소스 선택" 단축키로 순환. 소스 개수만큼만 시도.
        for _ in 0..<max(1, api.selectableSources().count) {
            api.postSystemSwitchShortcut()
            try? await Task.sleep(nanoseconds: verifyDelayMS * 1_000_000)
            if api.currentSourceID() == id { return true }
        }
        return false
    }
}
