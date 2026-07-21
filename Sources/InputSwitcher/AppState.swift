import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var sources: [InputSource] = []
    @Published var mappings: [String: KeyCombo] = [:]
    @Published var currentID: String?
    @Published var recordingFor: String?          // 녹화 중인 소스 ID
    @Published var failedRegistrations: Set<String> = []
    @Published var lastSwitchFailed = false       // 폴백까지 실패 시 메뉴바 아이콘 표시용

    /// 매핑은 있는데 시스템에서 제거된 소스 ID들 (설정 화면에 "소스 없음"으로 표시)
    var orphanedMappings: [String] {
        mappings.keys.filter { id in !sources.contains(where: { $0.id == id }) }.sorted()
    }

    private let api = SystemInputSourceAPI()
    private let settings = Settings()
    private let hotkeys = HotkeyManager()
    private lazy var switcher = Switcher(api: api, verifyDelayMS: settings.verifyDelayMS)

    init() {
        sources = api.selectableSources()
        mappings = settings.mappings
        currentID = api.currentSourceID()
        registerAll()
    }

    func registerAll() {
        hotkeys.unregisterAll()
        failedRegistrations = []
        for (sourceID, combo) in mappings {
            // 시스템에서 제거된 소스의 매핑은 무시 (스펙: 에러 처리)
            guard sources.contains(where: { $0.id == sourceID }) else { continue }
            let ok = hotkeys.register(combo) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.lastSwitchFailed = !(await self.switcher.switchTo(sourceID))
                    self.currentID = self.api.currentSourceID()
                }
            }
            if !ok { failedRegistrations.insert(sourceID) }
        }
    }

    func setCombo(_ combo: KeyCombo?, for sourceID: String) {
        if let combo {
            mappings[sourceID] = combo
        } else {
            mappings.removeValue(forKey: sourceID)
        }
        settings.mappings = mappings
        registerAll()
    }

    func refreshCurrent() {
        currentID = api.currentSourceID()
    }
}
