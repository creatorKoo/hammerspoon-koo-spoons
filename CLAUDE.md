# CLAUDE.md

개인 제작 Hammerspoon Spoon 모음 (AppFocus · HangulToggle · InputSourceHUD).
공식 Hammerspoon/Spoons 저장소와 같은 `Spoons/<이름>.spoon/init.lua` 레이아웃.
문서·코드 주석은 한국어, 커밋 메시지는 영어.

## 배포 구조 (핵심 전제)

- repo에는 **배포 가능한 spoon 소스만** 둔다. 개인 키 매핑·설정은 `~/.hammerspoon/init.lua`(git 밖, 로컬)에서 `spoon.X:configure({...})`로 주입한다 — spoon 코드에 개인 설정을 하드코딩하지 말 것.
- `install.sh`가 각 spoon을 `~/.hammerspoon/Spoons/`에 **심볼릭 링크**한다. 사용자 init.lua의 pathwatcher가 이 repo를 감시하므로 `.lua` 저장 = Hammerspoon 즉시 자동 리로드(라이브 반영). 저장하는 순간 실제 키보드 동작이 바뀐다는 점을 의식할 것.
- spoon의 공개 API(설정 필드, `configure` 옵션)를 바꾸면 `README.md`와 `examples/init.lua`도 함께 갱신한다.

## Spoon 작성 컨벤션

모든 spoon은 단일 `init.lua`이며 공통 골격을 따른다:

- 파일 머리: `--- === 이름 ===` 문서 블록 — 기능 요약, 사용 예, **설계 노트**(왜 이렇게 구현했는지) 포함
- `local obj = {}; obj.__index = obj` + `obj.name` / `obj.version` / `obj.author` / `obj.license`(MIT)
- 설정값은 obj 필드로 상단에 선언하고 `:configure(opts)`로 덮어쓰기(opts를 self에 병합, self 반환 → 체이닝 가능)
- `:start()` / `:stop()` 모두 self 반환. `:stop()`은 생성한 eventtap·observer·timer·canvas를 **전부** 정리
- 섹션 구분 주석: `---------------------------------------------------------------- 제목`

### Hammerspoon 특유의 규칙 (기존 코드가 지켜온 것)

- **eventtap 콜백은 즉시 리턴** — 콜백이 느리면 OS가 탭을 비활성화한다. 실제 작업은 `hs.timer.doAfter(0, ...)`로 미룬다.
- 좌/우 modifier 구분은 상태 변수가 아니라 각 이벤트의 **raw flags**(`e:getRawEventData().CGEventData.flags` + `NX_DEVICER*KEYMASK` 비트)로 판정한다 — key-up 유실에도 stuck 상태가 안 생긴다.
- `hs.keycodes.inputSourceChanged` 콜백은 **HS 전역 1슬롯**이며 현재 InputSourceHUD가 점유 중. 다른 spoon에서 사용 금지.
- AX(`hs.axuielement`) 호출은 앱에 따라 깨지기 쉬우므로 `pcall`로 감싼다.
- 영구 상태 파일은 `~/.local/state/<이름>/`에 둔다 (예: AppFocus의 `usage.json`).

## 테스트 / 검증

자동 테스트 없음. 검증 = 파일 저장 → HS 자동 리로드 → 수동 확인.

- 터미널에서 `hs -c '<lua식>'`으로 상태 점검 가능 (hs.ipc CLI 설치되어 있음)
- eventtap·AX는 손쉬운 사용(Accessibility) 권한 필요. 암호 필드(보안 입력) 중에는 macOS가 이벤트 탭을 차단함 — 버그 아님.

## 릴리스 (스푼별 독립 버저닝)

1. 해당 spoon의 `obj.version` 갱신 (semver)
2. 커밋 제목: `<이름> v<버전>: <영어 요약>` (예: `AppFocus v1.1.0: order candidates by recency`)
3. 태그 `<이름>-v<버전>` (예: `AppFocus-v1.1.0`) → 해당 spoon의 zip만 첨부해 GitHub Release
   - zip 생성: `cd Spoons && zip -r <이름>.spoon.zip <이름>.spoon` (`*.zip`은 gitignore됨)

## 기타

- `install.sh` / `uninstall.sh`: bash + `set -euo pipefail`, Karabiner JSON 조작은 `jq` 사용. install은 룰을 삭제가 아니라 `enabled:false`로 끄고 백업을 남긴다(롤백 가능해야 함).
