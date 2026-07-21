# hammerspoon-koo-spoons

개인 제작 [Hammerspoon](https://www.hammerspoon.org/) Spoon 모음. 공식 [Hammerspoon/Spoons](https://github.com/Hammerspoon/Spoons) 저장소와 같은 `Spoons/` 레이아웃을 사용한다.

| Spoon | 기능 |
|---|---|
| **AppFocus** | ⌥R(오른쪽 option) 홀드 + 글자 = 실행중 앱 순환 포커스 + 실시간 오버레이 |
| **HangulToggle** | 오른쪽 command = 전용 한/영 키 (입력소스 직접 토글) |
| **InputSourceHUD** | 입력 포커스 변경 시 캐럿 근처에 현재 입력소스(한/A) 배지 표시 + Spotlight 영문 전환 |
| **WindowFit** | 지정 앱 창이 열릴 때 메인 모니터 가용 영역에 맞춰 자동 리사이즈 (Stage Manager 여백 유지) |

## AppFocus

- `⌥R + 글자` → 이름의 단어 중 하나가 그 글자로 시작하는(표시명·디스크명, shift 무시) **실행중** 앱으로 포커스 이동 — "Google Chrome"은 `g`·`c` 둘 다 매칭
- 진입 시 그 글자의 **가장 최근에 쓴 앱**으로 감. 이미 후보 앱을 보고 있으면 **다음 후보로 순환** (진입 시점의 최근순을 고정한 링을 따라 돌아 핑퐁 없음)
- 매칭되는 실행중 앱이 없으면 **no-op** — 순수 전환기이며 앱 실행 기능은 없음
- 홀드 중 **실시간 오버레이**: 현재 앱=▸, 최근 사용순 정렬. 사용 순번은 `~/.local/state/app-focus/usage.json`
- 선택 설정: 첫 글자가 다른 앱을 특정 키의 순환에 포함 — `spoon.AppFocus:configure({ keys = { c = { "Google Chrome" } } })`

## HangulToggle

- 오른쪽 command = **전용 한/영 키** — 누르는 즉시 전환, modifier 기능은 완전히 제거
  (키 이벤트의 cmd 플래그를 벗겨내므로 누른 채 타이핑해도 ⌘단축키로 새지 않음 — 빠른 타이핑 안전)
- F18/설정앱 우회 없이 `hs.keycodes.currentSourceID()`로 입력소스 직접 전환
- 두벌식 외 배열은 `:configure({ korean = "..." })`로 변경

## InputSourceHUD

- 입력 포커스가 **다른 필드/창/앱으로 옮겨갈 때** macOS 네이티브 입력소스 인디케이터를 캐럿 옆에 잠깐 띄운다. 원리: 다른 소스로 전환했다 즉시 되돌리는 "플립"으로 네이티브 UI를 유발 (커스텀 오버레이 없음, 최종 소스는 그대로)
- **전체화면 코너 배지**: 전체화면 창(메뉴바 숨김)일 때 화면 우상단에 현재 입력소스(한/A)를 아주 투명하게 상시 표시. 캐럿·플립에 의존하지 않아 Slack·Chrome 같은 웹 기반 입력창에서도 항상 보임. 창모드에선 메뉴바에 한/영이 보이므로 자동 숨김
- Spotlight는 활성화 이벤트를 내지 않아 상시 AX 관찰자로 감지 — 열리면 (기본값) 영문 전환, 닫히면 이전 소스 복원
- 텍스트 필드 포커스 변경만 반응(타이핑/캐럿 이동은 무시). 웹 기반 필드는 macOS가 네이티브 인디케이터를 못 그려 캐럿 표시가 안 되지만 전체화면이면 코너 배지가 대신 보여줌
- 커스터마이즈: `:configure({ spotlightForceSource = nil })`(Spotlight 자동전환 끔), `cornerBadge=false`(코너 배지 끔), `cornerFullscreenOnly=false`(창모드에서도 코너 배지), `cornerAlpha`·`cornerSize`, `labelFor(sourceID)`(배지 글자)

## WindowFit

- 지정한 앱(`:configure({ apps = { "Citrix Viewer" } })`)의 창이 **생성될 때** 메인 모니터의 가용 영역(메뉴바·Dock 제외)에 맞춰 자동 리사이즈 — macOS 전체화면이 아닌 "큰 일반 창"
- 왼쪽엔 `leftInset`(기본 75px)만큼 여백을 남겨 Stage Manager 스트립이 반쯤 보이게 함 (값 조절로 튜닝)
- 메인 모니터 밖의 창·macOS 전체화면 창·팝업은 건드리지 않음. 적용은 생성 시 1회 — 이후 수동 리사이즈 존중
- 크기를 스스로 복원하는 앱(Citrix 등) 대비: `applyDelay`(기본 0.3초) 후 적용 + 1초 뒤 1회 재확인
- 지금 떠 있는 창 일괄 정리: `hs -c 'spoon.WindowFit:applyAll()'`

## 설치

```sh
./install.sh
```

하는 일: Hammerspoon 설치(없으면) → `~/.hammerspoon/Spoons/`에 spoon **심볼릭 링크** → `~/.hammerspoon/init.lua` 없으면 예시 복사 → Karabiner 룰 비활성화(백업).

처음이면: 시스템 설정 → 개인정보 보호 및 보안 → **손쉬운 사용** → Hammerspoon 허용 → Reload Config.

### 디렉토리 설계

```
~/.hammerspoon/              # 로컬 디렉토리 (git 밖) — HS의 공식 홈
  init.lua                   # 개인 설정: loadSpoon + 키 매핑 (examples/init.lua 참고)
  Spoons/
    AppFocus.spoon     → 이 repo 링크
    HangulToggle.spoon → 이 repo 링크
    (서드파티.spoon)          # 다른 spoon을 설치해도 repo와 안 섞임
```

repo는 배포 가능한 spoon 소스만 가진다. 개인 키 매핑은 `~/.hammerspoon/init.lua`(로컬)에서 `spoon.AppFocus:configure({...})`로 주입 — spoon 수정 없이 매핑 변경 가능하고, `*.lua` 저장 시 자동 리로드된다.

## 배포 / 버저닝 (스푼별)

- 각 spoon은 독립적으로 버저닝: spoon의 `obj.version` 갱신 → **스푼별 태그** `<이름>-v<버전>` (예: `AppFocus-v1.0.0`) → 해당 spoon zip만 첨부한 Release 발행
- 배포용 zip: `cd Spoons && zip -r AppFocus.spoon.zip AppFocus.spoon` → 받는 쪽은 zip을 풀어 더블클릭하면 Hammerspoon이 자동 설치
- repo가 공식 Spoons 저장소와 같은 레이아웃이므로, 추후 [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html) 커스텀 저장소 등록이나 공식 저장소 PR도 가능

## 롤백

```sh
./uninstall.sh   # Karabiner 룰 재활성화 + spoon 링크 제거
```

`legacy/global_app_shortcut.json`은 구 Karabiner complex modification (참고용, 시험 기간 후 삭제 예정).

## 알려진 한계

- 암호 입력 필드(보안 입력) 중에는 macOS가 이벤트 탭을 차단하므로 그 순간 단축키가 동작하지 않음
