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
            // 기본 150ms: macOS 26 (Tahoe)에서 CJKV 포커스-커밋이 안정되는 최소값 (macism 동일)
            return v > 0 ? UInt64(v) : 150
        }
        set { defaults.set(Int(newValue), forKey: delayKey) }
    }
}
