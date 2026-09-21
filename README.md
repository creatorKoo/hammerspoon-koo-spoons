# hammerspoon-koo-spoons

[Hammerspoon](https://www.hammerspoon.org/) Spoon 모음. macOS에서 **오른쪽 command를 한/영 키로**, **오른쪽 option을 앱 전환 키로** 쓰기 위해 만들었다.
Spoon은 각각 독립적으로 설치·삭제할 수 있고, 필요한 것만 골라 쓰면 된다.

| Spoon | 기능 | 최신 |
|---|---|---|
| **HangulToggle** | 오른쪽 command = 전용 한/영 키. modifier 기능은 제거되어 빠른 타이핑에도 안전 | [Releases](https://github.com/creatorKoo/hammerspoon-koo-spoons/releases?q=HangulToggle) |
| **AppFocus** | 오른쪽 option 홀드 + 글자 = 실행중 앱 전환/순환 + 실시간 오버레이 | [Releases](https://github.com/creatorKoo/hammerspoon-koo-spoons/releases?q=AppFocus) |
| **InputSourceHUD** | 입력 포커스가 바뀔 때 화면 중앙에 현재 입력소스(한/A) 배지 + Spotlight 영문 전환 | [Releases](https://github.com/creatorKoo/hammerspoon-koo-spoons/releases?q=InputSourceHUD) |
| **WindowFit** | 지정 앱 창이 열릴 때 메인 모니터 가용 영역에 맞춰 자동 리사이즈 | [Releases](https://github.com/creatorKoo/hammerspoon-koo-spoons/releases?q=WindowFit) |

## 빠른 설치

1. Hammerspoon 설치: `brew install --cask hammerspoon` 또는 [공식 사이트](https://www.hammerspoon.org/)에서 받아 실행
2. [Releases](https://github.com/creatorKoo/hammerspoon-koo-spoons/releases)에서 원하는 Spoon의 `*.spoon.zip`을 받아 압축을 풀고 `이름.spoon`을 **더블클릭** → Hammerspoon이 `~/.hammerspoon/Spoons/`에 설치
3. `~/.hammerspoon/init.lua`에 아래처럼 쓰고 저장 (파일이 없으면 새로 만든다. 전체 예시는 [examples/init.lua](examples/init.lua))

   ```lua
   hs.loadSpoon("HangulToggle")
   spoon.HangulToggle:configure({ switchMode = "hotkey" }):start()

   hs.loadSpoon("AppFocus")
   spoon.AppFocus:start()
   ```

4. 시스템 설정 → 개인정보 보호 및 보안 → **손쉬운 사용** → Hammerspoon 허용 → 메뉴바 Hammerspoon 아이콘 → **Reload Config**
5. HangulToggle은 macOS 단축키 "이전 입력 소스 선택"을 F18로 지정해야 한다. 미설정이면 시작 시 **안내창**이 뜨고 "시스템 설정 열기" 버튼으로 바로 이동할 수 있다.

### 업데이트

Hammerspoon에는 자동 업데이트가 없다. 새 버전은 이 저장소를 **Watch → Custom → Releases**로 구독하면 GitHub 알림으로 받을 수 있다 (RSS: `https://github.com/creatorKoo/hammerspoon-koo-spoons/releases.atom`).
적용은 설치와 같다: 새 zip을 풀어 더블클릭 → 교체 확인 → Reload Config. 각 Spoon은 독립 버저닝이라 필요한 것만 갈아끼우면 된다.

### 켜고 끄기

기능을 끄려면 `init.lua`에서 해당 Spoon의 두 줄을 주석 처리하고 저장 후 Reload Config. 잠깐 멈추려면 터미널에서 `hs -c 'spoon.HangulToggle:stop()'` (다시 켜기: `start()`; `hs` CLI는 `hs.ipc.cliInstall()`로 설치).

### AI 에이전트에 맡기기

Claude Code 같은 코딩 에이전트에게 이 README 주소를 주고 "HangulToggle과 AppFocus 설치해 줘"라고 하면 위 절차를 대신 해준다. 손쉬운 사용 권한 허용과 F18 단축키 지정만 직접 클릭하면 된다.

## AppFocus

- `⌥R + 글자` → 이름의 단어 중 하나가 그 글자로 시작하는(표시명·디스크명, shift 무시) **실행중** 앱으로 포커스 이동 — "Google Chrome"은 `g`·`c` 둘 다 매칭
- 진입 시 그 글자의 **가장 최근에 쓴 앱**으로 감. 이미 후보 앱을 보고 있으면 **다음 후보로 순환** (진입 시점의 최근순을 고정한 링을 따라 돌아 핑퐁 없음)
- 매칭되는 실행중 앱이 없으면 **no-op** — 순수 전환기이며 앱 실행 기능은 없음
- 홀드 중 **실시간 오버레이**: 현재 앱=▸, 최근 사용순 정렬. 사용 순번은 `~/.local/state/app-focus/usage.json`
- 선택 설정: 첫 글자가 다른 앱을 특정 키의 순환에 포함 — `spoon.AppFocus:configure({ keys = { c = { "Google Chrome" } } })`

## HangulToggle

- 오른쪽 command = **전용 한/영 키** — 누르는 즉시 전환, modifier 기능은 완전히 제거
  (누른 채 타이핑한 키는 삼키고 cmd를 뺀 복사본을 재전송하므로 ⌘단축키로 새지 않음 — 빠른 타이핑 안전)
  단, 암호 필드 같은 보안 입력 구간에선 macOS가 이벤트 탭을 막으므로 그동안은 평범한 ⌘로 동작함
- 전환 방식 `switchMode` 두 가지
  - `"hotkey"` (권장): macOS 키보드 단축키 **"이전 입력 소스 선택"에 걸어둔 키(기본 F18)** 를 rcmd 누름 시점에 합성해 보냄 — 전환이 앱 자신의 키 이벤트 경로에서 일어나 모든 앱에 즉시 반영
    - 준비: 시스템 설정 > 키보드 > 키보드 단축키 > 입력 소스 > "이전 입력 소스 선택" 켜고 F18 지정 — 미설정이면 시작 시 안내창이 뜨고 "시스템 설정 열기" 버튼으로 바로 이동 (안내 끄기: `setupGuide = false`, 상태 파일 `~/.local/state/HangulToggle/`)
    - 설정: `spoon.HangulToggle:configure({ switchMode = "hotkey" }):start()` (다른 키면 `hotkey = { mods = {"fn"}, key = "f19" }`)
  - `"tis"` (기본값, 준비 불필요): `hs.keycodes.currentSourceID()`로 시스템 입력소스를 직접 전환. 단, Chromium/Electron 계열(Chrome·VS Code·Slack 등)은 밖에서 바뀐 소스를 입력창을 다시 클릭하기 전까지 반영하지 않는 경우가 있음(메뉴바는 '한'인데 영어가 찍힘) — 그 증상이 있으면 `"hotkey"`로
  - 두벌식 외 배열은 tis 모드에서만 관련: `:configure({ korean = "..." })`

## InputSourceHUD

- 입력 포커스가 **다른 필드/창/앱으로 옮겨갈 때** 현재 입력소스(한/A) 배지를 포커스 화면 중앙에 잠깐 표시 — 자체 오버레이라 입력소스를 전혀 건드리지 않음 (입력소스를 갔다 되돌려 네이티브 인디케이터를 유발하던 v1.1의 '플립' 방식은 폐지)
- 위치는 화면 중앙 고정 — 캐럿 좌표(AX) 추정은 웹/Electron 필드에서 엉뚱한 좌표를 반환하는 경우가 많아 쓰지 않음 (macOS 지구본 입력소스 HUD와 같은 접근, 항상 같은 자리라 예측 가능)
- 한영 키·앱별 자동 전환 같은 **실제 전환**은 macOS 네이티브 캡슐이 원래 뜨므로 배지를 중복 표시하지 않음
- **전체화면 코너 배지**: 전체화면 창(메뉴바 숨김)일 때 화면 우상단에 현재 입력소스를 아주 투명하게 상시 표시. 창모드에선 메뉴바에 한/영이 보이므로 자동 숨김. 모니터 연결/해제 시에도 자동 복구
- Spotlight는 활성화 이벤트를 내지 않아 상시 AX 관찰자로 감지 — 열리면 (기본값) 영문 전환, 닫히면 이전 소스 복원
- 텍스트 필드 포커스 변경만 반응(타이핑/캐럿 이동은 무시), 앱 전환은 항상 표시
- 커스터마이즈: `:configure({ duration = 0.8, size = 64, alpha = 0.45 })`(중앙 배지 표시시간·크기·투명도), `spotlightForceSource = false`(Spotlight 자동전환 끔 — `nil`은 Lua 특성상 무효), `cornerBadge=false`(코너 배지 끔), `cornerFullscreenOnly=false`(창모드에서도 코너 배지), `cornerAlpha`·`cornerSize`·`cornerMargin`/`cornerMarginTop`(코너 배지 우측·상단 여백, 상단은 메뉴바 아래 기준), `labelFor(sourceID)`(배지 글자)

## WindowFit

- 지정한 앱(`:configure({ apps = { "Citrix Viewer" } })`)의 창이 **생성될 때** 메인 모니터의 가용 영역(메뉴바·Dock 제외)에 맞춰 자동 리사이즈 — macOS 전체화면이 아닌 "큰 일반 창"
- 왼쪽엔 `leftInset`(기본 75px)만큼 여백을 남겨 Stage Manager 스트립이 반쯤 보이게 함 (값 조절로 튜닝)
- 메인 모니터 밖의 창·macOS 전체화면 창·팝업은 건드리지 않음. 적용은 생성 시 1회 — 이후 수동 리사이즈 존중
- 크기를 스스로 복원하는 앱(Citrix 등) 대비: `applyDelay`(기본 0.3초) 후 적용 + 1초 뒤 1회 재확인
- 지금 떠 있는 창 일괄 정리: `hs -c 'spoon.WindowFit:applyAll()'`

## 개발자 설치 (clone + 심볼릭 링크)

Spoon을 고쳐 쓰거나 기여하려면 zip 대신 저장소를 링크한다.

```sh
git clone https://github.com/creatorKoo/hammerspoon-koo-spoons.git
cd hammerspoon-koo-spoons && ./install.sh
```

하는 일: Hammerspoon 설치(없으면) → `~/.hammerspoon/Spoons/`에 각 spoon **심볼릭 링크** → `~/.hammerspoon/init.lua` 없으면 예시 복사. 예시 init.lua는 링크된 저장소를 감시해 `*.lua` 저장 시 자동 리로드한다.
`--karabiner` 옵션을 주면 선택 프로필의 Karabiner complex rule을 **전부** 비활성화한다(삭제 아님, 백업 생성). 예전 Karabiner 한영/앱전환 룰과 충돌할 때만 쓸 것.

### 디렉토리 설계

```
~/.hammerspoon/              # 로컬 디렉토리 (git 밖) — HS의 공식 홈
  init.lua                   # 개인 설정: loadSpoon + configure (examples/init.lua 참고)
  Spoons/
    HangulToggle.spoon → zip 설치면 복사본, clone 설치면 이 repo 링크
    AppFocus.spoon
    (서드파티.spoon)          # 다른 spoon을 설치해도 repo와 안 섞임
```

repo는 배포 가능한 spoon 소스만 가진다. 개인 키 매핑은 `~/.hammerspoon/init.lua`(로컬)에서 `spoon.X:configure({...})`로 주입한다 — spoon 수정 없이 설정 변경 가능.

## 배포 / 버저닝 (스푼별)

- 각 spoon은 독립적으로 버저닝: spoon의 `obj.version` 갱신 → **스푼별 태그** `<이름>-v<버전>` (예: `AppFocus-v1.0.0`) → 해당 spoon zip만 첨부한 Release 발행
- 배포용 zip: `cd Spoons && zip -r AppFocus.spoon.zip AppFocus.spoon` → 받는 쪽은 zip을 풀어 더블클릭하면 Hammerspoon이 자동 설치
- 각 spoon은 단일 `init.lua`로 자립하며 서로 의존하지 않는다. 공식 [Hammerspoon/Spoons](https://github.com/Hammerspoon/Spoons)는 소스를 `Source/`, zip을 `Spoons/`에 두는 구조라 제출 시 그 형식(영어 docstring 포함)에 맞추면 된다

## 롤백

```sh
./uninstall.sh              # clone 설치의 spoon 링크 제거
./uninstall.sh --karabiner  # + install.sh --karabiner 가 끈 Karabiner 룰 재활성화
```
zip으로 설치했다면 `~/.hammerspoon/Spoons/이름.spoon` 폴더를 지우고 init.lua의 해당 줄을 정리한다.

## 알려진 한계

- 암호 입력 필드(보안 입력) 중에는 macOS가 이벤트 탭을 차단하므로 그 순간 단축키가 동작하지 않음
- InputSourceHUD는 Hammerspoon 전역 1슬롯인 `hs.keycodes.inputSourceChanged` 콜백을 점유한다. 같은 콜백을 쓰는 다른 spoon과는 함께 쓸 수 없음
