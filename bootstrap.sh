#!/usr/bin/env bash
# bootstrap.sh — fresh Arch -> ccsmith33's full Hyprland + cockpit setup
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/bootstrap.sh | bash
#   OR
#   git clone <repo>; cd <repo>; ./bootstrap.sh
#
# Assumptions:
#   - Arch already installed via archinstall with LUKS + btrfs + GRUB
#   - User has sudo
#   - Network is up
#
# What this does:
#   1. Installs every package the build depends on (pacman + AUR via paru).
#   2. Enables required system services.
#   3. Runs `chezmoi init --apply <repo>` to materialize all configs.
#   4. Leaves machine-specific things (fingerprint enrollment, GitHub auth,
#      LUKS TPM enrollment) as manual follow-ups documented at the end.
#
# This is the artifact that justifies the two-week experiment: a fresh Arch
# install becomes the full daily-driver in one command.

set -euo pipefail

# --- TODO: PACKAGES (filled in as we install layers) ---------------------
PACMAN_PKGS=(
  # L2 snapshots
  snapper snap-pac grub-btrfs inotify-tools
  # L5 hardware
  power-profiles-daemon framework-system fprintd libfprint iio-sensor-proxy usbutils
  # L6 wayland
  hyprland xdg-desktop-portal-hyprland xorg-xwayland kitty hyprpolkitagent
  pipewire wireplumber pipewire-pulse pipewire-jack pipewire-alsa
  bluez bluez-utils
  qt5-wayland qt6-wayland noto-fonts noto-fonts-emoji
  # L7 greeter
  greetd greetd-tuigreet
  # L13 chezmoi + dev essentials
  chezmoi git github-cli openssh
)

# --- TODO: AUR PACKAGES (paru) ------------------------------------------
AUR_PKGS=(
  # filled in as we add AUR-only tools
)

# --- TODO: SYSTEM SERVICES ---------------------------------------------
SYSTEM_SERVICES_ENABLE=(
  greetd.service
  bluetooth.service
  framework-charge-limit.service
  grub-btrfsd.service
  sshd.service
)

# --- TODO: USER SERVICES -----------------------------------------------
USER_SERVICES_ENABLE=(
  pipewire.socket
  pipewire-pulse.socket
  wireplumber.service
)

main() {
  echo "==> bootstrap.sh: NOT YET IMPLEMENTED"
  echo "    Layers covered so far: L2, L5, L6, L7, L13 (this scaffolding)."
  echo "    Filling in as the build progresses."
  exit 1
}

main "$@"
