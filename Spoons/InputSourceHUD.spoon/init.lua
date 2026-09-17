--- === InputSourceHUD ===
---
--- 입력 포커스가 바뀔 때(다른 필드/창/앱으로 이동) 현재 입력소스(한/A) 배지를
--- 포커스된 화면 중앙에 잠깐 표시한다. 전체화면(메뉴바 숨김)일 때는 화면 우상단에
--- 상시 코너 배지도 함께 표시한다.
---
--- 설계 노트: v1.0은 자체 캔버스 배지, v1.1은 입력소스를 잠깐 전환했다 되돌리는
--- '플립'으로 macOS 네이티브 인디케이터를 빌려 쓰는 방식이었다. 플립은 캐럿 추적이
--- 완벽한 대신 실제 소스를 두 번 바꾸는 부작용(전환 순간 타이핑 오입력 위험,
--- 외부·앱별 자동 전환과의 조율 로직 비대화)이 있어 v1.2에서 자체 배지로 복귀했다.
--- 배지 위치는 화면 중앙 고정: v1.0의 캐럿 좌표(AXBoundsForRange) 추정은
--- 웹/Electron 필드에서 자주 깨진다 — 예: Electron AXTextField가 range는 주면서
--- bounds로 퇴화 좌표 (0,33) 0×0을 반환해 배지가 화면 구석에 떴다. 앱마다 실패
--- 방식이 달라 가드로 못 막으므로, 항상 같은 자리(중앙)가 예측 가능해서 낫다
--- (macOS 지구본 입력소스 HUD와 같은 접근).
--- 한영 키·앱별 자동 전환 같은 '실제 전환'은 macOS가 네이티브 캡슐을 직접 띄우므로
--- 자체 배지를 중복 표시하지 않는다 (inputSourceChanged 훅은 코너 라벨 갱신 전용).
---
--- 트리거: 앱 활성화(항상 표시) + 포커스 UI 요소 변경(AX 알림 4종 — Electron/웹의
--- 동적 auto-focus 커버, 포커스 요소 동일성 게이트로 타이핑 노이즈 차단).
--- v1.2.2: AX 알림 콜백에서는 AX를 호출하지 않는다. AXSelectedTextChanged/AXLayoutChanged는
--- 많은 앱에서 키 입력마다 오는데, 콜백에서 매번 동기 AX 왕복을 하면 앱이 바쁠 때 HS 메인
--- 스레드가 막혀 다른 spoon의 eventtap까지 OS가 비활성화할 수 있다(한영 키 유실로 관찰됨).
--- 알림은 pending 타이머로 병합만 하고, 타이핑이 readDelay 이상 멈춘 뒤 한 번만 AX로
--- 포커스 요소를 읽어 동일성 게이트를 적용한다 — 연속 타이핑 중엔 AX 호출 0회.
--- Spotlight: 활성화 이벤트를 내지 않으므로 상시 AX 관찰자로 감지하고,
--- `spotlightForceSource`가 설정돼 있으면 열릴 때 그 소스로 전환·닫히면 복원한다.
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("InputSourceHUD")
---   spoon.InputSourceHUD:start()
---
--- 요구: 손쉬운 사용(Accessibility) 권한.
local obj = {}
obj.__index = obj

obj.name = "InputSourceHUD"
obj.version = "1.2.2"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.duration = 0.8         -- 중앙 배지 표시 시간(초)
obj.size = 64              -- 중앙 배지 한 변 크기(pt)
obj.alpha = 0.45           -- 중앙 배지 배경 불투명도 (낮을수록 투명)
obj.readDelay = 0.1        -- 포커스 이벤트 후 소스 읽기까지 지연 (앱별 자동 전환이 먼저 끝나게)
obj.spotlightForceSource = "com.apple.keylayout.ABC"    -- Spotlight 열릴 때 전환할 소스. nil이면 끔

-- 코너 배지: 전체화면(메뉴바 숨김)일 때 현재 입력소스를 화면 우상단에 상시 표시.
obj.cornerBadge = true            -- 코너 배지 사용
obj.cornerFullscreenOnly = true   -- 전체화면 창일 때만 (창모드는 메뉴바에 한/영이 보임)
obj.cornerSize = 34               -- 배지 한 변 크기(pt)
obj.cornerAlpha = 0.35            -- 배경 불투명도 (낮을수록 투명; 흰 글자 대비 확보용)
obj.cornerMargin = 8              -- 우측 여백(pt)
obj.cornerMarginTop = 8           -- 메뉴바 아래부터 재는 상단 여백(pt). 전체화면에서 메뉴바를
                                  -- 불러냈을 때 시계를 가리지 않도록 메뉴바 높이는 자동 반영됨

--- 입력소스 ID → 배지 글자 (중앙·코너 배지 공용, 커스터마이즈 가능)
function obj.labelFor(sourceID)
  if sourceID:find("Korean", 1, true) or sourceID:find("Hangul", 1, true) then return "한" end
  return "A"
end

local ax = require("hs.axuielement")

---------------------------------------------------------------- 중앙 배지

local function focusedElement()
  return ax.systemWideElement():attributeValue("AXFocusedUIElement")
end

-- 포커스된 요소가 텍스트 입력 가능한지 (버튼 등 비텍스트 포커스에는 표시하지 않음)
local function isTextFocused(el)
  el = el or focusedElement()
  if not el then return false end
  local ok, range = pcall(function() return el:attributeValue("AXSelectedTextRange") end)
  return ok and range ~= nil
end

-- 배지를 포커스 화면(없으면 메인 화면) 중앙에 그리고 duration 후 페이드아웃.
-- 표시할 때마다 새 캔버스를 만들므로 디스플레이 구성 변경으로 캔버스 창이
-- 죽는 문제(코너 배지의 screenWatcher 참고)와 무관.
function obj:_draw()
  if self.canvas then self.canvas:delete(); self.canvas = nil end
  if self.hideTimer then self.hideTimer:stop(); self.hideTimer = nil end

  local win = hs.window.focusedWindow()
  local scr = (win and win:screen()) or hs.screen.mainScreen()
  local f = scr:frame()
  local S = self.size
  local x = f.x + (f.w - S) / 2
  local y = f.y + (f.h - S) / 2
  local label = self.labelFor(hs.keycodes.currentSourceID() or "")

  local c = hs.canvas.new({ x = x, y = y, w = S, h = S })
  c[1] = {
    type = "rectangle", action = "fill",
    fillColor = { red = 0.07, green = 0.08, blue = 0.10, alpha = self.alpha },
    roundedRectRadii = { xRadius = S * 0.22, yRadius = S * 0.22 },
  }
  c[2] = {
    type = "text", text = label,
    textSize = S * 0.5, textColor = { hex = "#e6edf3" }, textAlignment = "center",
    textFont = ".AppleSystemUIFontBold",
  }
  -- 글자 세로 '광학' 중앙 정렬: 라인박스를 그대로 가운데 두면 글자가 안 쓰는
  -- 디센더 공간(baseline 아래) 때문에 글자가 위로 치우쳐 배지가 세로로 길어 보인다.
  -- 글리프 몸통(capHeight, 한글 몸통도 유사)이 중앙에 오도록 baseline을
  -- (S+capHeight)/2에 배치 — 프레임 상단에서 baseline까지가 ascender이므로 역산.
  local fi = hs.styledtext.fontInfo({ name = ".AppleSystemUIFontBold", size = S * 0.5 })
  local y2 = (S + fi.capHeight) / 2 - fi.ascender
  c[2].frame = { x = 0, y = y2, w = S, h = fi.ascender - fi.descender + 2 }
  c:level(hs.canvas.windowLevels.overlay)
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:show()
  self.canvas = c
  self.hideTimer = hs.timer.doAfter(self.duration, function()
    if self.canvas then self.canvas:delete(0.15); self.canvas = nil end
  end)
end

-- requireText=true면 텍스트 입력 요소에 포커스가 있을 때만 표시 (버튼 등 비텍스트 포커스엔 안 뜸).
-- gateSameEl=true면 포커스 요소가 직전 표시 때와 같으면 표시하지 않음 (AX 알림용 — 같은 필드 안
-- 타이핑/캐럿 이동 노이즈 차단). 이 판정은 타이머 안에서 하므로 콜백 시점엔 AX 호출이 없다.
-- 짧은 시간 내 중복 트리거(앱 활성화 + 창 포커스 + AX 알림)는 pending 하나로 병합하되,
-- 하나라도 '항상 표시'(requireText=false / gateSameEl=false)면 그쪽을 따른다 — 앱 전환 표시가 게이트에 먹히지 않게.
function obj:_scheduleShow(requireText, gateSameEl)
  if self.pending then
    self.pending:stop()
    requireText = requireText and self._pendingRequireText
    gateSameEl = gateSameEl and self._pendingGate
  end
  self._pendingRequireText = requireText
  self._pendingGate = gateSameEl
  self.pending = hs.timer.doAfter(self.readDelay, function()
    self.pending = nil
    if requireText then
      local el = focusedElement()
      if not el then return end
      if gateSameEl then
        local same = false
        pcall(function() same = (el == self._lastEl) end)
        if same then return end
      end
      self._lastEl = el
      if not isTextFocused(el) then return end
    end
    self:_draw()
  end)
end

--- 수동/테스트용 즉시 표시
function obj:show()
  self:_scheduleShow(false)
  return self
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
  obs:callback(function()
    -- 여기서 AX를 호출하지 않는다 (키 입력마다 오는 알림 — 설계 노트 v1.2.2 참고).
    -- 병합 타이머 안에서 포커스 요소를 한 번 읽어 '실제로 바뀐' 경우만 표시한다.
    obj:_scheduleShow(true, true)
  end)
  local appEl = ax.applicationElement(app)
  local any = false
  for _, n in ipairs(WATCH_NOTIFS) do
    if pcall(function() obs:addWatcher(appEl, n) end) then any = true end
  end
  if any then pcall(function() obs:start() end); self.obs = obs end
end

-- Spotlight 닫힘 처리: 강제 전환했던 경우 이전 소스 복원
-- (복원은 실제 전환이므로 macOS 네이티브 캡슐이 현재 캐럿 위치에 표시됨)
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

-- Spotlight 상시 감시: 열리면 (옵션) 입력소스 강제 전환 + 이전 소스 기억 + 배지 표시, 닫히면 복원
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
            hs.keycodes.currentSourceID(obj.spotlightForceSource)  -- 실제 전환 (네이티브 캡슐도 뜸)
          else
            obj.spotlightPrevSource = nil
          end
        end
        obj:_scheduleShow(false)  -- 전환 여부와 무관하게 자체 배지 표시
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
  -- x는 fullFrame(오른쪽 끝은 메뉴바 유무와 무관), y는 frame(메뉴바 제외 영역) 기준.
  -- 전체화면에서 커서를 올려 메뉴바가 내려와도 시계/메뉴 아이콘을 가리지 않는다
  -- (노치 모델처럼 메뉴바가 두꺼운 화면에도 자동으로 맞는다).
  local x = f.x + f.w - S - self.cornerMargin
  local y = scr:frame().y + self.cornerMarginTop
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
  -- 실제 전환(한영 키, 앱별 자동 전환 등)은 macOS가 네이티브 캡슐을 직접 띄우므로
  -- 여기서는 코너 배지 라벨만 갱신한다.
  -- 주의: hs.keycodes.inputSourceChanged는 HS 전역 1개 슬롯이라 이 spoon이 점유함
  self._lastSeenSource = hs.keycodes.currentSourceID()
  hs.keycodes.inputSourceChanged(function()
    local cur = hs.keycodes.currentSourceID()
    if cur == obj._lastSeenSource then return end  -- 실제 변경만 반응 (재통지 무시)
    obj._lastSeenSource = cur
    obj:_refreshCorner()  -- 코너 배지 라벨 갱신
  end)

  self.appWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      obj:_attachObserver(app)
      obj:_scheduleShow(false)  -- 앱 전환은 항상 표시 (비텍스트 포커스라도)
      obj:_ensureSpotlight()    -- Spotlight 재시작 대비 재부착
    end
  end)
  self.appWatcher:start()

  -- cmd+tab 등 창 포커스 변경 커버 (앱 활성화 이벤트가 누락되는 경로 보강, 트리거는 pending으로 병합됨)
  self._winFn = function()
    obj:_scheduleShow(true)
    obj:_refreshCorner()  -- 창/화면/전체화면 상태 바뀌었을 수 있으니 코너 갱신
  end
  self.winFilter = hs.window.filter.default
  self.winFilter:subscribe({
    hs.window.filter.windowFocused,
    hs.window.filter.windowFullscreened,
    hs.window.filter.windowUnfullscreened,
  }, self._winFn)

  -- 디스플레이 구성 변경(모니터 연결/해제) 시 코너 캔버스 재생성.
  -- 기존 캔버스 창은 사라진 화면에 묶여 isShowing()=true인 채 렌더링만 멈춘
  -- 좀비가 될 수 있고(이동·show()로는 복구 불가), 파괴 후 재생성만이 복구 수단.
  -- 재구성 직후는 화면·포커스 상태가 유동적이라 잠시 뒤에 갱신한다 (연속 발화 병합).
  self.screenWatcher = hs.screen.watcher.new(function()
    if obj.corner then obj.corner:delete(); obj.corner = nil end
    if obj.screenSettle then obj.screenSettle:stop() end
    obj.screenSettle = hs.timer.doAfter(1.0, function()
      obj.screenSettle = nil
      obj:_refreshCorner()
    end)
  end)
  self.screenWatcher:start()

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
  if self.screenWatcher then self.screenWatcher:stop(); self.screenWatcher = nil end
  if self.screenSettle then self.screenSettle:stop(); self.screenSettle = nil end
  if self.corner then self.corner:delete(); self.corner = nil end
  if self.canvas then self.canvas:delete(); self.canvas = nil end
  if self.hideTimer then self.hideTimer:stop(); self.hideTimer = nil end
  if self.appWatcher then self.appWatcher:stop(); self.appWatcher = nil end
  if self.obs then pcall(function() self.obs:stop() end); self.obs = nil end
  if self.spObs then pcall(function() self.spObs:stop() end); self.spObs = nil end
  if self.spotlightPoll then self.spotlightPoll:stop(); self.spotlightPoll = nil end
  if self.pending then self.pending:stop(); self.pending = nil end
  return self
end

return obj
