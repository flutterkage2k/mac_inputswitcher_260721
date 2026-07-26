import Foundation

/// "v0.2.0" / "0.10.1" 형식 비교. lhs가 rhs보다 오래된 버전이면 true.
func isVersion(_ lhs: String, olderThan rhs: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
    let a = parts(lhs)
    let b = parts(rhs)
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x < y }
    }
    return false
}

struct UpdateInfo: Equatable {
    let version: String
    let url: URL
}

enum UpdateChecker {
    static let releasesPage =
        URL(string: "https://github.com/flutterkage2k/mac_inputswitcher_260721/releases")!

    /// GitHub 최신 릴리스 조회 (인증 불필요, rate limit 60회/시로 충분)
    static func latestRelease() async throws -> UpdateInfo {
        let api = URL(string:
            "https://api.github.com/repos/flutterkage2k/mac_inputswitcher_260721/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: api)
        struct Release: Decodable {
            let tag_name: String
            let html_url: String
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        return UpdateInfo(version: release.tag_name,
                          url: URL(string: release.html_url) ?? releasesPage)
    }
}
