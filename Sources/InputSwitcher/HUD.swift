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
        // 화면 정중앙에 표시
        panel.setFrame(NSRect(x: screen.midX - size.width / 2,
                              y: screen.midY - size.height / 2,
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
        p.hasShadow = false // 시스템 창 그림자가 회색 윤곽선처럼 보이는 것 방지
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
        // 볼륨 OSD 스타일: 어두운 반투명 배경 + 흰 글자 — 어떤 화면 위에서도 잘 읽힘
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(16) // 그림자 잘림 방지 여백
    }
}
