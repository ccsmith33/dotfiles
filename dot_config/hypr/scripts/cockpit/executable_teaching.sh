#!/usr/bin/env bash
# cockpit/teaching.sh — fuzzel preset picker, spawns lesson layout in cwd.
set -eu
source ~/.config/hypr/scripts/cockpit/lib.sh

CWD=$(cockpit_cwd)
[[ -z $CWD || ! -d $CWD ]] && CWD=$HOME

PRESET=$(printf '%s\n' \
  "git          — lazygit + driver terminal (visualize commits/branches)" \
  "containers   — lazydocker + driver terminal seeded for this project" \
  "image-layers — dive against a chosen image" \
  | fuzzel --dmenu --prompt "teach › " | awk '{print $1}')

[[ -z $PRESET ]] && exit 0

CURRENT=$(hyprctl activeworkspace -j | jq -r '.id')
WS=$((CURRENT + 1))

case $PRESET in
  git)
    hyprctl dispatch exec "[workspace $WS silent] kitty --directory $CWD -e lazygit"
    sleep 0.4
    hyprctl dispatch exec "[workspace $WS silent] kitty --directory $CWD"
    notify-send "Cockpit · Teach" "git → ws$WS  ($(basename "$CWD"))"
    ;;
  containers)
    hyprctl dispatch exec "[workspace $WS silent] kitty --directory $CWD -e lazydocker"
    sleep 0.4
    SEED=$(cockpit_seed_cmd "$CWD")
    if [[ -n $SEED ]]; then
      hyprctl dispatch exec "[workspace $WS silent] kitty --directory $CWD -e fish -i -C \"commandline '$SEED'\""
    else
      hyprctl dispatch exec "[workspace $WS silent] kitty --directory $CWD"
    fi
    notify-send "Cockpit · Teach" "containers → ws$WS  (seed: ${SEED:-none})"
    ;;
  image-layers)
    IMAGE=$(podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
      | grep -v '<none>' \
      | fuzzel --dmenu --prompt "image › ")
    [[ -z $IMAGE ]] && exit 0
    hyprctl dispatch exec "[workspace $WS silent] kitty --directory $CWD -e dive $IMAGE"
    notify-send "Cockpit · Teach" "dive on $IMAGE → ws$WS"
    ;;
esac

sleep 0.3
hyprctl dispatch workspace "$WS"
