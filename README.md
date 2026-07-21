# InputSwitcher

입력소스별 전용 단축키로 즉시 전환하는 macOS 메뉴바 앱.
업데이트가 중단된 [kawa](https://github.com/hatashiro/kawa)의 현대적 재구현입니다.

- 예: `⌃⌥⇧⌘J` → 한글, `⌃⌥⇧⌘K` → 영어, `⌃⌥⇧⌘L` → 일본어 (단축키는 자유롭게 설정)
- macOS의 악명 높은 **CJK 입력소스 전환 버그**(전환해도 실제 타이핑은 이전 언어)를 우회
- Spotlight / Raycast 같은 런처 패널이 열려 있어도 패널을 닫지 않고 전환
- 외부 의존성 0 — Karabiner, macism 필요 없음. 앱 하나로 끝

## ⚠️ 사용에 대한 경고

- **개인 프로젝트입니다.** 어떠한 보증 없이 "있는 그대로" 제공되며, 사용으로 인한
  문제(입력소스 설정 변경, 데이터 입력 오류 등)에 대해 개발자는 책임지지 않습니다.
- 이 앱은 **Apple 공증(notarization)을 받지 않았습니다.** 직접 빌드해서 쓰는 것을
  권장하며, 빌드된 앱을 내려받아 실행하면 macOS Gatekeeper 경고가 뜹니다 (아래 참고).
- CJK 전환 시 화면 우하단에 아주 작은 창이 잠깐(기본 150ms) 나타났다 사라집니다.
  이것은 macOS 버그 우회를 위한 **정상 동작**입니다.
- 폴백 경로에서만 접근성 권한을 요청합니다. 기본 동작에는 아무 권한도 필요 없습니다.
- macOS 14 (Sonoma) 이상, Apple Silicon/Intel. macOS 26 (Tahoe)에서 개발·테스트됨.

## 설치 (소스 빌드 — 권장)

Xcode Command Line Tools만 있으면 됩니다.

```bash
git clone https://github.com/flutterkage2k/mac_inputswitcher_260721.git
cd mac_inputswitcher_260721
./scripts/bundle.sh
cp -Rf build/InputSwitcher.app /Applications/
open /Applications/InputSwitcher.app
```

빌드된 .app을 내려받아 쓰는 경우 Gatekeeper가 차단하면:
앱을 **우클릭 → 열기**, 또는 터미널에서
`xattr -d com.apple.quarantine /Applications/InputSwitcher.app`

## 사용법

1. 메뉴바의 키보드 아이콘 클릭
2. 각 입력소스 옆 **단축키설정** → 원하는 단축키 입력 (⌘/⌥/⌃/⇧ 수식키 필수)
3. 어느 앱에서든 단축키로 즉시 전환. "로그인 시 시작"을 켜면 부팅 후 자동 실행

## 작동 원리

`TISSelectInputSource`는 백그라운드 앱에서 CJK(한/중/일) 입력소스로 전환할 때
메뉴바 아이콘만 바꾸고 실제 IME는 바꾸지 않는 버그가 있습니다 (macOS 26에서도 존재).
InputSwitcher는 select 후 **포커스 커밋** — 앱이 잠깐 key가 됐다가 이전 앱으로
복귀하는 사이클([macism](https://github.com/laishulu/macism)과 같은 방식) — 으로
전환을 실제 적용시킵니다. Spotlight/Raycast 패널이 열려 있으면 패널이 닫히지 않도록
커밋을 생략하고 plain select만 수행합니다.

## 설정 조정

- CJK 커밋 대기시간 (기본 150ms — Tahoe 안정 최소값):
  `defaults write dev.heesung.InputSwitcher verifyDelayMS -int 100`
  낮추면 빨라지지만 전환이 씹힐 수 있습니다. 변경은 앱 재시작 후 적용됩니다.
- 진단 로그: `~/Library/Logs/InputSwitcher.log` (1MB 상한). 문제 리포트 시 첨부해 주세요.
- 로컬(adhoc) 서명 특성상 재빌드 후에는 접근성 권한(폴백용)을 다시 요청할 수 있습니다.
- "로그인 시 시작"은 .app 번들로 실행할 때만 동작합니다 (`swift run`에서는 무시됨).

## 개발

```bash
swift build   # 빌드
swift test    # 단위 테스트 (13개)
./scripts/bundle.sh  # .app 번들 생성 (adhoc 서명)
```

## 라이선스

MIT — [@kage2k](https://github.com/flutterkage2k)
