#!/bin/bash
# hammerspoon-spoons 설치.
#   1) Hammerspoon 설치 (없으면 brew cask)
#   2) ~/.hammerspoon/Spoons/ 에 이 repo의 spoon들을 심볼릭 링크
#      (~/.hammerspoon 자체는 로컬 디렉토리 — repo와 분리, 서드파티 spoon과 안 섞임)
#   3) ~/.hammerspoon/init.lua 없으면 examples/init.lua 복사 (개인 설정 시작점)
#   4) Karabiner 룰 비활성화 (삭제 아님 — enabled:false, 백업 생성)
# 롤백: ./uninstall.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
KARABINER_JSON="$HOME/.config/karabiner/karabiner.json"

if [ ! -d /Applications/Hammerspoon.app ]; then
  echo "==> Hammerspoon 설치"
  brew install --cask hammerspoon
fi

# 구버전(디렉토리 전체 심볼릭 링크) 정리
if [ -L "$HOME/.hammerspoon" ]; then
  rm "$HOME/.hammerspoon"
  echo "==> 구버전 ~/.hammerspoon 디렉토리 링크 제거"
fi

mkdir -p "$HOME/.hammerspoon/Spoons"
for spoon in "$REPO"/Spoons/*.spoon; do
  name="$(basename "$spoon")"
  ln -sfn "$spoon" "$HOME/.hammerspoon/Spoons/$name"
  echo "==> Spoons/$name 링크"
done

if [ ! -f "$HOME/.hammerspoon/init.lua" ]; then
  cp "$REPO/examples/init.lua" "$HOME/.hammerspoon/init.lua"
  echo "==> ~/.hammerspoon/init.lua 생성 (예시 복사 — 키 매핑은 이 파일에서 수정)"
fi

if [ -f "$KARABINER_JSON" ]; then
  if /usr/bin/jq -e '[.profiles[] | select(.selected == true) | .complex_modifications.rules[]? | select(.enabled != false)] | length > 0' "$KARABINER_JSON" >/dev/null; then
    cp "$KARABINER_JSON" "$KARABINER_JSON.pre-hammerspoon.bak"
    tmp="$(mktemp "$HOME/.config/karabiner/karabiner.json.XXXXXX")"
    /usr/bin/jq '.profiles |= map(if .selected == true then (.complex_modifications.rules |= map(. + {"enabled": false})) else . end)' \
      "$KARABINER_JSON" > "$tmp"
    mv "$tmp" "$KARABINER_JSON"   # 같은 디렉토리 rename → Karabiner가 자동 리로드
    echo "==> Karabiner 룰 비활성화 (백업: karabiner.json.pre-hammerspoon.bak)"
  fi
fi

mkdir -p "$HOME/.local/state/app-focus"

if pgrep -xq Hammerspoon; then
  echo "==> Hammerspoon 실행 중 — 메뉴바 아이콘 → Reload Config (또는: hs -c 'hs.reload()')"
else
  open -a Hammerspoon
fi

echo ""
echo "완료. 처음 설치라면:"
echo "  시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → Hammerspoon 허용 → Reload Config"
