--- === WindowFit ===
---
--- 지정한 앱의 창이 **생성될 때**, 메인(primary) 모니터의 가용 영역(메뉴바·Dock 제외)에
--- 맞춰 크기·위치를 자동 조정한다. 왼쪽에는 Stage Manager 스트립이 반쯤 보이도록
--- 여백(leftInset)을 남긴다. macOS 전체화면이 아닌 "큰 일반 창"을 만드는 것이 목적.
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("WindowFit")
---   spoon.WindowFit:configure({ apps = { "Citrix Viewer" } }):start()
---
--- 건드리지 않는 경우: 메인 모니터 밖의 창 / macOS 전체화면 창 / 비표준 창(팝업·시트).
--- 적용은 창 생성 시 1회뿐 — 이후 사용자의 수동 리사이즈는 존중한다.
--- 지금 떠 있는 창을 일괄 정리하려면: hs -c 'spoon.WindowFit:applyAll()'
---
--- 설계 노트:
---   · 감지는 hs.window.filter(windowCreated) — Citrix Viewer는 hs.application:allWindows()
---     (AX 앱 요소 경유)로는 창을 아예 노출하지 않아 window.filter가 유일한 안정 경로.
---     setCurrentSpace(nil)로 다른 스페이스의 창도 추적한다.
---   · 창 생성 직후 저장된 지오메트리를 스스로 복원하는 앱(Citrix가 그럼)을 덮어쓰도록
---     applyDelay 후 적용하고, 1초 뒤 프레임이 목표에서 벗어나 있으면 딱 1회만 재적용한다
---     (그 뒤의 변경은 사용자 조작으로 보고 존중).
---   · setFrame 후 실제 프레임은 1px쯤 어긋날 수 있어(Citrix가 세션 해상도에 맞춰 스냅)
---     재적용 판정은 tolerance(기본 2px)로 비교한다.
local obj = {}
obj.__index = obj

obj.name = "WindowFit"
obj.version = "1.0.0"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.apps = {}          -- 대상 앱 이름 목록 (예: { "Citrix Viewer" }) — 개인 설정에서 주입
obj.leftInset = 75     -- 왼쪽 여백(px) — Stage Manager 스트립이 반쯤 보이는 값으로 튜닝
obj.applyDelay = 0.3   -- 창 생성 → 적용까지 지연(초). 앱 자체의 크기 복원이 먼저 끝나게
obj.tolerance = 2      -- 재적용 판정 시 목표 프레임과의 허용 오차(px)

---------------------------------------------------------------- 프레임 계산/적용

-- 목표 프레임: 메인 모니터 frame()(메뉴바·Dock 제외 가용 영역)에서 왼쪽만 leftInset 들여쓰기
function obj:_targetFrame(primary)
  local f = (primary or hs.screen.primaryScreen()):frame()
  return hs.geometry.rect(f.x + self.leftInset, f.y, f.w - self.leftInset, f.h)
end

local function near(a, b, tol)
  return math.abs(a - b) <= tol
end

function obj:_matchesTarget(frame, target)
  return near(frame.x, target.x, self.tolerance) and near(frame.y, target.y, self.tolerance)
     and near(frame.w, target.w, self.tolerance) and near(frame.h, target.h, self.tolerance)
end

-- 스킵 규칙 통과 시 목표 프레임 적용. 실제로 적용했으면 true.
-- 창이 이미 닫혔거나 AX가 거부해도 죽지 않도록 pcall (Citrix AX는 특이함)
function obj:_apply(w)
  local applied = false
  pcall(function()
    if not w:isStandard() or w:isFullScreen() then return end
    local primary = hs.screen.primaryScreen()
    if w:screen():id() ~= primary:id() then return end
    w:setFrame(self:_targetFrame(primary), 0)  -- 애니메이션 없이 즉시
    applied = true
  end)
  return applied
end

-- 생성된 창: applyDelay 후 적용 + 1초 뒤 한 번만 확인/재적용
function obj:_scheduleApply(w)
  local t1, t2
  t1 = hs.timer.doAfter(self.applyDelay, function()
    self._timers[t1] = nil
    if not self:_apply(w) then return end
    t2 = hs.timer.doAfter(1.0, function()
      self._timers[t2] = nil
      local ok, cur = pcall(function() return w:frame() end)
      if ok and cur and not self:_matchesTarget(cur, self:_targetFrame()) then
        self:_apply(w)
      end
    end)
    self._timers[t2] = true
  end)
  self._timers[t1] = true
end

--- 지금 떠 있는 대상 앱 창 전부에 즉시 적용 (스킵 규칙 동일) — 테스트/일괄 정리용
function obj:applyAll()
  if not self._wf then return self end
  for _, w in ipairs(self._wf:getWindows()) do self:_apply(w) end
  return self
end

---------------------------------------------------------------- 라이프사이클

function obj:configure(opts)
  for k, v in pairs(opts or {}) do self[k] = v end
  return self
end

function obj:start()
  self:stop()
  self._timers = {}
  if #self.apps == 0 then
    print("[WindowFit] apps가 비어 있음 — configure({ apps = {...} }) 후 start()")
    return self
  end
  local wf = hs.window.filter.new(false)   -- 빈 필터에서 대상 앱만 추가 (전역 추적 오버헤드 회피)
  for _, name in ipairs(self.apps) do wf:setAppFilter(name, true) end
  wf:setCurrentSpace(nil)                  -- 다른 스페이스의 창도 추적
  wf:subscribe(hs.window.filter.windowCreated, function(w) obj:_scheduleApply(w) end)
  self._wf = wf
  return self
end

function obj:stop()
  if self._wf then
    pcall(function() self._wf:unsubscribeAll() end)
    self._wf = nil
  end
  for t in pairs(self._timers or {}) do pcall(function() t:stop() end) end
  self._timers = {}
  return self
end

return obj
