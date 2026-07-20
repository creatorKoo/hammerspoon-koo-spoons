--- === AppFocus ===
---
--- ⌥R(오른쪽 option) 홀드 = 앱 전환 레이어.
--- 글자 키 → 이름의 단어 중 하나가 그 글자로 시작하는(표시명·디스크명, shift 무시) '실행중' 앱으로
--- 포커스 이동 (예: "Google Chrome"은 g·c 둘 다 매칭),
--- 이미 그 앱이면 다음 후보로 순환(알파벳 링). 매칭되는 실행중 앱이 없으면 아무 동작 안 함
--- (앱 실행 기능 없음 — 순수 전환기). 홀드하는 동안 실시간 후보 목록 오버레이 표시 (빈도순).
---
--- 사용 예 (~/.hammerspoon/init.lua):
---   hs.loadSpoon("AppFocus")
---   spoon.AppFocus:start()
---   -- 선택: 첫 글자가 다른 앱을 특정 키의 순환에 포함시키려면
---   -- spoon.AppFocus:configure({ keys = { c = { "Google Chrome" } } }):start()
---
--- 설계 노트:
---   · 레이어 여부는 상태 변수가 아니라 각 이벤트의 raw flags(NX_DEVICERALTKEYMASK)로
---     판정 — key-up 유실에도 stuck 상태가 생길 수 없음.
---   · eventtap 콜백이 느리면 OS가 탭을 비활성화하므로 실제 작업은 hs.timer.doAfter(0, ...)로.
local obj = {}
obj.__index = obj

obj.name = "AppFocus"
obj.version = "1.1.0"
obj.author = "GooBeom Jeoung"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- 설정 (configure로 덮어쓰기)
obj.keys = {}                  -- (선택) 글자 → 추가 매칭 별칭. 실행 기능은 없음 — 매칭 확장 전용. 소문자 키만
obj.overlayMaxLines = 14       -- 오버레이 최대 줄 수
obj.statePath = os.getenv("HOME") .. "/.local/state/app-focus/usage.json"

local etypes = hs.eventtap.event.types
local eprops = hs.eventtap.event.properties

local RIGHT_ALT_KC = 61     -- hs.keycodes.map.rightalt
local RIGHT_ALT_BIT = 0x40  -- NX_DEVICERALTKEYMASK

local usage = { apps = {}, seq = 0 }
local overlayCanvas, overlayTimer
local letterByCode = {}
local swallowedUp = {}      -- 삼킨 keyDown의 keyUp도 짝 맞춰 삼킴 (고아 keyUp 방지)

---------------------------------------------------------------- 최근 사용 순번

-- usage.apps[bundleId] = 단조 증가 순번(seq). 값이 클수록 최근에 사용. usage.seq = 최댓값.
local function loadUsage()
  local ok, data = pcall(hs.json.read, obj.statePath)
  if ok and type(data) == "table" then
    usage.apps = data.apps or {}
    usage.seq = data.seq or 0
    for _, v in pairs(usage.apps) do  -- 구 형식(횟수) 마이그레이션: 최댓값에서 이어받음
      if type(v) == "number" and v > usage.seq then usage.seq = v end
    end
  end
end

local function saveUsage()
  local dir = obj.statePath:match("(.+)/[^/]+$")
  local acc = ""
  for seg in dir:gmatch("[^/]+") do
    acc = acc .. "/" .. seg
    hs.fs.mkdir(acc)
  end
  hs.json.write(usage, obj.statePath, true, true)
end

local function seqOf(appId)
  return usage.apps[appId] or 0
end

local function bump(appId)
  usage.seq = usage.seq + 1
  usage.apps[appId] = usage.seq
  saveUsage()
end

---------------------------------------------------------------- 후보 계산

-- /Applications/iTerm.app → "iTerm" (영문 디스크 이름 — 한국어 로케일의 표시명과 별개)
local function diskName(app)
  local p = app:path()
  return p and p:match("([^/]+)%.app$") or nil
end

-- 이름의 각 단어 첫 글자(a–z만) 집합을 set에 누적. "Google Chrome" → {g=true, c=true}
local function wordInitials(s, set)
  set = set or {}
  for word in (s or ""):lower():gmatch("%S+") do
    local ch = word:sub(1, 1)
    if ch:match("%l") then set[ch] = true end
  end
  return set
end

--- key: "i"(소문자) 또는 "I"(shift 변형). 실행중 후보를 최근 사용순(미사용은 알파벳순)으로 반환.
function obj:candidatesFor(key)
  local letter = key:lower()
  local aliases = {}
  for _, name in ipairs(self.keys[key] or {}) do aliases[name:lower()] = true end

  local out, seen = {}, {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 then  -- Dock에 뜨는 일반 GUI 앱만
      local disk = diskName(app)
      local name = app:name() or ""
      local dl, nl = (disk or ""):lower(), name:lower()
      local id = app:bundleID() or disk or name
      local initials = wordInitials(dl)
      wordInitials(nl, initials)
      local match = initials[letter] or aliases[dl] or aliases[nl]
      if match and id ~= "" and not seen[id] then
        seen[id] = true
        out[#out + 1] = { app = app, disk = disk or name, name = name, id = id }
      end
    end
  end
  -- 최근 사용순(seq 내림차순), 미사용끼리는 알파벳순
  table.sort(out, function(a, b)
    local sa, sb = seqOf(a.id), seqOf(b.id)
    if sa ~= sb then return sa > sb end
    return a.disk:lower() < b.disk:lower()
  end)
  return out
end

---------------------------------------------------------------- 전환

local function activate(cand)
  if not cand.app:activate(true) then
    -- macOS 14+ 협조적 활성화가 거부하는 드문 경우 LaunchServices 경로로 폴백
    hs.application.open(cand.app:path() or cand.disk)
  end
end

-- 진입 = 최근 사용순 1위로, 연속 = 순환. 순환 순서는 '진입 시점의 최근순'을 스냅샷으로
-- 고정한 링을 따른다 (활성화할 때마다 seq가 바뀌어도 순서가 흔들려 핑퐁하지 않도록).
function obj:handleKey(key)
  local cands = self:candidatesFor(key)  -- 최근 사용순
  if #cands == 0 then return end         -- 매칭되는 실행중 앱 없음 → no-op

  local byId = {}
  for _, c in ipairs(cands) do byId[c.id] = c end

  local front = hs.application.frontmostApplication()
  local frontId
  if front then
    for _, c in ipairs(cands) do
      if c.app:pid() == front:pid() then frontId = c.id; break end
    end
  end

  local ring = self._ring
  local continuing = ring and ring.key == key and frontId and ring.ids[ring.pos] == frontId

  local target
  if continuing then
    -- 고정된 링에서 아직 실행중인 '다음' 후보로 (순환)
    local n = #ring.ids
    for step = 1, n do
      local p = ((ring.pos - 1 + step) % n) + 1
      local c = byId[ring.ids[p]]
      if c then ring.pos = p; target = c; break end
    end
  end

  if not target then
    -- 새 진입: 현재 최근순으로 링 스냅샷을 새로 뜬다
    local ids = {}
    for i, c in ipairs(cands) do ids[i] = c.id end
    self._ring = { key = key, ids = ids, pos = 1 }
    if frontId then
      -- 이미 이 글자 후보를 보는 중(예: 클릭으로 진입) → 그 다음으로 (순환 시작)
      local fp = 1
      for i, id in ipairs(ids) do if id == frontId then fp = i; break end end
      self._ring.pos = (fp % #ids) + 1
    end
    target = byId[ids[self._ring.pos]]
  end

  activate(target)
  bump(target.id)
  if overlayCanvas then self:showOverlay() end  -- 홀드 중이면 목록 갱신
end

---------------------------------------------------------------- 오버레이

local COLORS = {
  bg      = { red = 0.07, green = 0.08, blue = 0.10, alpha = 0.93 },
  header  = { hex = "#8b949e" },
  key     = { hex = "#7aa2f7" },
  running = { hex = "#e6edf3" },
  stopped = { hex = "#6e7681" },
  front   = { hex = "#7ee787" },
  sep     = { hex = "#484f58" },
}

-- 폭 계산용: Menlo(모노스페이스) 기준 문자 단위 폭. ASCII=1, 그 외(한글 등)=1.7
local function textUnits(s)
  local u = 0
  for _, cp in utf8.codes(s) do u = u + (cp < 128 and 1 or 1.7) end
  return u
end

-- 줄 구성: 매핑된 키 전부 + (동적) 실행중 앱의 첫 글자. 최근 사용순 정렬.
local function overlayText()
  local rows, added = {}, {}
  local function addRow(key)
    if added[key] then return end
    added[key] = true
    local cands = obj:candidatesFor(key)  -- 최근 사용순
    local aliases = obj.keys[key] or {}
    if #cands == 0 and #aliases == 0 then return end
    -- 줄의 최근성 = 후보 중 가장 최근 사용 seq (없으면 0)
    local n = 0
    for _, c in ipairs(cands) do local s = seqOf(c.id); if s > n then n = s end end
    rows[#rows + 1] = { key = key, cands = cands, aliases = aliases, n = n }
  end

  local sortedKeys = {}
  for k in pairs(obj.keys) do sortedKeys[#sortedKeys + 1] = k end
  table.sort(sortedKeys)
  for _, k in ipairs(sortedKeys) do addRow(k) end
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 then
      local initials = wordInitials(diskName(app))
      wordInitials(app:name(), initials)
      for ch in pairs(initials) do addRow(ch) end
    end
  end

  table.sort(rows, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    local al, bl = a.key:lower(), b.key:lower()
    if al ~= bl then return al < bl end
    return a.key < b.key
  end)
  local max = obj.overlayMaxLines
  while #rows > max do table.remove(rows) end

  local front = hs.application.frontmostApplication()
  local frontPid = front and front:pid() or -1
  local body = { name = "Menlo", size = 15 }

  local st = hs.styledtext.new("앱 전환",
    { font = { name = "Menlo-Bold", size = 12 }, color = COLORS.header })
  local maxUnits = 0
  for _, row in ipairs(rows) do
    -- 표시 항목 구성: 실행중 후보 + 매핑됐지만 미실행인 별칭(회색)
    local items, runningSet = {}, {}
    for _, c in ipairs(row.cands) do
      runningSet[c.disk:lower()] = true
      local isFront = c.app:pid() == frontPid
      items[#items + 1] = {
        text = (isFront and "▸" or "") .. c.disk,
        color = isFront and COLORS.front or COLORS.running,
      }
    end
    for _, a in ipairs(row.aliases) do
      if not runningSet[a:lower()] then
        items[#items + 1] = { text = a, color = COLORS.stopped }
      end
    end
    -- 가장 긴 줄 추적 (동적 폭 계산용)
    local plain = " " .. row.key .. "  "
    for i, it in ipairs(items) do
      plain = plain .. (i > 1 and " · " or "") .. it.text
    end
    maxUnits = math.max(maxUnits, textUnits(plain))
    -- 렌더링
    st = st .. hs.styledtext.new("\n " .. row.key .. "  ",
      { font = { name = "Menlo-Bold", size = 15 }, color = COLORS.key })
    for i, it in ipairs(items) do
      if i > 1 then st = st .. hs.styledtext.new(" · ", { font = body, color = COLORS.sep }) end
      st = st .. hs.styledtext.new(it.text, { font = body, color = it.color })
    end
  end
  return st, #rows, maxUnits
end

function obj:hideOverlay()
  if overlayTimer then overlayTimer:stop(); overlayTimer = nil end
  if overlayCanvas then overlayCanvas:delete(); overlayCanvas = nil end
end

function obj:showOverlay()
  self:hideOverlay()
  local st, nRows, maxUnits = overlayText()
  if nRows == 0 then return end

  local sf = hs.screen.mainScreen():frame()
  -- 폭 = 가장 긴 줄 기준 (Menlo 15pt 문자폭 ≈ 9px) + 좌우 패딩, 화면 폭 80% 상한
  local W = math.min(math.max(math.ceil(maxUnits * 9) + 44, 340), math.floor(sf.w * 0.8))
  local H = 14 + 20 + nRows * 23 + 16
  overlayCanvas = hs.canvas.new({
    x = sf.x + (sf.w - W) / 2, y = sf.y + sf.h * 0.26, w = W, h = H,
  })
  overlayCanvas[1] = {
    type = "rectangle", action = "fill",
    fillColor = COLORS.bg,
    roundedRectRadii = { xRadius = 14, yRadius = 14 },
  }
  overlayCanvas[2] = {
    type = "text", text = st,
    frame = { x = 22, y = 14, w = W - 44, h = H - 24 },
  }
  overlayCanvas:level(hs.canvas.windowLevels.overlay)
  overlayCanvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  overlayCanvas:show()
  overlayTimer = hs.timer.doAfter(20, function() obj:hideOverlay() end)  -- key-up 유실 워치독
end

---------------------------------------------------------------- Spoon 라이프사이클

local function rebuildLetterMap()
  letterByCode = {}
  for c = string.byte("a"), string.byte("z") do
    local l = string.char(c)
    local code = hs.keycodes.map[l]
    if code then letterByCode[code] = l end
  end
end

--- 설정 병합 (keys, overlayMaxLines, statePath). self 반환 → 체이닝 가능.
function obj:configure(opts)
  for k, v in pairs(opts or {}) do self[k] = v end
  local normalized = {}  -- 별칭 키는 소문자로 정규화 (대소문자 구분 없음)
  for k, v in pairs(self.keys) do normalized[k:lower()] = v end
  self.keys = normalized
  return self
end

function obj:start()
  loadUsage()
  rebuildLetterMap()

  self.flagsTap = hs.eventtap.new({ etypes.flagsChanged }, function(e)
    if e:getKeyCode() ~= RIGHT_ALT_KC then return false end
    local raw = e:getRawEventData().CGEventData.flags
    if (raw & RIGHT_ALT_BIT) ~= 0 then
      -- 레이어 진입 시마다 재생성 (O(26)) — 전역 1슬롯인 inputSourceChanged 콜백을
      -- 점유하지 않아 InputMethodIndicator 같은 다른 spoon과 공존 가능
      rebuildLetterMap()
      hs.timer.doAfter(0, function() obj:showOverlay() end)
    else
      hs.timer.doAfter(0, function() obj:hideOverlay() end)
    end
    return false  -- option 플래그는 통과 (⌥R 자체는 앱에 무해)
  end)

  self.keyTap = hs.eventtap.new({ etypes.keyDown }, function(e)
    local raw = e:getRawEventData().CGEventData.flags
    if (raw & RIGHT_ALT_BIT) == 0 then return false end  -- 오른쪽 option 홀드 아님 → 통과
    local letter = letterByCode[e:getKeyCode()]
    if not letter then return false end                  -- 화살표 등 글자 외 키는 통과
    if e:getProperty(eprops.keyboardEventAutorepeat) ~= 0 then return true end
    local key = letter  -- shift 무시 (대소문자 구분 없음)
    swallowedUp[e:getKeyCode()] = true
    hs.timer.doAfter(0, function() obj:handleKey(key) end)
    return true  -- 앱에 ⌥글자 미전달
  end)

  self.keyUpTap = hs.eventtap.new({ etypes.keyUp }, function(e)
    local kc = e:getKeyCode()
    if swallowedUp[kc] then swallowedUp[kc] = nil; return true end
    return false
  end)

  self.flagsTap:start()
  self.keyTap:start()
  self.keyUpTap:start()
  return self
end

function obj:stop()
  for _, tap in ipairs({ self.flagsTap, self.keyTap, self.keyUpTap }) do
    if tap then tap:stop() end
  end
  self.flagsTap, self.keyTap, self.keyUpTap = nil, nil, nil
  self:hideOverlay()
  return self
end

return obj
