import Foundation
import os

/// 통합 로그 미러. 파일 로그는 정리 도구(Memory Cleaner 등)가 ~/Library/Logs를 비우면
/// 통째로 사라진다(2026-10-18 실제 발생). 통합 로그에 같이 남기면 시스템 로그와 같은
/// 시각축에서 대조할 수 있다:
///   log show --last 1d --predicate 'subsystem == "dev.heesung.InputSwitcher"'
private let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.heesung.InputSwitcher",
                              category: "switch")

/// 경량 진단 로그: ~/Library/Logs/InputSwitcher.log + 통합 로그
/// 전환이 왜 실패/오작동하는지 사용자 머신에서 추적하기 위한 것.
func dbg(_ msg: String) {
    osLogger.log("\(msg, privacy: .public)")
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

/// 입력소스 변경이 우리 전환의 결과인지, 외부 요인(시스템 단축키, Caps Lock,
/// 메뉴 클릭, 다른 앱)인지 분류한다. 로그 분석용 태그를 반환.
/// - ours: 우리가 요청한 값으로 1초 내 바뀜
/// - ours-detour: 복구 왕복 중 우리가 잠깐 경유한 값
/// - external-after-ours: 우리 전환 후 1.5초 내에 다른 값으로 바뀜 (되돌림 의심)
/// - external: 그 외
func classifyChange(newID: String, lastTarget: String?, lastSwitchAt: Date,
                    recovering: Bool = false, now: Date = Date()) -> String {
    let elapsed = now.timeIntervalSince(lastSwitchAt)
    if newID == lastTarget, elapsed <= 1.0 { return "ours" }
    if lastTarget != nil, newID != lastTarget, elapsed <= 1.5 {
        return recovering ? "ours-detour" : "external-after-ours"
    }
    return "external"
}

/// 보조키(⌃⌥⇧⌘)에서 손을 뗄 때까지 기다린다.
///
/// 로그 근거: 같은 한글 전환인데 단축키로 하면 실패 31%(544회), 앱별 자동 전환은 5%(22회).
/// 두 경로의 차이는 단축키 쪽이 보조키 네 개를 누른 채로 입력소스를 바꾼다는 것뿐이다.
/// 누르고 있는 동안은 어차피 글자를 칠 수 없으므로 기다려도 잃는 입력이 없다.
/// 취소되면 곧바로 반환한다 (호출부에서 Task.isCancelled 확인).
@MainActor
func waitForModifierRelease(isDown: () -> Bool, timeoutMS: Int = 1000,
                            pollMS: Int = 10) async -> (waitedMS: Int, timedOut: Bool) {
    var waited = 0
    while isDown() {
        if waited >= timeoutMS { return (waited, true) }
        try? await Task.sleep(nanoseconds: UInt64(pollMS) * 1_000_000)
        if Task.isCancelled { return (waited, false) }
        waited += pollMS
    }
    return (waited, false)
}
