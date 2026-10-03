import Carbon
import AppKit

/// 커밋용 임시 패널. 커밋 중 들어온 키 입력을 감지해 알린다.
private final class CommitPanel: NSPanel {
    var onKeyDown: (() -> Void)?
    override func keyDown(with event: NSEvent) { onKeyDown?() }
    override func insertText(_ insertString: Any) { onKeyDown?() }
}

@MainActor
final class SystemInputSourceAPI: InputSourceAPI {
    func selectableSources() -> [InputSource] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { src in
            guard boolProp(src, kTISPropertyInputSourceIsSelectCapable),
                  let id = stringProp(src, kTISPropertyInputSourceID),
                  let name = stringProp(src, kTISPropertyLocalizedName) else { return nil }
            let lang = languages(src).first ?? ""
            let isCJKV = lang == "ko" || lang == "ja" || lang == "vi" || lang.hasPrefix("zh")
            return InputSource(id: id, name: name, isCJKV: isCJKV, isKorean: lang == "ko")
        }
    }

    /// CJKV 커밋: 작은 창을 띄워 잠깐 key/active가 됐다가 숨어서 이전 앱으로 포커스를
    /// 돌려준다. 이 포커스 사이클이 있어야 백그라운드에서의 CJKV 전환이 실제 적용된다.
    @discardableResult
    func commitSelection(waitMS: UInt64) async -> Bool {
        guard waitMS > 0 else { return true } // 0 = 커밋 기능 자체를 끈 것 → 생략 아님
        // Spotlight 같은 일시 패널은 포커스를 잃는 순간 닫히므로 커밋을 생략한다.
        // 패널 자체가 key인 상황에서는 plain select만으로 전환이 적용된다.
        guard !transientPanelIsOpen() else {
            dbg("commit: skip (panel open)")
            return false
        }
        dbg("commit: key-only 커밋 실행 (\(waitMS)ms)")
        // nonactivating 패널(Spotlight과 같은 방식): 사용자 앱을 비활성화하지 않고
        // key 상태만 잠깐 가져와 IME 세션을 재초기화시킨다. 앱 활성 상태가 유지되므로
        // 인라인 이름변경 같은 포커스 민감 UI가 닫히지 않는다.
        // 화면 밖에 둔다. 화면 안에 있으면 IME 변환 후보창이 이 창 위치에 딸려온다.
        let panel = CommitPanel(
            contentRect: NSRect(x: -300, y: -300, width: 3, height: 3),
            styleMask: [.titled, .nonactivatingPanel], // titled가 아니면 key가 될 수 없음
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // 커밋 창(150ms) 동안 패널이 key라서 타이핑을 삼킬 수 있다.
        // 키가 들어오면 즉시 물러나 삼킴 구간을 최소화하고 로그로 빈도를 계측한다.
        panel.onKeyDown = { [weak panel] in
            dbg("commit: 키 입력 감지 → 커밋 조기 종료 (입력 삼킴 가능성)")
            panel?.orderOut(nil)
        }
        panel.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: waitMS * 1_000_000)
        panel.orderOut(nil) // key는 이전 key window로 자동 복귀
        return true
    }

    /// 우리 앱을 잠깐 활성화했다가 원래 앱으로 돌려준다.
    /// 커밋 창(key만 가져오기)과 달리 사용자 앱을 실제로 비활성화시킨다 — 돌아올 때
    /// 입력 세션이 새로 만들어지는 것이 목적이다. 그만큼 파급이 크므로 사용자가
    /// 같은 키를 다시 누른 경우(이미 전환이 안 먹고 있는 상태)에만 쓴다.
    @discardableResult
    func cycleAppFocus(waitMS: UInt64) async -> Bool {
        // 포커스를 잃으면 닫히는 런처 패널이 떠 있으면 하지 않는다
        guard !transientPanelIsOpen() else {
            dbg("appCycle: skip (패널 열림)")
            return false
        }
        guard let previous = NSWorkspace.shared.frontmostApplication,
              previous.bundleIdentifier != Bundle.main.bundleIdentifier else {
            dbg("appCycle: skip (앞 앱 없음 또는 우리 앱)")
            return false
        }
        dbg("appCycle: \(previous.localizedName ?? "?") 떠났다 복귀 (\(waitMS)ms)")
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: waitMS * 1_000_000)
        previous.activate()
        return true
    }

    func currentSourceID() -> String? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProp(src, kTISPropertyInputSourceID)
    }

    @discardableResult
    func select(_ id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let src = list.first else { return false }
        return TISSelectInputSource(src) == noErr
    }

    /// 시스템 "입력 메뉴에서 다음 소스 선택" 단축키(symbolic hotkey 61)를 에뮬레이션.
    /// CGEvent 포스트는 접근성 권한 필요 — 폴백 발동 시에만 요청 프롬프트가 뜬다.
    func postSystemSwitchShortcut() {
        // 시스템 단축키가 비활성화면 포스트해도 시스템이 처리하지 않고
        // 포커스된 앱에 날키로 꽂히므로 아무것도 하지 않는다.
        guard let (keyCode, flags) = systemSwitchShortcut() else {
            dbg("fallback: hotkey61 비활성 → 포스트 생략")
            return
        }
        let trusted: Bool
        if transientPanelIsOpen() {
            trusted = AXIsProcessTrusted() // 권한 프롬프트가 패널을 닫으므로 금지
        } else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(opts)
        }
        dbg("fallback: trusted=\(trusted) key=\(keyCode)")
        guard trusted else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let ev = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            ev?.flags = flags
            ev?.post(tap: .cghidEventTap)
        }
    }

    /// com.apple.symbolichotkeys의 61번 항목을 읽는다.
    /// 항목이 없으면 macOS 기본값 ⌃⌥Space, 명시적으로 비활성화면 nil (포스트 금지).
    private func systemSwitchShortcut() -> (CGKeyCode, CGEventFlags)? {
        let defaultShortcut: (CGKeyCode, CGEventFlags) = (49, [.maskControl, .maskAlternate])
        guard let prefs = CFPreferencesCopyAppValue(
                  "AppleSymbolicHotKeys" as CFString,
                  "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = prefs["61"] as? [String: Any] else { return defaultShortcut }
        guard (entry["enabled"] as? Bool ?? true) else { return nil }
        guard let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int],
              params.count >= 3 else { return defaultShortcut }
        return (CGKeyCode(params[1]), CGEventFlags(rawValue: UInt64(params[2])))
    }

    private func boolProp(_ src: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }

    private func stringProp(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func languages(_ src: TISInputSource) -> [String] {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String] ?? []
    }

    /// 포커스를 잃으면 닫히는 일시 패널이 떠 있는가.
    /// - Raycast/Alfred류 런처: accessory 앱이 frontmost가 된 상태로 감지.
    /// - Spotlight: activate 없이 key만 가지므로 소유 on-screen 창 존재로 감지
    ///   (닫혀 있으면 0개임을 실측 확인).
    /// Spotlight/Raycast류는 자체 단축키로 열면 앱 활성화 없이 key만 가져가므로
    /// frontmost로는 감지할 수 없다. 이들은 닫혀 있으면 on-screen 창이 0개라는
    /// 실측 사실을 이용해 "소유 창 존재 = 패널 열림"으로 감지한다.
    // ponytail: 이름 목록 방식. 다른 런처가 필요해지면 이름 추가.
    private static let panelOwners: Set<String> = ["Spotlight", "Raycast", "Alfred"]

    private func transientPanelIsOpen() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.activationPolicy != .regular {
            dbg("panel?: yes — frontmost=\(front.localizedName ?? "?") policy=\(front.activationPolicy.rawValue)")
            return true
        }
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let hit = list.first { w in
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  Self.panelOwners.contains(owner) else { return false }
            // 설정 창 같은 일반(layer 0) 창은 제외 — 패널은 elevated layer에 뜬다 (Raycast=8)
            return owner == "Spotlight" || (w[kCGWindowLayer as String] as? Int ?? 0) > 0
        }
        let owner = hit?[kCGWindowOwnerName as String] as? String
        dbg("panel?: \(owner.map { "yes(\($0))" } ?? "no") — frontmost=\(front?.localizedName ?? "?") policy=\(front?.activationPolicy.rawValue ?? -1)")
        return hit != nil
    }
}
