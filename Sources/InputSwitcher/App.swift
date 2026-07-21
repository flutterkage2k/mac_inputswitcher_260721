import SwiftUI

@main
struct InputSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("InputSwitcher", systemImage: "keyboard") {
            VStack(alignment: .leading, spacing: 8) {
                Text("InputSwitcher 준비됨")
                Divider()
                Button("종료") { NSApp.terminate(nil) }
            }
            .padding(12)
            .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // bare SPM 실행파일이 Dock에 뜨지 않도록
        NSApp.setActivationPolicy(.accessory)
    }
}
