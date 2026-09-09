import Foundation

/// 경량 진단 로그: ~/Library/Logs/InputSwitcher.log
/// 전환이 왜 실패/오작동하는지 사용자 머신에서 추적하기 위한 것.
func dbg(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/InputSwitcher.log")
    // 무한 증식 방지: 1MB 넘으면 직전 파일을 .1로 남기고 새로 시작.
    // 지우기만 하면 실험 데이터가 통째로 사라진다 (실제로 닷새치를 잃었다).
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
        let prev = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: prev)
        try? FileManager.default.moveItem(at: url, to: prev)
    }
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
