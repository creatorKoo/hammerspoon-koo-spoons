--- === HangulToggle ===
---
--- 오른쪽 command = 전용 한/영 키.
--- 누르는 즉시 입력소스를 전환하고, 오른쪽 command의 modifier 기능은 완전히 제거한다:
---   · rcmd 키 이벤트 자체를 앱에 전달하지 않음
---   · rcmd를 (미처 떼기 전에) 누른 채 타이핑해도 ⌘단축키로 들어가지 않도록
---     그 키 이벤트를 삼키고 cmd 없는 복사본을 재전송 — 빠른 타이핑에 안전
--- 왼쪽 command는 평소대로 동작한다.
---
--- 전환 방식(switchMode) 두 가지:
---   · "hotkey" (권장): macOS 키보드 단축키 "이전 입력 소스 선택"에 걸어둔 키(기본 F18)를
---     rcmd 누름 시점에 합성 down/up으로 즉시 보낸다. 전환이 앱 자신의 키 이벤트 경로 안에서
---     일어나므로 어떤 앱이든 곧바로 반영된다.
---     준비: 시스템 설정 > 키보드 > 키보드 단축키 > 입력 소스 > "이전 입력 소스 선택" = F18
---   · "tis": hs.keycodes.currentSourceID()로 시스템 입력소스를 직접 바꾼다. 준비가 필요 없지만
---     Chromium/Electron 계열(Chrome, VS Code, Slack 등)은 밖에서 바뀐 소스를 입력 컨텍스트가
---     다시 포커스를 받을 때까지 반영하지 않는 경우가 있다(메뉴바는 '한'인데 영어가 찍힘).
---
--- 설계 노트: v1.0은 in-flight 이벤트의 cmd 플래그를 setFlags로 벗겨내는 방식이었는데,
--- 그것만으론 앱이 ⌘단축키로 해석하는 걸 못 막았다 (rcmd+A 전체선택, rcmd+Q 종료가 그대로
--- 발동). 예전엔 Karabiner의 'Right Command → F18' 룰이 드라이버 단계에서 막아줘 이 구멍이
--- 드러나지 않았고, Karabiner를 제거하면서 노출됐다. v1.1은 해당 키 이벤트를 아예 삭제하고
--- (return true) cmd를 뺀 복사본을 새로 posting한다 — 재전송한 이벤트는 userData 표식으로
--- 구분해 재진입을 막는다.
--- v1.2는 전환 자체를 "hotkey" 경로로 옮길 수 있게 했다. TIS API로 밖에서 바꾸면 Chromium 계열이
--- 간헐적으로 반영을 놓치는 문제가 있었고(입력창을 다시 클릭해야 한글이 나옴), 예전 Karabiner
--- F18 구성에서 이 문제가 없던 이유가 바로 앱 안 경로였다. 합성 F18은 fn 플래그를 반드시
--- 포함해야 단축키로 인식된다(하드웨어 F키 이벤트와 같은 플래그). 사용자의 rcmd 뗌은 기다리지
--- 않고 down/up을 연달아 보내므로 체감은 '누르는 즉시'로 동일하다.
--- 한계: eventtap이 막히는 구간(암호 필드 등 보안 입력, OS가 탭을 비활성화한 순간)에는
--- 오른쪽 command가 다시 평범한 ⌘로 동작한다. 드라이버 단계 리맵(hidutil/Karabiner)만이
--- 그것까지 막을 수 있다.
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("HangulToggle")
---   spoon.HangulToggle:configure({ switchMode = "hotkey" }):start()   -- macOS 단축키 F18 준비 필요
---   -- 준비 없이 쓰려면: spoon.HangulToggle:start()  (switchMode 기본값 "tis")
---   -- 단축키를 다른 키에 걸었으면: :configure({ switchMode = "hotkey", hotkey = { mods = {"fn"}, key = "f19" } })
---   -- 입력소스가 다르면(tis 모드): :configure({ korean = "com.apple.inputmethod.Korean.390Sebulshik" })
local obj = {}
obj.__index = obj

obj.name = "HangulToggle"
obj.version = "1.2.0"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.switchMode = "tis"                          -- "tis" | "hotkey" (설명은 파일 머리 참고)
obj.hotkey = { mods = { "fn" }, key = "f18" }   -- hotkey 모드: macOS "이전 입력 소스 선택"에 걸어둔 키.
                                                --   F키는 하드웨어 이벤트처럼 fn 플래그가 있어야 단축키로 인식됨
obj.english = "com.apple.keylayout.ABC"         -- tis 모드에서만 사용
obj.korean = "com.apple.inputmethod.Korean.2SetKorean"

local etypes = hs.eventtap.event.types

local RIGHT_CMD_KC = 54     -- hs.keycodes.map.rightcmd
local RIGHT_CMD_BIT = 0x10  -- NX_DEVICERCMDKEYMASK: raw flags에서 '오른쪽' cmd 식별
local LEFT_CMD_BIT = 0x08   -- NX_DEVICELCMDKEYMASK

-- 재전송한 이벤트에 남기는 표식 (우리 탭이 자기 이벤트를 다시 처리하지 않도록)
local USER_DATA = hs.eventtap.event.properties.eventSourceUserData
local REPOST_MARK = 0x48475447  -- 'HGTG'

---------------------------------------------------------------- 전환

function obj:current()
  return hs.keycodes.currentSourceID()
end

-- tis 모드: 시스템 입력소스를 직접 토글
function obj:toggleTIS()
  local cur = hs.keycodes.currentSourceID() or ""
  if cur:find("Korean", 1, true) or cur:find("Hangul", 1, true) then
    hs.keycodes.currentSourceID(self.english)
  else
    hs.keycodes.currentSourceID(self.korean)
  end
end

-- hotkey 모드: macOS "이전 입력 소스 선택" 단축키를 합성해 앱 안 경로로 전환.
-- down/up을 연달아 보내므로 사용자가 rcmd를 떼기 전에 전환된다. 합성 F키 이벤트는
-- 시스템 단축키 필터를 거치기만 하고 앱에는 도달하지 않는다(단축키가 소비).
function obj:toggleHotkey()
  hs.eventtap.keyStroke(self.hotkey.mods or {}, self.hotkey.key, 0)
end

function obj:toggle()
  if self.switchMode == "hotkey" then self:toggleHotkey() else self:toggleTIS() end
end

---------------------------------------------------------------- 설정 / 시작 / 정지

function obj:configure(opts)
  for k, v in pairs(opts or {}) do self[k] = v end
  return self
end

function obj:start()
  -- rcmd 누름 = 즉시 한/영 전환. 이벤트는 삼켜서 앱이 cmd 자체를 못 보게 함
  self.flagsTap = hs.eventtap.new({ etypes.flagsChanged }, function(e)
    if e:getKeyCode() ~= RIGHT_CMD_KC then return false end
    local raw = e:getRawEventData().CGEventData.flags
    if (raw & RIGHT_CMD_BIT) ~= 0 then
      hs.timer.doAfter(0, function() obj:toggle() end)  -- 탭 콜백은 즉시 리턴
    end
    return true  -- rcmd down/up 모두 앱에 미전달 (전용 한/영 키)
  end)

  -- rcmd를 아직 누른 채 타이핑하는 경우: 원본 키 이벤트를 삭제하고 cmd 없는 복사본을 재전송.
  -- (플래그는 하드웨어 상태에서 오므로 flagsChanged를 삼키는 것만으론 부족하고,
  --  in-flight 이벤트에 setFlags만 해도 앱은 여전히 ⌘단축키로 해석한다 — 설계 노트 참고)
  -- hotkey 모드에서 합성한 F18은 우리가 posting한 것이라 raw flags에 rcmd 장치 비트가 없어 그대로 통과한다.
  self.stripTap = hs.eventtap.new({ etypes.keyDown, etypes.keyUp }, function(e)
    if e:getProperty(USER_DATA) == REPOST_MARK then return false end  -- 우리가 만든 것은 통과
    local raw = e:getRawEventData().CGEventData.flags
    if (raw & RIGHT_CMD_BIT) == 0 or (raw & LEFT_CMD_BIT) ~= 0 then return false end
    local f = e:getFlags()
    if not f.cmd then return false end
    f.cmd = nil
    local clean = e:copy()      -- 오토리핏·키보드 종류 등 나머지 속성 유지
    clean:setFlags(f)
    clean:setProperty(USER_DATA, REPOST_MARK)
    return true, { clean }      -- 원본 삭제 + 정리된 이벤트로 대체
  end)

  self.flagsTap:start()
  self.stripTap:start()
  return self
end

function obj:stop()
  if self.flagsTap then self.flagsTap:stop(); self.flagsTap = nil end
  if self.stripTap then self.stripTap:stop(); self.stripTap = nil end
  return self
end

return obj
