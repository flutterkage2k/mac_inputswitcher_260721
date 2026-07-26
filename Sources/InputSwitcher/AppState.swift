import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var sources: [InputSource] = []
    @Published var mappings: [String: KeyCombo] = [:]
    @Published var currentID: String?
    @Published var recordingFor: String?          // 녹화 중인 소스 ID
    @Published var failedRegistrations: Set<String> = []
    @Published var lastSwitchFailed = false       // 폴백까지 실패 시 메뉴바 아이콘 표시용
    @Published var showHUD: Bool {
        didSet { settings.showHUD = showHUD }
    }

    /// 매핑은 있는데 시스템에서 제거된 소스 ID들 (설정 화면에 "소스 없음"으로 표시)
    var orphanedMappings: [String] {
        mappings.keys.filter { id in !sources.contains(where: { $0.id == id }) }.sorted()
    }

    @Published var appRules: [String: AppRule] = [:]

    private let api = SystemInputSourceAPI()
    private let settings = Settings()
    private let hotkeys = HotkeyManager()
    private lazy var switcher = Switcher(api: api, verifyDelayMS: settings.verifyDelayMS)
    private var switchTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var lastActivatedBundleID: String?

    init() {
        showHUD = Settings().showHUD
        sources = api.selectableSources()
        mappings = settings.mappings
        appRules = settings.appRules
        currentID = api.currentSourceID()
        registerAll()
        observeAppActivations()
    }

    private func observeAppActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            Task { @MainActor in self?.appDidActivate(bundleID) }
        }
    }

    private func appDidActivate(_ bundleID: String) {
        // CJKV 커밋의 포커스 사이클(규칙 앱→자신→규칙 앱)이 규칙을 재발동해
        // 무한 루프가 되지 않도록: 자신은 무시, 같은 앱 연속 재활성화도 무시.
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        guard bundleID != lastActivatedBundleID else { return }
        lastActivatedBundleID = bundleID
        guard let rule = appRules[bundleID],
              api.currentSourceID() != rule.sourceID,
              sources.contains(where: { $0.id == rule.sourceID }) else { return }
        dbg("autoSwitch: \(bundleID) → \(rule.sourceID)")
        performSwitch(to: rule.sourceID)
    }

    private func performSwitch(to sourceID: String) {
        switchTask?.cancel()
        switchTask = Task { @MainActor in
            let ok = await switcher.switchTo(sourceID)
            if !Task.isCancelled {
                lastSwitchFailed = !ok
                currentID = api.currentSourceID()
                if ok, showHUD,
                   let name = sources.first(where: { $0.id == sourceID })?.name {
                    HUD.shared.show(name)
                }
            }
        }
    }

    func registerAll() {
        hotkeys.unregisterAll()
        failedRegistrations = []
        for (sourceID, combo) in mappings {
            // 시스템에서 제거된 소스의 매핑은 무시 (스펙: 에러 처리)
            guard sources.contains(where: { $0.id == sourceID }) else { continue }
            let ok = hotkeys.register(combo) { [weak self] in
                self?.performSwitch(to: sourceID)
            }
            if !ok { failedRegistrations.insert(sourceID) }
        }
    }

    func setCombo(_ combo: KeyCombo?, for sourceID: String) {
        if let combo {
            // 동일 단축키가 다른 소스에 이미 할당돼 있으면 제거 (last-wins)
            mappings = mappings.filter { $0.key == sourceID || $0.value != combo }
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

    func addAppRule(bundleID: String, appName: String, sourceID: String) {
        appRules[bundleID] = AppRule(appName: appName, sourceID: sourceID)
        settings.appRules = appRules
    }

    func removeAppRule(_ bundleID: String) {
        appRules.removeValue(forKey: bundleID)
        settings.appRules = appRules
    }
}
