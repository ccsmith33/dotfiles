# Cockpit handoff — for the next session

You're starting a fresh chat to tackle Layer 12 (the cockpit) with clean context. This doc is the briefing.

---

## What's already done (don't redo)

**System foundation:**
- Arch + Hyprland on FW16, fully working. LUKS auto-unlocks via TPM2 (PCR 7). greetd auto-logs in. Hyprland session locks via hyprlock as the only auth UI. Fingerprint enrolled for sudo.
- Both `linux` 6.19.14 and `linux-lts` 6.18.24 kernels installed; sd-encrypt initramfs, both bootable from GRUB.
- Snapshots at every meaningful step via snap-pac + grub-btrfs.

**Aesthetic:**
- "Overgrowth" palette locked: moss-mid `#6c8a59` primary, rust-mid `#a85a2b` decay, bark-mid `#6e5034` tertiary, dark-brown surfaces `#1f1a14`. ANSI red/green matched-brightness. Dark mode everywhere.
- Wallpaper: alphacoders 1406300 (van Velsen "Overgrown Future"), 4000×2249 sharp.
- Bar height 48px (was 40), kitty font 13pt (was 11), borders 3px solid moss-mid active / bark-deep inactive.
- Frozen palette artifacts at `aesthetic/overgrowth-locked/` — restore after any matugen run.

**Tooling installed:**
- L9-10 Dev: mise, direnv, glab, podman, buildah, distrobox, eza, bat, fd, ripgrep, zoxide, fzf, lazygit, VS Code, kitty.
- L11 Cloud: azure-cli, kubectl, helm, k9s, kubectx, kubens, terraform, opentofu, **pwsh** (PowerShell 7.6.1, no `Az` module yet).
- L12 Cockpit-supporting: dive, lazydocker, ctop, btop, vhs, glow, chafa, viu, d2.
- Firefox 150 installed.

**Keybinds** (in `~/.config/hypr/custom/keybinds.conf`):
- Super+Q → kitty
- Super+W → close window
- Super+L → hyprlock
- Super+Tab / Super+Shift+Tab → cycle workspaces
- Super+Space → fuzzel
- Super+Shift+S → grim+slurp screenshot
- Super+Shift+Q → force-kill window
- Super+Shift+P → **RESERVED for cockpit (not yet wired)**

---

## What to build next: the cockpit

**The vision** (locked in 2026-04-27):

`Super+Shift+P` spawns **two workspaces relative to current**:
- **Workspace N+1 = DEV environment.** VS Code + kitty terminal. (Browser/`gh` ad-hoc.)
- **Workspace N+2 = MONITOR/TEACH station.** Four-tile TUI grid:
  - lazydocker (top-left)
  - k9s (top-right)
  - btop (bottom-left)
  - ctop (bottom-right)

After spawn, lands the user on N+1 (DEV). MONITOR is one Super+Tab away, ready to demo on stream.

**Why this design over QML widgets:** workspace orchestration is bounded, immediately useful, and lets you LIVE-DEMO the actual tools students will use, not custom widgets. QML cockpit panel idea is parked at `docs/cockpit-quickshell-architecture.md` if we ever want a status overview, but it's not the primary deliverable.

---

## Concrete first-session work

### 1. Install + enable podman socket (lazydocker dependency)

```bash
sudo pacman -S --needed --noconfirm podman-docker
systemctl --user enable --now podman.socket
docker info  # verify it works
```

`podman-docker` provides a `/usr/bin/docker` shim that calls podman. Lazydocker reads from `/run/user/1000/podman/podman.sock` once that socket is enabled.

### 2. Write `~/.config/hypr/scripts/cockpit/spawn.sh`

```bash
#!/usr/bin/env bash
# Cockpit spawn — DEV + MONITOR workspaces relative to current
set -eu

CURRENT=$(hyprctl activeworkspace -j | jq -r '.id')
DEV_WS=$((CURRENT + 1))
MON_WS=$((CURRENT + 2))

notify-send "Cockpit" "DEV→ws$DEV_WS  MONITOR→ws$MON_WS"

# DEV: VS Code + kitty
hyprctl dispatch exec "[workspace $DEV_WS silent] code"
sleep 0.5
hyprctl dispatch exec "[workspace $DEV_WS silent] kitty -1"

# MONITOR: 4-pane TUI grid
sleep 1.5
hyprctl dispatch exec "[workspace $MON_WS silent] kitty -1 -e lazydocker"
sleep 0.4
hyprctl dispatch exec "[workspace $MON_WS silent] kitty -1 -e k9s"
sleep 0.4
hyprctl dispatch exec "[workspace $MON_WS silent] kitty -1 -e btop"
sleep 0.4
hyprctl dispatch exec "[workspace $MON_WS silent] kitty -1 -e ctop"

# Land on DEV
sleep 0.8
hyprctl dispatch workspace "$DEV_WS"
notify-send "Cockpit" "Ready"
```

`chmod +x` it. Hyprland's `[workspace N silent]` window rule routes the spawned window without focus-stealing.

### 3. Bind in `~/.config/hypr/custom/keybinds.conf`

Append:
```
# Cockpit — spawn DEV + MONITOR workspaces
bind = Super+Shift, P, exec, ~/.config/hypr/scripts/cockpit/spawn.sh # Spawn cockpit
```

`hyprctl reload`. Test by hitting Super+Shift+P.

### 4. Iteration to expect

- **lazydocker without containers running** → empty UI, fine for teaching.
- **k9s without kubeconfig** → shows a "no context" screen. Could add a `KUBECONFIG=/dev/null kitty -e k9s` if it crashes hard, OR skip k9s and replace with `kitty -e watch kubectl version --client` or another command.
- **Tile layout under dwindle** → 4 windows on a 16:10 panel give a Fibonacci-ish layout, NOT a clean 2x2. If you want true 2x2, either use master layout or insert manual `togglesplit` commands between window spawns.
- **Teardown** (Super+Shift+O?): not yet wired. User closes manually with Super+W per window. Could add a `cockpit-teardown.sh` later that walks ws N+1 and N+2 and `hyprctl dispatch closewindow` everything.

### 5. Beyond the basic spawn

After the basic flow works:
- **vhs recording integration** — keybind to start a `.tape` recording on the MONITOR workspace. Useful for canned class demos.
- **Hot-swap "presets"** — different MONITOR sets for different class topics (Docker week vs k8s week vs Azure week). Pick from fuzzel.
- **Status notifications** — when a long-running pipeline finishes (poll `az pipelines runs list`), notify-send. Keeps the QML-panel idea relevant in a lightweight way.
- **Visual polish** — set a Hyprland workspace rule that names workspaces "DEV"/"MONITOR" so they show clearly in the bar.

---

## How to start the next session

Open a fresh Claude Code session. Memory carries forward (user profile, working preferences, aesthetic, keybind preferences, locked decisions). First message can be brief:

> Read `~/.local/share/chezmoi/docs/handoff-cockpit.md` and pick up the cockpit work. Start with podman-docker install.

Or even tighter: `/loop`-style — just say "do the cockpit handoff plan" and trust memory + the doc.

---

## Open followups (deferred, not blocking)

- `Az` PowerShell module install: `Install-Module Az -Scope CurrentUser` inside pwsh (~5 min).
- BMAD-swarm install via npm when needed.
- Layer 14 backup (borg/restic + offsite + daily timer + tested restore).
- Layer 15 maintenance posture (reflector + paccache + arch-audit + informant).
- bootstrap.sh implementation — package list is up to date but `main()` is still a TODO stub.
- Wallpaper persistence across reboots — verify QuickShell remembers the path. If not, add an exec-once wallpaper-set.

---

## Recovery if anything breaks during cockpit work

- Snapshot `pre-cockpit-spawn` before Super+Shift+P testing.
- `git -C ~/.local/share/chezmoi reset --hard HEAD` to undo any chezmoi-tracked config edits.
- Boot snapshot via grub-btrfs if catastrophic.
