import Carbon
import AppKit

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
            return InputSource(id: id, name: name)
        }
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
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return }
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
}
