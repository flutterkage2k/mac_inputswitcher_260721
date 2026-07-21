import SwiftUI

@main
struct InputSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        // 전환이 폴백까지 실패하면 아이콘으로만 조용히 표시 (알림 스팸 없음)
        MenuBarExtra("InputSwitcher",
                     systemImage: state.lastSwitchFailed ? "keyboard.badge.ellipsis" : "keyboard") {
            SettingsView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
