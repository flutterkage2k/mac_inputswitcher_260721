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

    var showHUD: Bool {
        get { defaults.object(forKey: "showHUD") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showHUD") }
    }

    var verifyDelayMS: UInt64 {
        get {
            let v = defaults.integer(forKey: delayKey)
            // 기본 150ms: macOS 26 (Tahoe)에서 CJKV 포커스-커밋이 안정되는 최소값 (macism 동일)
            return v > 0 ? UInt64(v) : 150
        }
        set { defaults.set(Int(newValue), forKey: delayKey) }
    }
}
