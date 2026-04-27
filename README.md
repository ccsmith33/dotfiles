# dotfiles

ccsmith33's Framework Laptop 16 + Arch Linux + Hyprland configuration.

Goal: a fresh Arch install becomes a fully-configured daily driver — Hyprland tiling UI, deployment-pipeline teaching cockpit, BMAD-swarm + Claude Code dev environment — in one bootstrap command.

## Layout

```
.
├── bootstrap.sh        # fresh-install entry point (NOT chezmoi-applied)
├── JOURNAL.md          # dated log of build decisions, fixes, breakages
├── README.md           # this file
├── .chezmoiignore      # marks the three above as repo-only
└── dot_config/         # everything below this is chezmoi-applied to ~/.config/
    └── hypr/
        └── hyprland.conf
```

## Bootstrap

On a fresh Arch (post-archinstall) machine:

```sh
git clone https://github.com/<user>/dotfiles ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

The bootstrap script handles package install, service enablement, and `chezmoi init --apply` for the configs.

## Day-to-day

After bootstrap, drive everything through chezmoi:

```sh
chezmoi edit ~/.config/hypr/hyprland.conf
chezmoi diff
chezmoi apply
```

## What's not in here

- Hardware-bound state: LUKS TPM enrollment, fingerprint enrollment.
- Secrets: API keys, SSH private keys.
- One-shots: BIOS settings.

These are tracked in JOURNAL.md but not declarative.
