#!/usr/bin/env bash
# Shared helpers for the cockpit scripts.

# cwd of the focused window — takes the active window pid's most-recent
# direct child (typically the shell) and reads its /proc/<pid>/cwd.
# Walking deeper than one level picks up nested helpers (nvim, claude-code
# workers) whose cwd isn't where the user thinks they are.
cockpit_cwd() {
  local pid child
  pid=$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty')
  [[ -z $pid || $pid -le 0 ]] && return
  child=$(pgrep -P "$pid" -n 2>/dev/null)
  [[ -z $child ]] && child=$pid
  readlink "/proc/$child/cwd" 2>/dev/null
}

# Inferred build/dev command for a project root. Prints empty string if no
# marker recognized — caller should treat that as "no seed."
cockpit_seed_cmd() {
  local d=$1
  if   [[ -f $d/compose.yaml || -f $d/compose.yml || -f $d/docker-compose.yml ]]; then
    echo "podman compose up --build"
  elif [[ -f $d/Containerfile || -f $d/Dockerfile ]]; then
    echo "podman build -t $(basename "$d" | tr '[:upper:]' '[:lower:]') ."
  elif [[ -f $d/package.json ]]; then
    if   [[ -f $d/bun.lockb ]];      then echo "bun run dev"
    elif [[ -f $d/pnpm-lock.yaml ]]; then echo "pnpm dev"
    elif [[ -f $d/yarn.lock ]];      then echo "yarn dev"
    else                                  echo "npm run dev"
    fi
  elif compgen -G "$d/*.tf" > /dev/null; then
    echo "tofu plan"
  elif [[ -f $d/Cargo.toml ]]; then
    echo "cargo run"
  fi
}

cockpit_is_container_project() {
  local d=$1
  [[ -f $d/compose.yaml || -f $d/compose.yml || -f $d/docker-compose.yml || \
     -f $d/Containerfile || -f $d/Dockerfile ]]
}
