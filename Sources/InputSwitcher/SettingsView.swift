import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var state: AppState

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
                    }
                    Button(state.recordingFor == source.id ? "취소" : "녹화") {
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
                }
            }
            Divider()
            Toggle("로그인 시 시작", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            ))
            .toggleStyle(.checkbox)
            Button("종료") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
        .background(KeyRecorder(state: state))
        .onAppear { state.refreshCurrent() }
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
