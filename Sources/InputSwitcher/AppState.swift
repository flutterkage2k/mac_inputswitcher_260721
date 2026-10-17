import SwiftUI
import Carbon
import UserNotifications

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
    /// 커밋 창이 떠 있는 시간(ms). 설정 화면 슬라이더로 조정, 범위는 Settings.delayRange.
    @Published var commitDelayMS: Double {
        didSet {
            settings.verifyDelayMS = UInt64(commitDelayMS)
            switcher.verifyDelayMS = settings.verifyDelayMS
        }
    }

    /// 매핑은 있는데 시스템에서 제거된 소스 ID들 (설정 화면에 "소스 없음"으로 표시)
    var orphanedMappings: [String] {
        mappings.keys.filter { id in !sources.contains(where: { $0.id == id }) }.sorted()
    }

    @Published var appRules: [String: AppRule] = [:]
    @Published var availableUpdate: UpdateInfo?

    private let api = SystemInputSourceAPI()
    private let settings = Settings()
    private let hotkeys = HotkeyManager()
    private lazy var switcher: Switcher = {
        let s = Switcher(api: api, verifyDelayMS: settings.verifyDelayMS)
        s.focusCommitEnabled = settings.focusCommitEnabled
        return s
    }()
    private var switchTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    /// 이 시각 전까지 규칙 발동 중지. 커밋 포커스 사이클(규칙 앱→자신→규칙 앱
    /// 재활성화, 수백 ms 내)이 규칙을 재발동해 루프가 되는 것을 막는다.
    // ponytail: 시간 창 방식 — 전환 직후 1초 내 규칙 앱 진입은 자동 전환 안 됨
    private var suppressRulesUntil = Date.distantPast
    // 입력소스 변경 알림 분류용: 우리가 마지막으로 요청한 전환
    private var sourceChangeObserver: NSObjectProtocol?
    private var lastSwitchTarget: String?
    private var lastSwitchAt = Date.distantPast
    private var lastSwitchWasRepress = false
    private var lastLoggedSourceID: String?

    init() {
        showHUD = Settings().showHUD
        commitDelayMS = Double(Settings().verifyDelayMS)
        sources = api.selectableSources()
        mappings = settings.mappings
        appRules = settings.appRules
        currentID = api.currentSourceID()
        // 어떤 설정으로 모은 기록인지 로그 자체에 남긴다 (사후 분석에서 모드 혼동 방지)
        dbg("mode: v\(appVersion) modwait=\(settings.waitForModifierRelease) "
            + "focusCommit=\(settings.focusCommitEnabled) delay=\(settings.verifyDelayMS)ms")
        registerAll()
        observeAppActivations()
        observeSourceChanges()
        scheduleUpdateChecks()
    }

    /// 실행 5초 후 1회 + 24시간마다 자동 업데이트 확인
    private func scheduleUpdateChecks() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await checkForUpdates(notify: true)
        }
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in await self.checkForUpdates(notify: true) }
        }
    }

    /// 반환: 조회 성공 여부. 성공 시 availableUpdate 갱신 (없으면 nil).
    @discardableResult
    func checkForUpdates(notify: Bool) async -> Bool {
        guard let latest = try? await UpdateChecker.latestRelease() else {
            dbg("updateCheck: 조회 실패")
            return false
        }
        if isVersion(appVersion, olderThan: latest.version) {
            availableUpdate = latest
            dbg("updateCheck: 새 버전 \(latest.version)")
            if notify, settings.lastNotifiedVersion != latest.version {
                settings.lastNotifiedVersion = latest.version
                await postUpdateNotification(latest)
            }
        } else {
            availableUpdate = nil
        }
        return true
    }

    /// 새 버전 배너 알림 (버전당 1회). 알림 클릭 처리는 AppDelegate가 담당.
    private func postUpdateNotification(_ info: UpdateInfo) async {
        guard Bundle.main.bundleIdentifier != nil else { return } // bare 실행 보호
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else {
            dbg("updateCheck: 알림 권한 없음")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "InputSwitcher 업데이트"
        content.body = "\(info.version) 버전이 나왔습니다. 클릭하면 다운로드 페이지가 열립니다."
        let request = UNNotificationRequest(
            identifier: "update-\(info.version)", content: content, trigger: nil)
        try? await center.add(request)
    }

    /// macOS의 입력소스 변경 알림을 구독해 모든 변경을 기록한다. 우리 전환뿐 아니라
    /// 시스템 단축키·Caps Lock·메뉴 클릭·다른 앱이 바꾼 것도 잡힌다. 지금까지 로그에는
    /// 우리가 바꾼 것만 남아, 전환 직후 누군가 되돌리는 경우를 볼 수 없었다.
    /// (HangulSync의 감지 방식에서 착안)
    private func observeSourceChanges() {
        sourceChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sourceDidChange() }
        }
    }

    private func sourceDidChange() {
        // 같은 변경에 알림이 두 번 오는 경우가 있어 직전 기록과 같으면 건너뛴다
        guard let id = api.currentSourceID(), id != lastLoggedSourceID else { return }
        lastLoggedSourceID = id
        currentID = id
        let tag = classifyChange(newID: id, lastTarget: lastSwitchTarget,
                                 lastSwitchAt: lastSwitchAt, recovering: lastSwitchWasRepress)
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        dbg("changed: \(id) [\(tag)] app=\(app)")
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
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        guard let rule = appRules[bundleID],
              api.currentSourceID() != rule.sourceID,
              sources.contains(where: { $0.id == rule.sourceID }) else { return }
        guard Date() > suppressRulesUntil else {
            dbg("autoSwitch: \(bundleID) 억제됨 (전환 직후 재활성화)")
            return
        }
        dbg("autoSwitch: \(bundleID) → \(rule.sourceID)")
        performSwitch(to: rule.sourceID, viaHotkey: false)
    }

    private func performSwitch(to sourceID: String, viaHotkey: Bool) {
        // 모든 전환에 앱 이름을 남긴다 — 어느 앱에서 desync가 나는지 사후 분석용
        dbg("app=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        suppressRulesUntil = Date().addingTimeInterval(1.0)
        switchTask?.cancel()
        switchTask = Task { @MainActor in
            if viaHotkey, settings.waitForModifierRelease {
                let held: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                let r = await waitForModifierRelease(
                    isDown: { !NSEvent.modifierFlags.intersection(held).isEmpty })
                if Task.isCancelled { return }
                dbg("modwait: \(r.waitedMS)ms\(r.timedOut ? " (timeout)" : "")")
            }
            lastSwitchTarget = sourceID
            lastSwitchAt = Date()
            lastSwitchWasRepress = (api.currentSourceID() == sourceID)
            suppressRulesUntil = Date().addingTimeInterval(1.0)
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
                self?.performSwitch(to: sourceID, viaHotkey: true)
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
