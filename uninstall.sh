#!/bin/bash
# 롤백: 이 repo의 spoon 링크 제거. --karabiner 를 주면 install.sh --karabiner 가 끈 룰도 재활성화.
# (~/.hammerspoon/init.lua 와 Hammerspoon 앱은 남김 — 완전 제거: brew uninstall --cask hammerspoon)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
KARABINER_JSON="$HOME/.config/karabiner/karabiner.json"
DO_KARABINER=0
for arg in "$@"; do
  case "$arg" in
    --karabiner) DO_KARABINER=1 ;;
    *) echo "알 수 없는 옵션: $arg (사용: ./uninstall.sh [--karabiner])" >&2; exit 2 ;;
  esac
done

if [ "$DO_KARABINER" = 1 ] && [ -f "$KARABINER_JSON" ]; then
  cp "$KARABINER_JSON" "$KARABINER_JSON.pre-rollback.bak"
  tmp="$(mktemp "$HOME/.config/karabiner/karabiner.json.XXXXXX")"
  /usr/bin/jq '.profiles |= map(.complex_modifications.rules |= map(del(.enabled)))' \
    "$KARABINER_JSON" > "$tmp"
  mv "$tmp" "$KARABINER_JSON"
  echo "==> Karabiner 룰 재활성화 (enabled 플래그 제거)"
fi

for spoon in "$REPO"/Spoons/*.spoon; do
  link="$HOME/.hammerspoon/Spoons/$(basename "$spoon")"
  if [ -L "$link" ]; then
    rm "$link"
    echo "==> $link 제거"
  fi
done

echo "롤백 완료. (~/.hammerspoon/init.lua 의 loadSpoon 줄은 직접 정리 필요)"
