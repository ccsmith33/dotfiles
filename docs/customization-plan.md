# Customization plan — for return-from-gym review

Drafted 2026-04-27 while user is at the gym. Three parallel research agents finished. This doc consolidates findings into a concrete plan, flags the decisions that need user sign-off, and orders the work.

User instruction: **big things first, small adjustments (keybinds, navbar size) after.** That ordering is honored below.

---

## Where we stand

- end-4/dots-hyprland fully installed. QuickShell running (PID 243238) with first-run welcome dialog.
- Configs imported into chezmoi as a baseline commit (`f0265db`, 998 files). Pushed.
- Pre-end-4 snapshot is `pre-end-4-clone` (snapper #10). Snapshots are at #20 from snap-pac.
- `~/.config/hypr/custom/{keybinds,general,execs,rules}.conf` exist as override slots. Empty / commented. End-4 specifically reserves these for user overrides; future end-4 updates won't clobber them.
- `~/.config/hypr/hypridle.conf` ships in-place (no override slot).

---

## Three decisions I need from you

### Decision 1: Terminal — stay on kitty?

**Recommendation: Stay on kitty.** Fix the font size, padding, and add green borders. Then re-evaluate.

**Why:** the migration argument hinged on inline-image protocol fidelity (for `dive`/`lazydocker`/`chafa`/`viu`/`glow`) and VHS recording compatibility. VHS uses **ttyd internally** — your daily-driver terminal has zero effect on `.tape` reproducibility. So that argument evaporates. Kitty's graphics protocol is the reference implementation; live demos look most faithful here. And kitty has **built-in colored borders** (`window_border_width` + `active_border_color`) — your "no border" complaint is a one-line config fix, not a migration argument.

**Backup option if kitty still feels wrong after a config pass:** Ghostty 1.3.1 (March 2026). Mature now, kitty graphics protocol parity, simpler config, indistinguishable performance. Has minor rough edges in Hyprland (middle-click primary paste needs `gtk-enable-primary-paste`, window-class timing affects per-app rules, no scripting layer).

**Not WezTerm.** Slow cadence in 2026, Wayland reimplementation in flux, single-maintainer risk. Originally locked-in choice in your plan, but the 2026 reality changed the math.

→ **Pick: kitty (recommended) | Ghostty | Other**

---

### Decision 2: Theming approach

end-4's pipeline: wallpaper → `matugen` extracts dominant colors → writes a 43-color Material You palette to `~/.local/state/quickshell/user/generated/colors.json` → ~12 consumers (kitty, hypr, hyprlock, fuzzel, GTK3/4, Kvantum, KDE, QuickShell UI, etc.) read or template-render from it.

You want a hand-picked static "overgrowth" palette. Three strategies:

| | Strategy A: Bypass | Strategy B: Hijack | Strategy C: Hybrid (recommended) |
|---|---|---|---|
| **What** | Disable matugen entirely; hand-write static palette to all 12 consumer files | Feed matugen a fixed swatch image; let it auto-generate the full 43-color palette every time | Run matugen ONCE from our anchor colors, save the output, then disable regen and tweak tertiary/error roles for rust accents |
| **Effort** | ~4 hours | ~30 min | ~1 hour |
| **Control** | Total | Anchor only (matugen derives 42 colors) | Anchor + targeted overrides |
| **Risk** | Stable; ignores future end-4 changes | Fragile — breaks if matugen invocation changes upstream | Stable like A; uses pipeline once then locks |
| **Trade-off** | We hand-fill 43 colors per consumer | Can't easily inject rust accents (Material You derives all colors from one anchor → everything green-tinted) | Best of both — full coherent palette from a green anchor + manual rust touches where it matters |

**Recommendation: Strategy C (Hybrid).** We keep your "static palette" goal (no wallpaper-driven changes), get a coherent 43-color M3 palette from one matugen run, then hand-edit a handful of color slots in `colors.json` to put rust where decay/failure/error semantics need it. After that, disable Ctrl+Super+T's wallpaper picker so it doesn't regenerate. Wallpapers become *visual only* — you can still set them, they just don't drive theme.

→ **Pick: Strategy C (recommended) | A pure-static | B pure-anchor**

---

### Decision 3: Initial palette anchor

I drafted a 12-swatch palette earlier. With your "green-dominant + dark-default + green borders" feedback, I'd reweight it like this:

```
Backgrounds (deep dark, green-tinted)
  bg-deep    #0d1612
  bg-medium  #16241e
  bg-elev    #1f3329

Foreground
  fg-primary #c4d3c3
  fg-muted   #7c8e85

Greens (the spine — DOMINANT)
  moss-deep  #4a6b3f   inactive borders, dim greens
  moss-mid   #6c8a59   *** PRIMARY ACCENT — active borders, cursor, selection
  fern       #8aa472   hover, lighter accent
  cyan-pale  #67b99a   highlight, "running"/"healthy" status

Supporting accents (use sparingly)
  teal-deep  #1f4d4a   secondary accent only
  teal-mid   #36807a   pipeline "running" indicator
  rust-mid   #a85a2b   *** DECAY ACCENT — failures, errors, warnings
```

The matugen anchor would be `moss-mid` (#6c8a59). That puts greens in primary/secondary roles automatically. Then we manually inject `rust-mid` into M3's tertiary/error slots.

→ **Approve palette as-is | Adjust specific colors (tell me which) | Wait until I see wallpapers and re-decide**

---

## Execution order (after decisions)

### Phase 1 — Theme apply (the BIG one)
*Depends on Decisions 2 + 3.*

1. Run matugen once with anchor color: `matugen color hex "#6c8a59"` to generate seed `colors.json`.
2. Hand-edit `colors.json` to inject rust accents in tertiary + error slots, deep-green-tint the surface tones.
3. Copy result to `~/.local/state/quickshell/user/generated/colors.json` as the static palette.
4. Disable matugen regen in `~/.config/quickshell/ii/scripts/colors/switchwall.sh` (comment out the matugen invocation block; replace with `echo "Overgrowth palette is static"`).
5. Trigger one regeneration of consumer files (the matugen template render step still works — just won't re-extract). Affected:
   - `~/.config/hypr/hyprland/colors.conf` (Hyprland borders → moss-mid active, ash inactive)
   - `~/.config/hypr/hyprlock/colors.conf` (lock screen)
   - `~/.config/fuzzel/fuzzel_theme.ini` (launcher)
   - `~/.config/gtk-{3,4}.0/gtk.css` (GTK apps)
   - `~/.config/quickshell/ii/scripts/colors/terminal/kitty-theme.conf` (kitty palette)
6. Send SIGUSR1 to kitty to reload, run `hyprctl reload`, regenerate Kvantum theme via `kde-material-you-colors-wrapper.sh`.
7. Visual check: bar, lock, launcher, terminal, GTK app (e.g. `nautilus`), Qt app (e.g. `dolphin`).

**Snapshot before:** `pre-overgrowth-theme`. If anything looks broken: `snapper rollback` or `git checkout dot_config/` in chezmoi.

### Phase 2 — Terminal fix (kitty config)
*Depends on Decision 1.*

Edit `~/.config/kitty/kitty.conf`:
```conf
# Larger text (FW16 165 DPI)
font_size 13.0

# Visible padding
window_padding_width 8

# Green borders — matches the overgrowth aesthetic
window_border_width 1.5pt
active_border_color #6c8a59
inactive_border_color #1f3329

# Optional: subtle background opacity for the "abandoned space" feel
background_opacity 0.92
```

Reload: send SIGUSR1 to running kitty (`pkill -SIGUSR1 kitty`).

Mirror the border in Hyprland for consistency on non-kitty windows: `~/.config/hypr/custom/general.conf`:
```conf
general {
    col.active_border = rgba(6c8a59ff)
    col.inactive_border = rgba(1f3329ff)
    border_size = 2
}
```

### Phase 3 — Functional fixes (the small stuff)

Drop into `~/.config/hypr/custom/keybinds.conf` (append to the existing file — it already has the user-overrides comment block):

```conf
# --- ccsmith33 overrides ---

# Super+Q opens terminal (was: killactive)
unbind = Super, Q
bind = Super, Q, exec, $terminal

# Super+L locks screen (was: loginctl lock-session — doesn't actually launch the lock UI)
unbind = Super, L
bind = Super, L, exec, hyprlock

# Super+Tab cycles workspaces forward; Shift reverses (was: overview toggle)
unbind = Super, Tab
bind = Super, Tab, workspace, e+1
bind = Super+Shift, Tab, workspace, e-1

# Super+Space launches fuzzel directly (Super-tap to search still works via end-4's bindid)
bind = Super, Space, exec, pkill fuzzel || fuzzel
```

And to `~/.config/hypr/hypridle.conf`, change line 14:
```conf
listener {
    timeout = 300 # 5mins
    on-timeout = hyprlock        # was: loginctl lock-session
}
```

For "smooth but fast" animations, drop into `~/.config/hypr/custom/general.conf`:
```conf
animations {
    bezier = smoothDecel, 0.25, 0.46, 0.45, 0.94
    bezier = quickEase,   0.4,  0.0,  0.2,  1.0

    animation = workspaces,        1, 1.5, quickEase,   slide
    animation = windowsIn,         1, 1.5, smoothDecel, popin 80%
    animation = windowsOut,        1, 1.0, smoothDecel, popin 90%
    animation = windowsMove,       1, 1.5, smoothDecel, slide
    animation = fadeIn,            1, 1.0, smoothDecel
    animation = fadeOut,           1, 0.8, smoothDecel
    animation = layersIn,          1, 1.2, smoothDecel, popin 93%
    animation = layersOut,         1, 0.8, smoothDecel, popin 94%
    animation = border,            1, 0.8, quickEase
}
```

(Hyprland animation duration unit = 100ms, so `1.5` = 150ms. End-4's defaults were 200–700ms, often with overshoot beziers — these tighten things to 80–150ms with no overshoot.)

Reload everything: `hyprctl reload`.

### Phase 4 — Bar + density tweaks (defer until after Phase 1–3)
The "navbar feels small" is a quickshell config tweak. Won't touch yet — easier to evaluate once the palette is right.

### Phase 5 — Wallpaper choice
Independent of the rest. Pick 1–3 from the curated sources. Drop them in `~/Pictures/wallpapers/`. Tell me which one is the daily and which are alts. We set via `swww img` (it's installed) without re-triggering matugen since we disabled wallpaper→theme in Phase 1.

### Phase 6 — Verify, snapshot, commit, push
- New snapper snapshot `post-overgrowth-applied`.
- `chezmoi diff` → should show only the customizations.
- `chezmoi re-add` for any newly-tracked file.
- `git add -A; git commit -m "Apply overgrowth aesthetic + ccsmith33 keybinds"; git push`.

---

## Expected total time

- Phase 1 (theme): ~60 min execution + iterative tweaks.
- Phase 2 (terminal): ~10 min.
- Phase 3 (keybinds, animations, lockscreen): ~10 min.
- Phase 4 (bar): deferred.
- Phase 5 (wallpaper): user-paced.
- Phase 6 (verify + commit): ~10 min.

**Total: ~90 min for Phases 1-3 once decisions are made.**

---

## Open items still parked

- Fingerprint enrollment + PAM (deferred — needs your finger physically at the laptop).
- LUKS TPM2 auto-unlock (deferred per your "back of list" instruction).
- Cockpit work — the actual original deliverable. Architecture map is at `docs/cockpit-quickshell-architecture.md`. We start this after the rice settles.
- bootstrap.sh — to be filled out as we go. Currently a stub; package list is up to date through Layer 7.
