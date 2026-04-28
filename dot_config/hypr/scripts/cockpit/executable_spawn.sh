#!/usr/bin/env bash
# cockpit/spawn.sh — context-aware DEV + MONITOR spawn.
# Reads cwd from focused kitty (procfs walk). Project-type-aware seeding.
set -eu
source ~/.config/hypr/scripts/cockpit/lib.sh

CWD=$(cockpit_cwd)
CURRENT=$(hyprctl activeworkspace -j | jq -r '.id')
NEXT=$((CURRENT + 1))

if [[ -z $CWD || ! -d $CWD ]]; then
  notify-send "Cockpit" "No cwd context — opening blank kitty on ws$NEXT"
  hyprctl dispatch exec "[workspace $NEXT silent] kitty"
  sleep 0.3
  hyprctl dispatch workspace "$NEXT"
  exit 0
fi

DEV_WS=$NEXT
MON_WS=$((CURRENT + 2))
PROJECT=$(basename "$CWD")
SEED=$(cockpit_seed_cmd "$CWD")

notify-send "Cockpit" "$PROJECT  →  DEV ws$DEV_WS · MON ws$MON_WS"

# DEV: VS Code (folder) + free kitty in cwd
hyprctl dispatch exec "[workspace $DEV_WS silent] code $CWD"
sleep 0.5
hyprctl dispatch exec "[workspace $DEV_WS silent] kitty --directory $CWD"

# MONITOR: visualizer (lazydocker for container projects, lazygit otherwise)
sleep 1.2
if cockpit_is_container_project "$CWD"; then
  hyprctl dispatch exec "[workspace $MON_WS silent] kitty --directory $CWD -e lazydocker"
else
  hyprctl dispatch exec "[workspace $MON_WS silent] kitty --directory $CWD -e lazygit"
fi

# MONITOR: driver terminal — seeded with inferred command (typed, not run)
sleep 0.4
if [[ -n $SEED ]]; then
  hyprctl dispatch exec "[workspace $MON_WS silent] kitty --directory $CWD -e fish -i -C \"commandline '$SEED'\""
else
  hyprctl dispatch exec "[workspace $MON_WS silent] kitty --directory $CWD"
fi

sleep 0.3
hyprctl dispatch workspace "$DEV_WS"
notify-send "Cockpit" "$PROJECT ready · seed: ${SEED:-none}"
