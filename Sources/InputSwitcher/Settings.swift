import Foundation

struct AppRule: Codable, Equatable {
    var appName: String   // 표시용 (앱이 실행 중이 아닐 때도 목록에 보여야 함)
    var sourceID: String
}

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

    /// 앱별 자동 전환 규칙 (키: bundleID)
    var appRules: [String: AppRule] {
        get {
            guard let data = defaults.data(forKey: "appRules"),
                  let decoded = try? JSONDecoder().decode([String: AppRule].self, from: data)
            else { return [:] }
            return decoded
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "appRules") }
    }

    /// 배너로 알린 마지막 버전 (버전당 1회만 알리기 위함)
    var lastNotifiedVersion: String {
        get { defaults.string(forKey: "lastNotifiedVersion") ?? "" }
        set { defaults.set(newValue, forKey: "lastNotifiedVersion") }
    }

    /// 단축키 전환 시 보조키에서 손을 뗄 때까지 기다릴지.
    /// 실측 결과 대기가 200~340ms, 16번 중 3번은 1초 상한까지 가서 "눌러도 안 바뀐다"로
    /// 체감됐다. 기본 꺼짐.
    var waitForModifierRelease: Bool {
        get { defaults.object(forKey: "waitForModifierRelease") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "waitForModifierRelease") }
    }

    /// 포커스 커밋(보이지 않는 창이 0.15초 key를 가져가는 방식) 사용 여부.
    /// 진입 실패율이 이 방식일 때 20~23%로 가장 낮았다(왕복 방식은 28~46%).
    /// 대가로 연속 전환 시 글자를 가끔 가로챈다(dev4 1.8일간 11회). 기본 켜짐.
    var focusCommitEnabled: Bool {
        get { defaults.object(forKey: "focusCommitEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "focusCommitEnabled") }
    }

    var showHUD: Bool {
        get { defaults.object(forKey: "showHUD") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showHUD") }
    }

    var verifyDelayMS: UInt64 {
        get {
            let v = defaults.integer(forKey: delayKey)
            // 기본 150ms. macism 작성자 실측으로 macOS 26(Tahoe)에서 안정적인 최솟값.
            // dev15~16의 80ms는 이 아래였다.
            return v > 0 ? UInt64(v) : 150
        }
        set { defaults.set(Int(newValue), forKey: delayKey) }
    }
}
