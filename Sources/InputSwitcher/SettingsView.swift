import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var state: AppState

    private enum UpdateStatus: Equatable {
        case idle, checking, upToDate, failed
    }
    @State private var updateStatus: UpdateStatus = .idle
    @State private var showUpdateAlert = false

    private func checkForUpdate() async {
        updateStatus = .checking
        let ok = await state.checkForUpdates(notify: false)
        if !ok {
            updateStatus = .failed
        } else if state.availableUpdate != nil {
            updateStatus = .idle
            showUpdateAlert = true
        } else {
            updateStatus = .upToDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(state.sources) { source in
                HStack {
                    Text(source.name)
                        .fontWeight(source.id == state.currentID ? .bold : .regular)
                    Spacer()
                    if state.recordingFor == source.id {
                        Text("키 입력...").foregroundStyle(.orange)
                    } else if let combo = state.mappings[source.id] {
                        Text(combo.display).monospaced()
                        if state.failedRegistrations.contains(source.id) {
                            Text("등록 실패").font(.caption).foregroundStyle(.red)
                        }
                        Button("×") { state.setCombo(nil, for: source.id) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("단축키 삭제")
                    }
                    Button(state.recordingFor == source.id ? "취소" : "단축키설정") {
                        state.recordingFor = state.recordingFor == source.id ? nil : source.id
                    }
                }
            }
            // 시스템에서 제거된 소스에 걸린 매핑 (스펙: 에러 처리)
            ForEach(state.orphanedMappings, id: \.self) { orphanID in
                HStack {
                    Text(orphanID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("소스 없음").font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("×") { state.setCombo(nil, for: orphanID) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("단축키 삭제")
                }
            }
            Divider()
            AppRulesSection(state: state)
            Divider()
            Toggle("로그인 시 시작", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            ))
            .toggleStyle(.checkbox)
            Toggle("전환 시 화면에 표시 (HUD)", isOn: $state.showHUD)
                .toggleStyle(.checkbox)
            HStack {
                Button("종료") { NSApp.terminate(nil) }
                Button(updateStatus == .checking ? "확인 중..." : "업데이트 확인") {
                    Task { await checkForUpdate() }
                }
                .disabled(updateStatus == .checking)
                if let info = state.availableUpdate {
                    // 수동/자동 어느 경로로 발견됐든 항상 표시
                    Button("업데이트가 있습니다") { NSWorkspace.shared.open(info.url) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.72, green: 0.08, blue: 0.08))
                } else if updateStatus == .upToDate {
                    Text("최신 버전입니다").font(.caption).foregroundStyle(.green)
                } else if updateStatus == .failed {
                    Text("확인 실패").font(.caption).foregroundStyle(.red)
                }
                Spacer()
            }
            HStack {
                Spacer()
                Text("v\(appVersion) · 2026.07.26 · @kage2k")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(KeyRecorder(state: state))
        .onAppear { state.refreshCurrent() }
        .alert("새로운 버전이 있습니다", isPresented: $showUpdateAlert) {
            Button("다운로드") {
                if let info = state.availableUpdate {
                    NSWorkspace.shared.open(info.url)
                }
            }
            Button("나중에", role: .cancel) {}
        } message: {
            if let info = state.availableUpdate {
                Text("현재 v\(appVersion) → \(info.version)\nReleases 페이지에서 내려받아 교체하세요.")
            }
        }
    }
}

/// 앱별 자동 전환: 규칙 목록 + 실행 중인 앱/입력소스 피커로 규칙 추가.
private struct AppRulesSection: View {
    @ObservedObject var state: AppState
    @State private var newAppBundleID = ""
    @State private var newSourceID = ""

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bid = app.bundleIdentifier else { return nil }
                return (bid, app.localizedName ?? bid)
            }
            .sorted { $0.name < $1.name }
    }

    private var rulesList: some View {
        ForEach(state.appRules.sorted(by: { $0.value.appName < $1.value.appName }),
                id: \.key) { bundleID, rule in
            HStack {
                Text(rule.appName)
                Spacer()
                Text(state.sources.first { $0.id == rule.sourceID }?.name ?? rule.sourceID)
                    .foregroundStyle(.secondary)
                Button("×") { state.removeAppRule(bundleID) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("규칙 삭제")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("앱별 자동 전환").font(.caption).foregroundStyle(.secondary)
            // 규칙이 많아져도 팝오버가 무한정 길어지지 않게 6개 초과 시 스크롤
            if state.appRules.count > 6 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) { rulesList }
                }
                .frame(height: 150)
            } else {
                rulesList
            }
            HStack {
                Picker("", selection: $newAppBundleID) {
                    Text("앱 선택").tag("")
                    ForEach(runningApps, id: \.bundleID) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                .labelsHidden()
                Picker("", selection: $newSourceID) {
                    Text("입력소스").tag("")
                    ForEach(state.sources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .labelsHidden()
                Button("추가") {
                    guard let app = runningApps.first(where: { $0.bundleID == newAppBundleID }),
                          !newSourceID.isEmpty else { return }
                    state.addAppRule(bundleID: app.bundleID, appName: app.name, sourceID: newSourceID)
                    newAppBundleID = ""
                    newSourceID = ""
                }
                .disabled(newAppBundleID.isEmpty || newSourceID.isEmpty)
            }
        }
    }
}

/// recordingFor가 설정된 동안 로컬 keyDown을 가로채 단축키로 저장한다.
struct KeyRecorder: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let state = self.state
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let target = state.recordingFor else { return event }
            let mods = carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil } // 수식키 없는 단축키 금지
            let combo = KeyCombo(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: mods,
                display: displayString(for: event))
            state.setCombo(combo, for: target)
            state.recordingFor = nil
            return nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    final class Coordinator {
        var monitor: Any?
    }
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var mods: UInt32 = 0
    if flags.contains(.command) { mods |= UInt32(cmdKey) }
    if flags.contains(.shift) { mods |= UInt32(shiftKey) }
    if flags.contains(.option) { mods |= UInt32(optionKey) }
    if flags.contains(.control) { mods |= UInt32(controlKey) }
    return mods
}

func displayString(for event: NSEvent) -> String {
    var s = ""
    let f = event.modifierFlags
    if f.contains(.control) { s += "⌃" }
    if f.contains(.option) { s += "⌥" }
    if f.contains(.shift) { s += "⇧" }
    if f.contains(.command) { s += "⌘" }
    s += (event.charactersIgnoringModifiers ?? "?").uppercased()
    return s
}
