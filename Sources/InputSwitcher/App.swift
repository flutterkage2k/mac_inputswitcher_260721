import SwiftUI
import UserNotifications

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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleIdentifier != nil { // bare 실행 보호
            UNUserNotificationCenter.current().delegate = self
        }
    }

    /// 업데이트 알림 배너 클릭 → 다운로드 페이지 열기
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("update-") {
            NSWorkspace.shared.open(UpdateChecker.releasesPage)
        }
        completionHandler()
    }

    /// 앱 실행 중에도 배너가 보이도록
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
