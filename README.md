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

- macOS 14+ 대상. macOS의 CJK 입력소스 전환 버그(TISSelectInputSource가 백그라운드에서
  CJKV 전환 시 아이콘만 바꾸고 실제 IME는 안 바꿈)는 select 후 **포커스 커밋**(앱이 잠깐
  key가 됐다가 복귀, macism 방식)으로 우회한다. 한/일/중/베트남어 전환 시 화면 우하단에
  아주 작은 창이 잠깐(기본 150ms) 나타났다 사라지는 것은 정상 동작이다.
- 기본 경로는 권한 불필요. 폴백(CGEvent)이 발동될 때만 접근성 권한을 요청한다.
- CJKV 커밋 대기시간(기본 150ms — Tahoe 안정 최소값) 조정:
  `defaults write dev.heesung.InputSwitcher verifyDelayMS -int 100`
  값을 낮추면 빨라지지만 전환이 다시 씹힐 수 있다.
- `verifyDelayMS` 변경은 앱 재시작 후 적용된다.
- "로그인 시 시작" 토글은 .app 번들로 실행할 때만 동작한다 (`swift run`에서는 무시됨).
- 로컬(adhoc) 서명 특성상 재빌드 후에는 접근성 권한(폴백용)을 다시 요청할 수 있다.
