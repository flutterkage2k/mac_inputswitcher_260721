# InputSwitcher 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 입력소스별 전용 전역 단축키로 즉시·안정적으로 전환하는 macOS 메뉴바 앱 (kawa 대체).

**Architecture:** SwiftPM executable 하나. 3개 유닛 — HotkeyManager(Carbon `RegisterEventHotKey`), InputSourceSwitcher(TIS API + 검증-재시도-폴백), SwiftUI `MenuBarExtra` UI. 전환 로직은 `InputSourceAPI` 프로토콜로 추상화해 목 주입 단위 테스트.

**Tech Stack:** Swift (tools 5.9, 언어모드 5), SwiftUI MenuBarExtra, Carbon HIToolbox, ServiceManagement. 외부 의존성 0.

## Global Constraints

- 대상 OS: macOS 14+ (`platforms: [.macOS(.v14)]`)
- 외부 패키지 의존성 금지
- 접근성 권한: 기본 경로(TIS select+verify)는 무권한. CGEvent 폴백 발동 시에만 요청
- UI 문구는 한국어
- 번들 ID: `dev.heesung.InputSwitcher`
- 검증 대기 기본값: 30ms, UserDefaults `verifyDelayMS`로 조정 가능 (스펙의 "조정 노브")
- 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: SwiftPM 골격 + 최소 메뉴바 앱

**Files:**
- Create: `Package.swift`
- Create: `Sources/InputSwitcher/App.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: 없음
- Produces: `InputSwitcherApp` (@main), `AppDelegate`. Task 6이 `SettingsView` 자리에 실제 UI를 넣는다.

- [ ] **Step 1: Package.swift 작성**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputSwitcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "InputSwitcher", path: "Sources/InputSwitcher"),
        .testTarget(
            name: "InputSwitcherTests",
            dependencies: ["InputSwitcher"],
            path: "Tests/InputSwitcherTests"
        ),
    ]
)
```

- [ ] **Step 2: .gitignore 작성**

```
.build/
build/
.DS_Store
```

- [ ] **Step 3: App.swift 작성**

```swift
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
```

- [ ] **Step 4: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: 수동 확인**

Run: `swift run` (백그라운드로). 메뉴바에 키보드 아이콘이 뜨고, 클릭 시 "InputSwitcher 준비됨"과 종료 버튼이 보이는지 확인 후 종료.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources .gitignore
git commit -m "feat: SwiftPM 골격 + 최소 메뉴바 앱"
```

---

### Task 2: 전환-검증-재시도-폴백 로직 (TDD)

**Files:**
- Create: `Sources/InputSwitcher/Switcher.swift`
- Test: `Tests/InputSwitcherTests/SwitcherTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces (Task 3, 6이 사용):
  - `struct InputSource: Identifiable, Equatable { let id: String; let name: String }`
  - `protocol InputSourceAPI { func currentSourceID() -> String?; @discardableResult func select(_ id: String) -> Bool; func selectableSources() -> [InputSource]; func postSystemSwitchShortcut() }`
  - `final class Switcher { init(api: InputSourceAPI, verifyDelayMS: UInt64); func switchTo(_ id: String) async -> Bool }`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import InputSwitcher

final class MockAPI: InputSourceAPI {
    var current: String? = "en"
    /// select 호출이 이 횟수를 넘어야 실제 반영됨 (0 = 즉시 성공, 99 = select로는 불가)
    var selectSucceedsAfter = 0
    private var selectCalls = 0
    var sources = [InputSource(id: "en", name: "ABC"), InputSource(id: "ko", name: "한글")]
    var cycleOrder = ["en", "ko"]
    private var cycleIndex = 0

    func currentSourceID() -> String? { current }
    @discardableResult func select(_ id: String) -> Bool {
        selectCalls += 1
        if selectCalls > selectSucceedsAfter { current = id }
        return true
    }
    func selectableSources() -> [InputSource] { sources }
    func postSystemSwitchShortcut() {
        cycleIndex = (cycleIndex + 1) % cycleOrder.count
        current = cycleOrder[cycleIndex]
    }
}

final class SwitcherTests: XCTestCase {
    private func makeSwitcher(_ api: MockAPI) -> Switcher {
        Switcher(api: api, verifyDelayMS: 0)
    }

    func test_직접_전환_성공() async {
        let api = MockAPI()
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.current, "ko")
    }

    func test_재시도로_성공() async {
        let api = MockAPI()
        api.selectSucceedsAfter = 1 // 첫 select는 무시됨 (CJK 버그 시뮬레이션)
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
    }

    func test_시스템단축키_순환_폴백으로_성공() async {
        let api = MockAPI()
        api.selectSucceedsAfter = 99 // select로는 절대 안 됨
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertTrue(ok)
        XCTAssertEqual(api.current, "ko")
    }

    func test_폴백까지_실패하면_false() async {
        let api = MockAPI()
        api.selectSucceedsAfter = 99
        api.cycleOrder = ["en", "fr"] // 순환 목록에 목표가 없음
        let ok = await makeSwitcher(api).switchTo("ko")
        XCTAssertFalse(ok)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `swift test`
Expected: 컴파일 실패 — `cannot find type 'InputSourceAPI'`

- [ ] **Step 3: Switcher.swift 구현**

```swift
import Foundation

struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
}

protocol InputSourceAPI {
    func currentSourceID() -> String?
    @discardableResult func select(_ id: String) -> Bool
    func selectableSources() -> [InputSource]
    func postSystemSwitchShortcut()
}

/// CJK 버그 우회의 핵심: select → 검증 → 재시도 → 시스템 전환 단축키 순환 폴백.
final class Switcher {
    private let api: InputSourceAPI
    var verifyDelayMS: UInt64

    init(api: InputSourceAPI, verifyDelayMS: UInt64 = 30) {
        self.api = api
        self.verifyDelayMS = verifyDelayMS
    }

    func switchTo(_ id: String) async -> Bool {
        for _ in 0..<2 {
            api.select(id)
            try? await Task.sleep(nanoseconds: verifyDelayMS * 1_000_000)
            if api.currentSourceID() == id { return true }
        }
        // 폴백: 시스템 "다음 소스 선택" 단축키로 순환. 소스 개수만큼만 시도.
        for _ in 0..<max(1, api.selectableSources().count) {
            api.postSystemSwitchShortcut()
            try? await Task.sleep(nanoseconds: verifyDelayMS * 1_000_000)
            if api.currentSourceID() == id { return true }
        }
        return false
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test`
Expected: `Test Suite 'SwitcherTests' passed` — 4개 테스트 모두 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/InputSwitcher/Switcher.swift Tests
git commit -m "feat: 전환-검증-재시도-폴백 로직 (TDD)"
```

---

### Task 3: 실제 TIS/CGEvent 구현 (SystemInputSourceAPI)

**Files:**
- Create: `Sources/InputSwitcher/SystemInputSourceAPI.swift`
- Test: `Tests/InputSwitcherTests/SystemAPISmokeTests.swift`

**Interfaces:**
- Consumes: Task 2의 `InputSourceAPI`, `InputSource`
- Produces (Task 6이 사용): `final class SystemInputSourceAPI: InputSourceAPI` (인자 없는 `init()`)

- [ ] **Step 1: 실패하는 스모크 테스트 작성**

실제 macOS API를 치는 통합 스모크 테스트 (호스트 Mac에서 안전하게 실행 가능 — 조회만 함):

```swift
import XCTest
@testable import InputSwitcher

final class SystemAPISmokeTests: XCTestCase {
    func test_실제_소스목록과_현재소스_조회() {
        let api = SystemInputSourceAPI()
        XCTAssertFalse(api.selectableSources().isEmpty, "선택 가능한 입력소스가 최소 1개는 있어야 함")
        XCTAssertNotNil(api.currentSourceID())
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `swift test --filter SystemAPISmokeTests`
Expected: 컴파일 실패 — `cannot find 'SystemInputSourceAPI'`

- [ ] **Step 3: SystemInputSourceAPI.swift 구현**

```swift
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
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test`
Expected: 전체 PASS (SwitcherTests 4개 + 스모크 1개)

- [ ] **Step 5: Commit**

```bash
git add Sources/InputSwitcher/SystemInputSourceAPI.swift Tests
git commit -m "feat: TIS/CGEvent 기반 실제 입력소스 API"
```

---

### Task 4: 설정 저장 (TDD)

**Files:**
- Create: `Sources/InputSwitcher/Settings.swift`
- Test: `Tests/InputSwitcherTests/SettingsTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces (Task 5, 6이 사용):
  - `struct KeyCombo: Codable, Equatable { var keyCode: UInt32; var carbonModifiers: UInt32; var display: String }`
  - `final class Settings { init(defaults: UserDefaults = .standard); var mappings: [String: KeyCombo] { get set }; var verifyDelayMS: UInt64 { get set } }`
  - `mappings`의 키는 입력소스 ID (예: `"com.apple.keylayout.ABC"`)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import InputSwitcher

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")
    }

    func test_매핑_저장_후_다시_읽기() {
        let s = Settings(defaults: defaults)
        let combo = KeyCombo(keyCode: 40, carbonModifiers: 768, display: "⇧⌘K")
        s.mappings = ["com.apple.inputmethod.Korean.2SetKorean": combo]

        let reloaded = Settings(defaults: defaults)
        XCTAssertEqual(reloaded.mappings["com.apple.inputmethod.Korean.2SetKorean"], combo)
    }

    func test_빈_상태는_빈_매핑() {
        XCTAssertTrue(Settings(defaults: defaults).mappings.isEmpty)
    }

    func test_verifyDelay_기본값_30() {
        XCTAssertEqual(Settings(defaults: defaults).verifyDelayMS, 30)
    }

    func test_verifyDelay_저장() {
        let s = Settings(defaults: defaults)
        s.verifyDelayMS = 100
        XCTAssertEqual(Settings(defaults: defaults).verifyDelayMS, 100)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `swift test --filter SettingsTests`
Expected: 컴파일 실패 — `cannot find 'Settings'`

- [ ] **Step 3: Settings.swift 구현**

```swift
import Foundation

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String
}

final class Settings {
    private let defaults: UserDefaults
    private let mappingsKey = "mappings"
    private let delayKey = "verifyDelayMS"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mappings: [String: KeyCombo] {
        get {
            guard let data = defaults.data(forKey: mappingsKey),
                  let decoded = try? JSONDecoder().decode([String: KeyCombo].self, from: data)
            else { return [:] }
            return decoded
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: mappingsKey) }
    }

    var verifyDelayMS: UInt64 {
        get {
            let v = defaults.integer(forKey: delayKey)
            return v > 0 ? UInt64(v) : 30
        }
        set { defaults.set(Int(newValue), forKey: delayKey) }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test`
Expected: 전체 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/InputSwitcher/Settings.swift Tests
git commit -m "feat: 단축키 매핑/딜레이 설정 저장 (TDD)"
```

---

### Task 5: HotkeyManager (Carbon 전역 단축키)

**Files:**
- Create: `Sources/InputSwitcher/HotkeyManager.swift`

**Interfaces:**
- Consumes: Task 4의 `KeyCombo`
- Produces (Task 6이 사용): `final class HotkeyManager { init(); @discardableResult func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool; func unregisterAll() }`
  - `register`가 `false`를 반환하면 등록 실패(다른 앱과 충돌)

- [ ] **Step 1: HotkeyManager.swift 구현**

Carbon C 콜백 경계라 단위 테스트 불가 — Task 6에서 수동 검증한다.

```swift
import Carbon.HIToolbox

final class HotkeyManager {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    fileprivate var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            manager.actions[hkID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        var ref: EventHotKeyRef?
        let id = nextID
        nextID += 1
        let hkID = EventHotKeyID(signature: OSType(0x494E_5357), id: id) // 'INSW'
        guard RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hkID,
                                  GetEventDispatcherTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs[id] = ref
        actions[id] = action
        return true
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }
}
```

- [ ] **Step 2: 빌드/기존 테스트 확인**

Run: `swift build && swift test`
Expected: 빌드 성공, 기존 테스트 전체 PASS

- [ ] **Step 3: Commit**

```bash
git add Sources/InputSwitcher/HotkeyManager.swift
git commit -m "feat: Carbon RegisterEventHotKey 기반 전역 단축키 관리자"
```

---

### Task 6: UI + 전체 연결 (AppState, 단축키 레코더)

**Files:**
- Create: `Sources/InputSwitcher/AppState.swift`
- Create: `Sources/InputSwitcher/SettingsView.swift`
- Modify: `Sources/InputSwitcher/App.swift` (MenuBarExtra 본문을 SettingsView로 교체)

**Interfaces:**
- Consumes: Task 2 `Switcher`/`InputSource`, Task 3 `SystemInputSourceAPI`, Task 4 `Settings`/`KeyCombo`, Task 5 `HotkeyManager`
- Produces: `AppState` (@MainActor ObservableObject), `SettingsView(state:)`

- [ ] **Step 1: AppState.swift 구현**

```swift
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var sources: [InputSource] = []
    @Published var mappings: [String: KeyCombo] = [:]
    @Published var currentID: String?
    @Published var recordingFor: String?          // 녹화 중인 소스 ID
    @Published var failedRegistrations: Set<String> = []
    @Published var lastSwitchFailed = false       // 폴백까지 실패 시 메뉴바 아이콘 표시용

    /// 매핑은 있는데 시스템에서 제거된 소스 ID들 (설정 화면에 "소스 없음"으로 표시)
    var orphanedMappings: [String] {
        mappings.keys.filter { id in !sources.contains(where: { $0.id == id }) }.sorted()
    }

    private let api = SystemInputSourceAPI()
    private let settings = Settings()
    private let hotkeys = HotkeyManager()
    private lazy var switcher = Switcher(api: api, verifyDelayMS: settings.verifyDelayMS)

    init() {
        sources = api.selectableSources()
        mappings = settings.mappings
        currentID = api.currentSourceID()
        registerAll()
    }

    func registerAll() {
        hotkeys.unregisterAll()
        failedRegistrations = []
        for (sourceID, combo) in mappings {
            // 시스템에서 제거된 소스의 매핑은 무시 (스펙: 에러 처리)
            guard sources.contains(where: { $0.id == sourceID }) else { continue }
            let ok = hotkeys.register(combo) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.lastSwitchFailed = !(await self.switcher.switchTo(sourceID))
                    self.currentID = self.api.currentSourceID()
                }
            }
            if !ok { failedRegistrations.insert(sourceID) }
        }
    }

    func setCombo(_ combo: KeyCombo?, for sourceID: String) {
        if let combo {
            mappings[sourceID] = combo
        } else {
            mappings.removeValue(forKey: sourceID)
        }
        settings.mappings = mappings
        registerAll()
    }

    func refreshCurrent() {
        currentID = api.currentSourceID()
    }
}
```

- [ ] **Step 2: SettingsView.swift 구현 (단축키 레코더 포함)**

```swift
import SwiftUI
import Carbon.HIToolbox

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
```

- [ ] **Step 3: App.swift 본문 교체**

`MenuBarExtra` 내부를 다음으로 교체 (기존 VStack 삭제):

```swift
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
```

- [ ] **Step 4: 빌드/테스트 확인**

Run: `swift build && swift test`
Expected: 빌드 성공, 전체 테스트 PASS

- [ ] **Step 5: 수동 통합 검증 (스펙의 수동 시나리오)**

Run: `swift run` (백그라운드). 확인 항목:
1. 메뉴에 실제 입력소스 목록이 뜬다 (한글/ABC 등)
2. 한글에 ⌘⇧K, ABC에 ⌘⇧E 녹화
3. 다른 앱(메모 등)에서 단축키로 전환 → **전환 직후 즉시 타이핑**해서 씹힘 없는지 확인
4. 한↔영 빠른 연속 전환 반복
5. 앱 재시작 후 매핑이 유지되는지 확인

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "feat: 메뉴바 UI + 단축키 레코더 + 전체 연결"
```

---

### Task 7: .app 번들링 + 로그인 시 시작

**Files:**
- Create: `scripts/bundle.sh`
- Modify: `Sources/InputSwitcher/SettingsView.swift` (로그인 시작 토글 추가)
- Create: `README.md`

**Interfaces:**
- Consumes: Task 6의 `SettingsView`
- Produces: `build/InputSwitcher.app` (로컬 서명), `scripts/bundle.sh`

- [ ] **Step 1: bundle.sh 작성**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/InputSwitcher.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/InputSwitcher "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.heesung.InputSwitcher</string>
  <key>CFBundleName</key><string>InputSwitcher</string>
  <key>CFBundleExecutable</key><string>InputSwitcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "완료 → $APP  (설치: cp -R $APP /Applications/)"
```

Run: `chmod +x scripts/bundle.sh`

- [ ] **Step 2: 로그인 시작 토글 추가**

`SettingsView.swift`의 `Divider()`와 `Button("종료")` 사이에 추가:

```swift
Toggle("로그인 시 시작", isOn: Binding(
    get: { SMAppService.mainApp.status == .enabled },
    set: { on in
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
))
.toggleStyle(.checkbox)
```

파일 상단에 `import ServiceManagement` 추가.
주의: SMAppService는 .app 번들로 실행될 때만 동작한다. `swift run`(bare 실행파일)에서는 토글이 실패해도 정상 — README에 명시.

- [ ] **Step 3: 번들 생성 및 검증**

Run: `./scripts/bundle.sh && open build/InputSwitcher.app`
Expected: 스크립트 성공, 메뉴바에 앱 등장. Task 6의 수동 시나리오 중 2~3번 재확인 + "로그인 시 시작" 토글 동작 확인 (번들 실행 시).

- [ ] **Step 4: README.md 작성**

```markdown
# InputSwitcher

입력소스별 전용 단축키로 즉시 전환하는 macOS 메뉴바 앱. ([kawa](https://github.com/hatashiro/kawa)의 현대적 재구현)

## 설치

```bash
./scripts/bundle.sh
cp -R build/InputSwitcher.app /Applications/
open /Applications/InputSwitcher.app
```

## 사용

메뉴바 키보드 아이콘 → 각 입력소스 옆 "녹화" → 원하는 단축키 입력 (수식키 필수).

## 참고

- macOS 14+ 대상. macOS의 CJK 입력소스 전환 버그(TISSelectInputSource)는
  select→검증→재시도→시스템 단축키 폴백으로 우회한다.
- 기본 경로는 권한 불필요. 폴백(CGEvent)이 발동될 때만 접근성 권한을 요청한다.
- 전환 검증 대기시간(기본 30ms) 조정:
  `defaults write dev.heesung.InputSwitcher verifyDelayMS -int 80`
- "로그인 시 시작" 토글은 .app 번들로 실행할 때만 동작한다 (`swift run`에서는 무시됨).
```

- [ ] **Step 5: Commit**

```bash
git add scripts README.md Sources
git commit -m "feat: .app 번들 스크립트 + 로그인 시 시작 + README"
```
