--- === InputSourceHUD ===
---
--- 입력 포커스가 바뀔 때(다른 필드/창/앱으로 이동) 현재 입력소스(한/A) 배지를
--- 텍스트 캐럿 근처에 잠깐 표시한다. 마우스 위치와 무관.
---
--- 트리거: 앱 활성화 + 포커스 UI 요소 변경(AXFocusedUIElementChanged).
--- 위치 폴백 체인: 캐럿 좌표(AX) → 입력 필드 프레임 → 포커스 창 중앙 → 화면 중앙.
--- Spotlight: 일반 앱과 달리 활성화 이벤트를 내지 않으므로 프로세스에 상시 AX 관찰자를
--- 부착해 감지하고, `spotlightForceSource`가 설정돼 있으면 열릴 때 그 입력소스로 자동 전환.
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("InputSourceHUD")
---   spoon.InputSourceHUD:start()
---
--- 요구: 손쉬운 사용(Accessibility) 권한.
local obj = {}
obj.__index = obj

obj.name = "InputSourceHUD"
obj.version = "1.0.0"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.duration = 0.8       -- 배지 표시 시간(초)
obj.readDelay = 0.15     -- 포커스 이벤트 후 입력소스를 읽기까지 지연 (앱별 자동 전환 결과 반영용)
obj.size = 72            -- 배지 한 변 크기(pt)
obj.spotlightForceSource = "com.apple.keylayout.ABC"  -- Spotlight 열릴 때 전환할 소스. nil이면 표시만

--- 입력소스 ID → 배지 글자 (커스터마이즈 가능)
function obj.labelFor(sourceID)
  if sourceID:find("Korean", 1, true) or sourceID:find("Hangul", 1, true) then return "한" end
  return "A"
end

local ax = require("hs.axuielement")

---------------------------------------------------------------- 위치 계산

local function screenFrameFor(pt)
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    if pt.x >= f.x and pt.x <= f.x + f.w and pt.y >= f.y and pt.y <= f.y + f.h then
      return s:frame()
    end
  end
  return hs.screen.mainScreen():frame()
end

-- 배지를 띄울 지점과 "텍스트 입력 요소인지" 여부를 반환.
-- 캐럿(AX 선택 범위의 화면 좌표) → 요소 프레임 → 포커스 창 중앙 → 화면 중앙 순 폴백.
local function caretPoint()
  local el = ax.systemWideElement():attributeValue("AXFocusedUIElement")
  if el then
    local range = el:attributeValue("AXSelectedTextRange")
    if range then
      local ok, rect = pcall(function()
        return el:parameterizedAttributeValue("AXBoundsForRange", range)
      end)
      if ok and type(rect) == "table" and rect.x and not (rect.x == 0 and rect.y == 0) then
        return { x = rect.x, y = rect.y + (rect.h or 0) }, true
      end
    end
    local ok, frame = pcall(function() return el:attributeValue("AXFrame") end)
    if ok and type(frame) == "table" and frame.x then
      return { x = frame.x + frame.w / 2, y = frame.y + frame.h }, range ~= nil
    end
  end
  local win = hs.window.focusedWindow()
  if win then
    local f = win:frame()
    return { x = f.x + f.w / 2, y = f.y + f.h / 2 }, false
  end
  local f = hs.screen.mainScreen():frame()
  return { x = f.x + f.w / 2, y = f.y + f.h / 2 }, false
end

---------------------------------------------------------------- 배지 그리기

function obj:_draw(pt)
  if self.canvas then self.canvas:delete(); self.canvas = nil end
  if self.hideTimer then self.hideTimer:stop(); self.hideTimer = nil end

  local S = self.size
  local sf = screenFrameFor(pt)
  local x = math.min(math.max(pt.x + 10, sf.x + 4), sf.x + sf.w - S - 4)
  local y = math.min(math.max(pt.y + 10, sf.y + 4), sf.y + sf.h - S - 4)
  local label = self.labelFor(hs.keycodes.currentSourceID() or "")

  local c = hs.canvas.new({ x = x, y = y, w = S, h = S })
  c[1] = {
    type = "rectangle", action = "fill",
    fillColor = { red = 0.07, green = 0.08, blue = 0.10, alpha = 0.92 },
    roundedRectRadii = { xRadius = S * 0.22, yRadius = S * 0.22 },
  }
  c[2] = {
    type = "text", text = label,
    textSize = S * 0.5, textColor = { hex = "#e6edf3" }, textAlignment = "center",
    frame = { x = 0, y = S * 0.16, w = S, h = S * 0.68 },
  }
  c:level(hs.canvas.windowLevels.overlay)
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:show()
  self.canvas = c
  self.hideTimer = hs.timer.doAfter(self.duration, function()
    if self.canvas then self.canvas:delete(0.15); self.canvas = nil end
  end)
end

-- requireText=true면 텍스트 입력 요소일 때만 표시 (버튼 포커스 등에는 안 뜸)
function obj:_scheduleShow(requireText)
  if self.pending then self.pending:stop() end
  self.pending = hs.timer.doAfter(self.readDelay, function()
    self.pending = nil
    local pt, isText = caretPoint()
    if requireText and not isText then return end
    self:_draw(pt)
  end)
end

--- 수동/테스트용 즉시 표시
function obj:show()
  self:_scheduleShow(false)
  return self
end

---------------------------------------------------------------- 관찰자

-- 현재 활성 앱의 포커스 요소 변경 감시 (앱 전환 시마다 재부착)
function obj:_attachObserver(app)
  if self.obs then pcall(function() self.obs:stop() end); self.obs = nil end
  if not app then return end
  local ok, obs = pcall(ax.observer.new, app:pid())
  if not ok then return end
  obs:callback(function() obj:_scheduleShow(true) end)
  local attached = pcall(function()
    obs:addWatcher(ax.applicationElement(app), "AXFocusedUIElementChanged"):start()
  end)
  if attached then self.obs = obs end
end

-- Spotlight 상시 감시: 검색 필드 포커스 → (옵션) 입력소스 전환 + 배지
function obj:_ensureSpotlight()
  local sp = hs.application.get("Spotlight")
  if not sp then return end
  if self.spObs and self.spotlightPid == sp:pid() then return end
  if self.spObs then pcall(function() self.spObs:stop() end); self.spObs = nil end

  local ok, obs = pcall(ax.observer.new, sp:pid())
  if not ok then return end
  obs:callback(function()
    -- 닫힐 때도 이벤트가 오므로, 잠깐 뒤 Spotlight 창이 실제로 떠 있는지 확인
    hs.timer.doAfter(0.05, function()
      local sp2 = hs.application.get("Spotlight")
      if sp2 and #sp2:allWindows() > 0 then
        if obj.spotlightForceSource then
          hs.keycodes.currentSourceID(obj.spotlightForceSource)
        end
        obj:_scheduleShow(false)
      end
    end)
  end)
  local attached = pcall(function()
    obs:addWatcher(ax.applicationElement(sp), "AXFocusedUIElementChanged"):start()
  end)
  if attached then
    self.spObs = obs
    self.spotlightPid = sp:pid()
  end
end

---------------------------------------------------------------- 라이프사이클

function obj:configure(opts)
  for k, v in pairs(opts or {}) do self[k] = v end
  return self
end

function obj:start()
  self.appWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      obj:_attachObserver(app)
      obj:_scheduleShow(false)  -- 앱 전환은 항상 표시 (폴백 위치라도)
      obj:_ensureSpotlight()    -- Spotlight 재시작 대비 재부착
    end
  end)
  self.appWatcher:start()
  self:_attachObserver(hs.application.frontmostApplication())
  self:_ensureSpotlight()
  return self
end

function obj:stop()
  if self.appWatcher then self.appWatcher:stop(); self.appWatcher = nil end
  if self.obs then pcall(function() self.obs:stop() end); self.obs = nil end
  if self.spObs then pcall(function() self.spObs:stop() end); self.spObs = nil end
  if self.pending then self.pending:stop(); self.pending = nil end
  if self.hideTimer then self.hideTimer:stop(); self.hideTimer = nil end
  if self.canvas then self.canvas:delete(); self.canvas = nil end
  return self
end

return obj
