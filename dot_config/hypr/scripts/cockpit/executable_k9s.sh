#!/usr/bin/env bash
# cockpit/k9s.sh — spawn k9s on next workspace; cwd-agnostic.
set -eu

CURRENT=$(hyprctl activeworkspace -j | jq -r '.id')
WS=$((CURRENT + 1))
hyprctl dispatch exec "[workspace $WS silent] kitty -e k9s"
sleep 0.3
hyprctl dispatch workspace "$WS"
notify-send "Cockpit · k9s" "ws$WS"
