-- ~/.hammerspoon/init.lua — 개인 설정 (git 밖, 로컬 관리)

require("hs.ipc")
pcall(hs.ipc.cliInstall, "/opt/homebrew")  -- 터미널 `hs` CLI

hs.autoLaunch(true)
hs.automaticallyCheckForUpdates(true)
hs.dockIcon(false)

---------------------------------------------------------------- 내 spoon (repo 링크)

-- ⌥R(오른쪽 option) 홀드 + 글자 = 이름의 단어가 그 글자로 시작하는 실행중 앱 전환/순환.
-- shift 무시, 매칭 없으면 no-op (앱 실행은 별도 수단 사용).
hs.loadSpoon("AppFocus")
spoon.AppFocus:start()

-- 오른쪽 command = 전용 한/영 키 (modifier 기능 제거 — 빠른 타이핑 안전)
hs.loadSpoon("HangulToggle")
spoon.HangulToggle:start()

-- 입력 포커스가 바뀔 때 캐럿 근처에 현재 입력소스(한/A) 배지 표시 + Spotlight 열리면 영문 전환
hs.loadSpoon("InputSourceHUD")
spoon.InputSourceHUD:start()

-- 지정 앱 창이 열릴 때 메인 모니터 가용 영역(메뉴바·Dock 제외)에 맞춰 자동 리사이즈.
-- 왼쪽엔 Stage Manager 스트립이 반쯤 보이게 여백 유지 (leftInset으로 튜닝)
hs.loadSpoon("WindowFit")
spoon.WindowFit:configure({ apps = { "Citrix Viewer" } }):start()

---------------------------------------------------------------- 공식 spoon (SpoonInstall 관리)

hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.use_syncinstall = true  -- 선언 즉시 동기 설치
local Install = spoon.SpoonInstall

-- 앱 전환 시 입력소스 자동 변경: iTerm 포커스 → 영문 (Spotlight는 InputSourceHUD가 담당)
Install:andUse("InputSourceSwitch", {
  fn = function(s)
    s:setApplications({
      ["iTerm2"] = "ABC",
    })
  end,
  start = true,
})

-- 포커스 변경 시 마우스를 해당 창 중앙으로 이동
Install:andUse("MouseFollowsFocus", { start = true })

---------------------------------------------------------------- 공통

-- 손쉬운 사용 권한이 없으면 키 감지(eventtap)가 동작하지 않음
if not hs.accessibilityState(true) then
  hs.alert.show("Hammerspoon: 손쉬운 사용 권한 허용 후 Reload Config", 6)
end

-- *.lua 저장 시 자동 리로드 (개인 설정 + spoon 개발 경로)
local watchDirs = {
  hs.configdir,
  os.getenv("HOME") .. "/Documents/repo/hammerspoon-koo-spoons/Spoons",  -- spoon 소스 repo
}
ConfigWatchers = {}
for _, dir in ipairs(watchDirs) do
  ConfigWatchers[#ConfigWatchers + 1] = hs.pathwatcher.new(dir, function(files)
    for _, f in ipairs(files) do
      if f:match("%.lua$") then hs.reload(); return end
    end
  end):start()
end

hs.alert.show("HS 설정 로드 ✓", 1.0)
