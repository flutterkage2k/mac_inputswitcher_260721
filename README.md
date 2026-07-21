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
- `verifyDelayMS` 변경은 앱 재시작 후 적용된다.
- "로그인 시 시작" 토글은 .app 번들로 실행할 때만 동작한다 (`swift run`에서는 무시됨).
- 로컬(adhoc) 서명 특성상 재빌드 후에는 접근성 권한(폴백용)을 다시 요청할 수 있다.
