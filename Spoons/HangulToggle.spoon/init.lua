--- === HangulToggle ===
---
--- 오른쪽 command = 전용 한/영 키.
--- 누르는 즉시 입력소스를 전환하고, 오른쪽 command의 modifier 기능은 완전히 제거한다:
---   · rcmd 키 이벤트 자체를 앱에 전달하지 않음
---   · rcmd를 (미처 떼기 전에) 누른 채 타이핑해도 ⌘단축키로 들어가지 않도록
---     그 키 이벤트를 삼키고 cmd 없는 복사본을 재전송 — 빠른 타이핑에 안전
--- 왼쪽 command는 평소대로 동작한다.
---
--- 설계 노트: v1.0은 in-flight 이벤트의 cmd 플래그를 setFlags로 벗겨내는 방식이었는데,
--- 그것만으론 앱이 ⌘단축키로 해석하는 걸 못 막았다 (rcmd+A 전체선택, rcmd+Q 종료가 그대로
--- 발동). 예전엔 Karabiner의 'Right Command → F18' 룰이 드라이버 단계에서 막아줘 이 구멍이
--- 드러나지 않았고, Karabiner를 제거하면서 노출됐다. v1.1은 해당 키 이벤트를 아예 삭제하고
--- (return true) cmd를 뺀 복사본을 새로 posting한다 — 재전송한 이벤트는 userData 표식으로
--- 구분해 재진입을 막는다.
--- 한계: eventtap이 막히는 구간(암호 필드 등 보안 입력, OS가 탭을 비활성화한 순간)에는
--- 오른쪽 command가 다시 평범한 ⌘로 동작한다. 드라이버 단계 리맵(hidutil/Karabiner)만이
--- 그것까지 막을 수 있다.
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("HangulToggle")
---   spoon.HangulToggle:start()
---   -- 입력소스가 다르면: :configure({ korean = "com.apple.inputmethod.Korean.390Sebulshik" })
local obj = {}
obj.__index = obj

obj.name = "HangulToggle"
obj.version = "1.1.0"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.english = "com.apple.keylayout.ABC"
obj.korean = "com.apple.inputmethod.Korean.2SetKorean"

local etypes = hs.eventtap.event.types

local RIGHT_CMD_KC = 54     -- hs.keycodes.map.rightcmd
local RIGHT_CMD_BIT = 0x10  -- NX_DEVICERCMDKEYMASK: raw flags에서 '오른쪽' cmd 식별
local LEFT_CMD_BIT = 0x08   -- NX_DEVICELCMDKEYMASK

-- 재전송한 이벤트에 남기는 표식 (우리 탭이 자기 이벤트를 다시 처리하지 않도록)
local USER_DATA = hs.eventtap.event.properties.eventSourceUserData
local REPOST_MARK = 0x48475447  -- 'HGTG'

function obj:current()
  return hs.keycodes.currentSourceID()
end

function obj:toggle()
  local cur = hs.keycodes.currentSourceID() or ""
  if cur:find("Korean", 1, true) or cur:find("Hangul", 1, true) then
    hs.keycodes.currentSourceID(self.english)
  else
    hs.keycodes.currentSourceID(self.korean)
  end
end

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
