import Carbon
import AppKit

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
            return InputSource(id: id, name: name, isCJKV: isCJKV)
        }
    }

    /// CJKV 커밋: 작은 창을 띄워 잠깐 key/active가 됐다가 숨어서 이전 앱으로 포커스를
    /// 돌려준다. 이 포커스 사이클이 있어야 백그라운드에서의 CJKV 전환이 실제 적용된다.
    func commitSelection(waitMS: UInt64) async {
        guard waitMS > 0 else { return }
        // Spotlight 같은 일시 패널은 포커스를 잃는 순간 닫히므로 커밋을 생략한다.
        // 패널 자체가 key인 상황에서는 plain select만으로 전환이 적용된다.
        guard !transientPanelIsOpen() else { return }
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let window = NSWindow(
            contentRect: NSRect(x: screen.maxX - 11, y: screen.minY + 8, width: 3, height: 3),
            styleMask: [.titled], // titled가 아니면 key window가 될 수 없음
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: waitMS * 1_000_000)
        window.orderOut(nil)
        NSApp.hide(nil) // accessory 앱이 숨으면 이전 앱으로 포커스가 복귀한다
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
        let trusted: Bool
        if transientPanelIsOpen() {
            trusted = AXIsProcessTrusted() // 권한 프롬프트가 패널을 닫으므로 금지
        } else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(opts)
        }
        guard trusted else { return }
        let (keyCode, flags) = systemSwitchShortcut()
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let ev = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            ev?.flags = flags
            ev?.post(tap: .cghidEventTap)
        }
    }

    /// com.apple.symbolichotkeys의 61번 항목을 읽는다. 실패 시 기본값 ⌃⌥Space.
    private func systemSwitchShortcut() -> (CGKeyCode, CGEventFlags) {
        let fallback: (CGKeyCode, CGEventFlags) = (49, [.maskControl, .maskAlternate])
        guard let prefs = CFPreferencesCopyAppValue(
                  "AppleSymbolicHotKeys" as CFString,
                  "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = prefs["61"] as? [String: Any],
              (entry["enabled"] as? Bool ?? true),
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int],
              params.count >= 3 else { return fallback }
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
    private func transientPanelIsOpen() -> Bool {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.activationPolicy != .regular {
            return true
        }
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { ($0[kCGWindowOwnerName as String] as? String) == "Spotlight" }
    }
}
