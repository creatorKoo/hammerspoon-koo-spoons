--- === HangulToggle ===
---
--- 오른쪽 command = 전용 한/영 키.
--- 누르는 즉시 입력소스를 전환하고, 오른쪽 command의 modifier 기능은 완전히 제거한다:
---   · rcmd 키 이벤트 자체를 앱에 전달하지 않음
---   · rcmd를 (미처 떼기 전에) 누른 채 타이핑해도 ⌘단축키로 들어가지 않도록
---     키 이벤트의 cmd 플래그를 벗겨냄 — 빠른 타이핑에 안전
--- 왼쪽 command는 평소대로 동작한다.
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("HangulToggle")
---   spoon.HangulToggle:start()
---   -- 입력소스가 다르면: :configure({ korean = "com.apple.inputmethod.Korean.390Sebulshik" })
local obj = {}
obj.__index = obj

obj.name = "HangulToggle"
obj.version = "1.0.0"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.english = "com.apple.keylayout.ABC"
obj.korean = "com.apple.inputmethod.Korean.2SetKorean"

local etypes = hs.eventtap.event.types

local RIGHT_CMD_KC = 54     -- hs.keycodes.map.rightcmd
local RIGHT_CMD_BIT = 0x10  -- NX_DEVICERCMDKEYMASK: raw flags에서 '오른쪽' cmd 식별
local LEFT_CMD_BIT = 0x08   -- NX_DEVICELCMDKEYMASK

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

  -- rcmd를 아직 누른 채 타이핑하는 경우: 키 이벤트에서 cmd 플래그 제거
  -- (플래그는 하드웨어 상태에서 오므로 flagsChanged를 삼키는 것만으론 부족)
  self.stripTap = hs.eventtap.new({ etypes.keyDown, etypes.keyUp }, function(e)
    local raw = e:getRawEventData().CGEventData.flags
    if (raw & RIGHT_CMD_BIT) ~= 0 and (raw & LEFT_CMD_BIT) == 0 then
      local f = e:getFlags()
      f.cmd = nil
      e:setFlags(f)  -- 수정된 이벤트가 그대로 전달됨
    end
    return false
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
