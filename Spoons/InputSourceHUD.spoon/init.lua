--- === InputSourceHUD ===
---
--- 입력 포커스가 바뀔 때(다른 필드/창/앱으로 이동) macOS **네이티브** 입력소스
--- 인디케이터(캐럿 옆 한/A 배지)를 띄운다.
---
--- 원리: macOS는 입력소스가 "전환"될 때만 네이티브 인디케이터를 보여주므로,
--- 포커스 변경 시 다른 소스로 전환했다가 즉시 원래 소스로 되돌리는 플립을 수행한다.
--- 최종 상태는 그대로고, 인디케이터는 현재 소스를 표시한다. 위치·디자인은 macOS가
--- 알아서 처리하므로(캐럿 추적 포함) 별도 좌표 계산이 필요 없다.
---
--- 트리거: 앱 활성화 + 포커스 UI 요소 변경(AXFocusedUIElementChanged).
--- Spotlight: 일반 앱과 달리 활성화 이벤트를 내지 않으므로 프로세스에 상시 AX 관찰자를
--- 부착해 감지하고, `spotlightForceSource`가 설정돼 있으면 열릴 때 그 입력소스로 자동
--- 전환한다 (실제 전환이므로 인디케이터도 자연히 표시됨).
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("InputSourceHUD")
---   spoon.InputSourceHUD:start()
---
--- 요구: 손쉬운 사용(Accessibility) 권한.
local obj = {}
obj.__index = obj

obj.name = "InputSourceHUD"
obj.version = "1.1.0"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.readDelay = 0.1        -- 포커스 이벤트 후 플립까지 지연 (앱별 자동 전환이 먼저 끝나게)
obj.flipDelay = 0.05       -- 다른 소스로 갔다가 되돌아오기까지 간격(초)
obj.suppressWindow = 0.5   -- 이 시간(초) 내 외부 소스 전환이 있었으면 즉시 플립하지 않고 확인 플립으로 미룸
obj.retryDelay = 0.2       -- 확인 플립까지 대기(초) — 전환 직후 캐럿이 자리잡은 뒤 확실히 표시
obj.english = "com.apple.keylayout.ABC"                 -- 플립 상대 소스 (현재가 한국어일 때)
obj.korean = "com.apple.inputmethod.Korean.2SetKorean"  -- 플립 상대 소스 (현재가 영문일 때)
obj.spotlightForceSource = "com.apple.keylayout.ABC"    -- Spotlight 열릴 때 전환할 소스. nil이면 끔

-- 코너 배지: 전체화면(메뉴바 숨김)일 때 현재 입력소스를 화면 우상단에 상시 표시.
-- 캐럿 위치·플립에 의존하지 않으므로 Slack·Chrome 같은 웹 기반 필드에서도 항상 보인다.
obj.cornerBadge = true            -- 코너 배지 사용
obj.cornerFullscreenOnly = true   -- 전체화면 창일 때만 (창모드는 메뉴바에 한/영이 보임)
obj.cornerSize = 34               -- 배지 한 변 크기(pt)
obj.cornerAlpha = 0.35            -- 배경 불투명도 (낮을수록 투명; 흰 글자 대비 확보용)
obj.cornerMargin = 8              -- 화면 우상단 여백(pt)

--- 입력소스 ID → 코너 배지 글자 (커스터마이즈 가능)
function obj.labelFor(sourceID)
  if sourceID:find("Korean", 1, true) or sourceID:find("Hangul", 1, true) then return "한" end
  return "A"
end

local ax = require("hs.axuielement")

---------------------------------------------------------------- 네이티브 인디케이터 플립

-- 다른 소스로 전환했다가 원래 소스로 복귀 → macOS 인디케이터가 현재 소스로 표시됨
function obj:flash()
  local now = hs.timer.secondsSinceEpoch()
  if now < (self.flipUntil or 0) then return end
  local cur = hs.keycodes.currentSourceID() or ""
  local other
  if cur:find("Korean", 1, true) or cur:find("Hangul", 1, true) then
    other = self.english
  else
    other = self.korean
  end
  -- 이 시각까지의 소스 변경 알림은 우리 플립이 낸 것이므로 '외부 전환'으로 치지 않음
  -- (버퍼를 짧게 유지해 빠른 연속 앱 전환에서도 매번 표시되게)
  self.flipUntil = now + self.flipDelay + 0.2
  hs.keycodes.currentSourceID(other)
  hs.timer.doAfter(self.flipDelay, function()
    hs.keycodes.currentSourceID(cur)
  end)
end

local function focusedElement()
  return ax.systemWideElement():attributeValue("AXFocusedUIElement")
end

-- 포커스된 요소가 텍스트 입력 가능한지 (버튼 등 비텍스트 포커스에는 플립하지 않음)
local function isTextFocused(el)
  el = el or focusedElement()
  if not el then return false end
  local ok, range = pcall(function() return el:attributeValue("AXSelectedTextRange") end)
  return ok and range ~= nil
end

-- requireText=true면 텍스트 입력 요소에 포커스가 있을 때만 플립.
-- 방금 입력소스가 '실제로' 바뀐 경우(예: InputSourceSwitch의 앱별 자동 전환)는
-- 네이티브 인디케이터가 이미 떠 있으므로 플립을 생략해 이중 깜빡임을 막는다.
function obj:_scheduleFlash(requireText)
  if self.pending then self.pending:stop() end
  local before = hs.keycodes.currentSourceID()

  local attempt
  attempt = function(isRetry)
    self.pending = nil
    -- 방금 우리 플립이 표시했으면 생략 (플립 중간에 잡힌 트리거의 오탐도 방지)
    if hs.timer.secondsSinceEpoch() < (self.flipUntil or 0) then return end
    if requireText and not isTextFocused() then return end
    if not isRetry then
      -- 외부/자동(macOS 문서별 전환, InputSourceSwitch 등) 소스 전환 직후:
      -- 인디케이터가 실제로 떴는지 알 수 없으므로(캐럿이 자리잡기 전이면 조용히 지나감)
      -- 즉시 플립하지 않고 잠시 뒤 '확인 플립' 1회로 미룬다 → 항상 표시 보장.
      local changed = hs.keycodes.currentSourceID() ~= before
      local recent = hs.timer.secondsSinceEpoch() - (self.lastExternalChange or 0) < self.suppressWindow
      if changed or recent then
        self.pending = hs.timer.doAfter(self.retryDelay, function() attempt(true) end)
        return
      end
    end
    self:flash()
  end

  self.pending = hs.timer.doAfter(self.readDelay, function() attempt(false) end)
end

---------------------------------------------------------------- 관찰자

-- 포커스가 바뀔 만한 AX 알림 전부 감시 (Electron/웹앱은 동적 필드 auto-focus 시
-- AXFocusedUIElementChanged 대신 AXLayoutChanged/AXSelectedTextChanged 등을 쏘기도 함)
local WATCH_NOTIFS = {
  "AXFocusedUIElementChanged",
  "AXSelectedTextChanged",
  "AXLayoutChanged",
  "AXFocusedWindowChanged",
}

-- 현재 활성 앱의 포커스 관련 알림 감시 (앱 전환 시마다 재부착)
function obj:_attachObserver(app)
  if self.obs then pcall(function() self.obs:stop() end); self.obs = nil end
  if not app then return end
  local ok, obs = pcall(ax.observer.new, app:pid())
  if not ok then return end
  obs:callback(function(_, _, notif)
    -- 포커스 요소가 '실제로 바뀐' 경우만 (같은 필드 안 타이핑/캐럿 이동 노이즈는 무시)
    local el = focusedElement()
    if not el then return end
    local same = false
    if obj._lastEl then pcall(function() same = (el == obj._lastEl) end) end
    if same then return end
    obj._lastEl = el
    obj:_scheduleFlash(true)
  end)
  local appEl = ax.applicationElement(app)
  local any = false
  for _, n in ipairs(WATCH_NOTIFS) do
    if pcall(function() obs:addWatcher(appEl, n) end) then any = true end
  end
  if any then pcall(function() obs:start() end); self.obs = obs end
end

-- Spotlight 닫힘 처리: 강제 전환했던 경우 이전 소스 복원 (복원 자체가 인디케이터 표시)
function obj:_spotlightClosed()
  if not self.spotlightOpen then return end
  self.spotlightOpen = false
  if self.spotlightPoll then self.spotlightPoll:stop(); self.spotlightPoll = nil end
  local prev = self.spotlightPrevSource
  self.spotlightPrevSource = nil
  -- Spotlight 안에서 사용자가 직접 소스를 바꿨다면(현재≠강제값) 그 선택을 존중
  if prev and hs.keycodes.currentSourceID() == self.spotlightForceSource then
    hs.keycodes.currentSourceID(prev)
  end
end

-- 닫힘 이벤트를 놓쳐도 복원되도록 열려 있는 동안 0.5초 간격 백업 폴링
function obj:_startSpotlightPoll()
  if self.spotlightPoll then self.spotlightPoll:stop() end
  self.spotlightPoll = hs.timer.doEvery(0.5, function()
    local sp = hs.application.get("Spotlight")
    if not (sp and #sp:allWindows() > 0) then obj:_spotlightClosed() end
  end)
end

-- Spotlight 상시 감시: 열리면 (옵션) 입력소스 강제 전환 + 이전 소스 기억, 닫히면 복원
function obj:_ensureSpotlight()
  local sp = hs.application.get("Spotlight")
  if not sp then return end
  if self.spObs and self.spotlightPid == sp:pid() then return end
  if self.spObs then pcall(function() self.spObs:stop() end); self.spObs = nil end

  local ok, obs = pcall(ax.observer.new, sp:pid())
  if not ok then return end
  obs:callback(function()
    -- 열림/닫힘 모두 이벤트가 오므로, 잠깐 뒤 창 존재 여부로 상태 전이 판단
    hs.timer.doAfter(0.05, function()
      local sp2 = hs.application.get("Spotlight")
      local isOpen = sp2 ~= nil and #sp2:allWindows() > 0
      if isOpen and not obj.spotlightOpen then
        obj.spotlightOpen = true
        if obj.spotlightForceSource then
          local cur = hs.keycodes.currentSourceID()
          if cur ~= obj.spotlightForceSource then
            obj.spotlightPrevSource = cur                          -- 닫힐 때 복원할 값
            hs.keycodes.currentSourceID(obj.spotlightForceSource)  -- 실제 전환 → 인디케이터 표시
          else
            obj.spotlightPrevSource = nil
            obj:flash()  -- 이미 강제값이면 플립으로 표시만
          end
        else
          obj:flash()
        end
        obj:_startSpotlightPoll()
      elseif not isOpen and obj.spotlightOpen then
        obj:_spotlightClosed()
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

---------------------------------------------------------------- 코너 배지 (전체화면용)

-- 전체화면 창일 때 화면 우상단에 현재 입력소스를 상시 표시. 창모드면 숨김.
function obj:_refreshCorner()
  if not self.cornerBadge then
    if self.corner then self.corner:hide() end
    return
  end
  local win = hs.window.focusedWindow()
  local fs = win and win:isFullScreen()
  if self.cornerFullscreenOnly and not fs then
    if self.corner then self.corner:hide() end
    return
  end

  local scr = (win and win:screen()) or hs.screen.mainScreen()
  local f = scr:fullFrame()
  local S = self.cornerSize
  local x = f.x + f.w - S - self.cornerMargin
  local y = f.y + self.cornerMargin
  local label = self.labelFor(hs.keycodes.currentSourceID() or "")

  if not self.corner then
    self.corner = hs.canvas.new({ x = x, y = y, w = S, h = S })
    self.corner[1] = {
      type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = S * 0.28, yRadius = S * 0.28 },
    }
    self.corner[2] = { type = "text", textAlignment = "center" }
    self.corner:level(hs.canvas.windowLevels.overlay)
    self.corner:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  end
  self.corner:topLeft({ x = x, y = y })
  self.corner:size({ w = S, h = S })
  self.corner[1].fillColor = { red = 0.07, green = 0.08, blue = 0.10, alpha = self.cornerAlpha }
  self.corner[2].text = label
  self.corner[2].textSize = S * 0.5
  self.corner[2].textColor = { hex = "#ffffff", alpha = 0.95 }
  self.corner[2].textFont = ".AppleSystemUIFontBold"
  self.corner[2].frame = { x = 0, y = S * 0.18, w = S, h = S * 0.7 }
  self.corner:show()
end

---------------------------------------------------------------- 라이프사이클

function obj:configure(opts)
  for k, v in pairs(opts or {}) do self[k] = v end
  return self
end

function obj:start()
  -- 외부(사용자 한영키, 앱별 자동 전환 등) 소스 변경 시각 기록 — 우리 플립은 flipUntil로 제외
  -- 주의: hs.keycodes.inputSourceChanged는 HS 전역 1개 슬롯이라 이 spoon이 점유함
  self._lastSeenSource = hs.keycodes.currentSourceID()
  hs.keycodes.inputSourceChanged(function()
    if hs.timer.secondsSinceEpoch() < (obj.flipUntil or 0) then return end  -- 우리 플립 중엔 무시(코너 깜빡임 방지)
    local cur = hs.keycodes.currentSourceID()
    if cur == obj._lastSeenSource then return end  -- 실제 변경만 기록 (재통지 무시)
    obj._lastSeenSource = cur
    obj.lastExternalChange = hs.timer.secondsSinceEpoch()
    obj:_refreshCorner()  -- 코너 배지 라벨 갱신
  end)

  self.appWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      obj:_attachObserver(app)
      obj:_scheduleFlash(true)  -- 텍스트 포커스가 있을 때만 (인디케이터는 캐럿이 있어야 의미)
      obj:_ensureSpotlight()           -- Spotlight 재시작 대비 재부착
    end
  end)
  self.appWatcher:start()

  -- cmd+tab 등 창 포커스 변경 커버 (앱 활성화 이벤트가 누락되는 경로 보강, 트리거는 pending으로 병합됨)
  self._winFn = function()
    obj:_scheduleFlash(true)
    obj:_refreshCorner()  -- 창/화면/전체화면 상태 바뀌었을 수 있으니 코너 갱신
  end
  self.winFilter = hs.window.filter.default
  self.winFilter:subscribe({
    hs.window.filter.windowFocused,
    hs.window.filter.windowFullscreened,
    hs.window.filter.windowUnfullscreened,
  }, self._winFn)

  self:_attachObserver(hs.application.frontmostApplication())
  self:_ensureSpotlight()
  self:_refreshCorner()
  return self
end

function obj:stop()
  pcall(function() hs.keycodes.inputSourceChanged(nil) end)
  if self.winFilter and self._winFn then
    pcall(function() self.winFilter:unsubscribe(self._winFn) end)
    self.winFilter, self._winFn = nil, nil
  end
  if self.corner then self.corner:delete(); self.corner = nil end
  if self.appWatcher then self.appWatcher:stop(); self.appWatcher = nil end
  if self.obs then pcall(function() self.obs:stop() end); self.obs = nil end
  if self.spObs then pcall(function() self.spObs:stop() end); self.spObs = nil end
  if self.spotlightPoll then self.spotlightPoll:stop(); self.spotlightPoll = nil end
  if self.pending then self.pending:stop(); self.pending = nil end
  return self
end

return obj
