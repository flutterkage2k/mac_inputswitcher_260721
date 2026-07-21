import SwiftUI

/// 전환 성공 시 화면에 잠깐 뜨는 입력소스 이름 표시 (isHUD 컨셉의 재구현).
/// nonactivating + ignoresMouseEvents — 포커스와 클릭을 절대 건드리지 않는다.
@MainActor
final class HUD {
    static let shared = HUD()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        hideTask?.cancel()
        let content = NSHostingView(rootView: HUDView(text: text))
        let size = content.fittingSize
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = content
        let screen = NSScreen.main?.visibleFrame ?? .zero
        // macOS 볼륨 OSD처럼 중앙 하단부에 표시
        panel.setFrame(NSRect(x: screen.midX - size.width / 2,
                              y: screen.minY + screen.height * 0.16,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let panel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            } completionHandler: {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.isReleasedWhenClosed = false
        return p
    }
}

private struct HUDView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
