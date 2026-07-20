# hammerspoon-koo-spoons

개인 제작 [Hammerspoon](https://www.hammerspoon.org/) Spoon 모음. 공식 [Hammerspoon/Spoons](https://github.com/Hammerspoon/Spoons) 저장소와 같은 `Spoons/` 레이아웃을 사용한다.

| Spoon | 기능 |
|---|---|
| **AppFocus** | ⌥R(오른쪽 option) 홀드 + 글자 = 실행중 앱 순환 포커스 + 실시간 오버레이 |
| **HangulToggle** | 오른쪽 command 탭 = 한/영 전환 (입력소스 직접 토글) |

## AppFocus

- `⌥R + 글자` → 이름의 단어 중 하나가 그 글자로 시작하는(표시명·디스크명, shift 무시) **실행중** 앱으로 포커스 이동 — "Google Chrome"은 `g`·`c` 둘 다 매칭
- 이미 그 앱을 보고 있으면 **다음 후보로 순환** (예: `i` 반복 → iTerm2 ↔ IntelliJ IDEA)
- 매칭되는 실행중 앱이 없으면 **no-op** — 순수 전환기이며 앱 실행 기능은 없음
- 홀드 중 **실시간 오버레이**: 현재 앱=▸, 사용 빈도순 정렬. 빈도는 `~/.local/state/app-focus/usage.json`
- 선택 설정: 첫 글자가 다른 앱을 특정 키의 순환에 포함 — `spoon.AppFocus:configure({ keys = { c = { "Google Chrome" } } })`

## HangulToggle

- 오른쪽 command = **전용 한/영 키** — 누르는 즉시 전환, modifier 기능은 완전히 제거
  (키 이벤트의 cmd 플래그를 벗겨내므로 누른 채 타이핑해도 ⌘단축키로 새지 않음 — 빠른 타이핑 안전)
- F18/설정앱 우회 없이 `hs.keycodes.currentSourceID()`로 입력소스 직접 전환
- 두벌식 외 배열은 `:configure({ korean = "..." })`로 변경

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

## 배포 / 버저닝

- spoon의 `obj.version` 갱신 + git tag (`v1.0.0`)
- 배포용 zip: `cd Spoons && zip -r AppFocus.spoon.zip AppFocus.spoon` → GitHub Release 첨부. 받는 쪽은 zip을 풀어 더블클릭하면 Hammerspoon이 자동 설치
- repo가 공식 Spoons 저장소와 같은 레이아웃이므로, 추후 [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html) 커스텀 저장소 등록이나 공식 저장소 PR도 가능

## 롤백

```sh
./uninstall.sh   # Karabiner 룰 재활성화 + spoon 링크 제거
```

`legacy/global_app_shortcut.json`은 구 Karabiner complex modification (참고용, 시험 기간 후 삭제 예정).

## 알려진 한계

- 암호 입력 필드(보안 입력) 중에는 macOS가 이벤트 탭을 차단하므로 그 순간 단축키가 동작하지 않음
