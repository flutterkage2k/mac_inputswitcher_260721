# 입력소스 전환 메뉴바 앱 — 설계 스펙

날짜: 2026-07-21
상태: 승인됨

## 배경

- [kawa](https://github.com/hatashiro/kawa)(입력소스별 전용 단축키 앱)는 2017년 이후 업데이트 중단. Carthage 기반 구식 프로젝트라 fork 비용 > 재작성 비용.
- macOS에는 `TISSelectInputSource`가 CJK(한/중/일) 입력소스로 전환 시 메뉴바 아이콘만 바뀌고 실제 입력은 이전 소스로 들어가는 버그가 있으며, macOS 26 (Tahoe)에서도 존재.
- 사용자는 Karabiner + macism 조합(및 자작 [Karabiner-input-source-shortcut-builder](https://github.com/flutterkage2k/Karabiner-input-source-shortcut-builder))을 써봤으나 **전환 지연/씹힘**과 **설정 파편화**가 불만.
- macism의 150ms 대기는 CLI라서 GUI 이벤트 루프가 없는 데 대한 우회 비용. 상주 GUI 앱은 이 비용을 대부분 피할 수 있다.

## 목표

kawa의 재현: **입력소스별 전용 단축키**(예: ⌘⇧K=한글, ⌘⇧E=영어)로 즉시·안정적으로 전환하는 단일 메뉴바 앱.

- 외부 의존성 없음 (Karabiner, macism 불필요)
- 접근성 권한 없이 동작
- 대상 OS: macOS 14+ (Sequoia/Tahoe 포함)
- 성공 기준: 빠른 연속 타이핑 직전 전환에서도 씹힘 없음, 설정은 앱 하나에서 끝

비목표(YAGNI): 앱별 자동 전환, 순환 토글 키, 입력소스 상태 오버레이 표시.

## 구조 — 3개 유닛

### 1. HotkeyManager
- Carbon `RegisterEventHotKey`로 전역 단축키 등록/해제.
- 선택 이유: 여전히 공식 지원되며 CGEventTap과 달리 접근성 권한 불필요 → 설치 마찰 제로.
- 인터페이스: `register(keyCombo, id)` / `unregister(id)` / 콜백으로 발동 알림.
- 의존: 없음.

### 2. InputSourceSwitcher (핵심 — CJK 버그 우회 지점)
- 목록: `TISCreateInputSourceList`로 선택 가능(selectable, keyboard 계열) 소스 나열.
- 전환 알고리즘:
  1. `TISSelectInputSource(target)` 호출
  2. 짧은 대기 후 `TISCopyCurrentKeyboardInputSource`로 실제 전환 **검증**
  3. 불일치 → 재시도 1회
  4. 그래도 실패 → 시스템의 "입력 메뉴에서 다음 소스 선택" 단축키를 CGEvent로 에뮬레이션 (macism의 최후 수단과 동일)
- 검증 대기시간은 설정에서 조정 가능한 단일 값으로 노출. 기본값은 수십 ms에서 시작 (GUI 앱이므로 macism의 150ms보다 공격적으로 시작하되, 하드웨어/OS별 편차를 위한 조정 노브를 남긴다).
- 인터페이스: `availableSources() -> [Source]` / `switchTo(sourceID) async -> Bool`.
- 의존: 없음.

### 3. UI (MenuBarExtra)
- SwiftUI `MenuBarExtra` 하나: 입력소스 목록 + 각 소스 옆 단축키 레코더 + 현재 활성 소스 표시.
- 설정 저장: UserDefaults (소스 ID → 키 콤보 매핑).
- 로그인 시 자동 시작: `SMAppService.mainApp`.
- 의존: HotkeyManager, InputSourceSwitcher.

## 데이터 흐름

단축키 발동 → HotkeyManager 콜백 → 매핑에서 소스 ID 조회 → InputSourceSwitcher.switchTo() → (실패 시 폴백 체인) → UI에 현재 소스 반영.

## 에러 처리

- 매핑된 입력소스가 시스템에서 제거된 경우: 해당 단축키 무시, 설정 화면에 "소스 없음" 표시.
- 단축키 등록 실패(다른 앱과 충돌): 해당 항목에 실패 표기.
- 폴백까지 전환 실패: 메뉴바 아이콘으로 조용히 표시 (알림 스팸 없음).

## 테스트

- 전환-검증-폴백 로직 단위 테스트 1개 (TIS 호출은 프로토콜로 추상화해 목 주입).
- 수동 시나리오: 한↔영↔일 빠른 연속 전환, 전환 직후 즉시 타이핑, 재부팅 후 자동 시작 확인.

## 규모/배포

- 파일 4~5개, 수백 줄. Xcode 프로젝트 하나.
- 개인용: 로컬 코드서명으로 충분. 배포 시점에 Developer ID 서명 + notarization 고려.
