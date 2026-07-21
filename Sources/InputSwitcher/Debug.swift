import Foundation

/// 경량 진단 로그: ~/Library/Logs/InputSwitcher.log
/// 전환이 왜 실패/오작동하는지 사용자 머신에서 추적하기 위한 것.
func dbg(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/InputSwitcher.log")
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "\(ts) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
