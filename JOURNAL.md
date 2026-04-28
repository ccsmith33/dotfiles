# FW16 + Arch Linux Build Journal

Living log of meaningful decisions, fixes, and breakages during the Arch + Hyprland buildout on the Framework Laptop 16. Will migrate into the chezmoi repo at Layer 13.

Format: dated entries, newest at the bottom. Capture *why* + *what changed* + *evidence it worked*. The end-of-week-2 evaluation will be based on what's actually here, not vibes.

---

## 2026-04-27 — Day 1: Layer 2 (snapshots / boot-into-snapshot)

**Starting state.** Arch installed via archinstall on the 1TB NVMe (LUKS2 + btrfs + subvols `@`, `@home`, `@log`, `@pkg`, with `.snapshots` nested inside `@` and `@home`). GRUB bootloader. Kernels: `linux` and `linux-lts`. Both `snapper` and `grub-btrfs` already installed by archinstall; `inotify-tools` present. Currently SSH'd in from desktop. paru built from source (paru-bin had libalpm mismatch). Node + Claude Code installed and authenticated.

**What archinstall already did (audit findings).**
- `snapper` configs `root` (for `/`) and `home` (for `/home`) created.
- `snapper-timeline.timer` and `snapper-cleanup.timer` enabled.
- Timeline retention: hourly 10 / daily 10 / monthly 10 / yearly 10; weekly + quarterly off.
- `grub-btrfsd.service` enabled and running with drop-in `ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots`.
- `/boot/grub/grub.cfg` sources `${prefix}/grub-btrfs.cfg` conditionally (lines 167–171).

**What was missing.**
- `snap-pac` (pacman pre/post hooks → auto-snapshot around every transaction).
- A baseline snapshot.

**Actions.**
1. Created baseline snapshot before any further installs:
   `sudo snapper -c root create --description "baseline-pre-hyprland" --cleanup-algorithm number` → snapshot #2.
2. Verified grub-btrfsd reacted (grub-btrfs.cfg regenerated, snapshot #2 appeared as a submenu with proper kernel cmdline including `subvol="@/.snapshots/2/snapshot"`).
3. Installed `snap-pac` via pacman. Pulled `python` 3.14.4 + `mpdecimal` as deps. snap-pac's own post-hook fired immediately and created snapshot #3 ("mpdecimal python snap-pac"). End-to-end loop verified: pacman txn → pre/post hooks → snapper snapshot → inotify → grub-btrfsd → grub-btrfs.cfg refreshed.
4. Edited `/etc/snap-pac.ini` to uncomment `[root]`, `important_packages = ["linux", "linux-lts"]`, `important_commands = ["pacman -Syu"]`. Effect: kernel updates and full system upgrades get `important=yes` userdata, so they're retained against `NUMBER_LIMIT_IMPORTANT=10` rather than rolling out under the standard `NUMBER_LIMIT=50`.

**Issues / TODOs surfaced.**
- `grub-btrfs.cfg` snapshot menu entries reference only `vmlinuz-linux`, not the LTS kernel. If we ever lose the standard kernel and want to boot a snapshot via LTS, we'd need to extend grub-btrfs config. Low priority — addresses an unlikely scenario.
- `grub-btrfs.cfg` snapshot entries do not include `amd-ucode.img` initrd. Booting *into a snapshot* skips microcode load. The main system grub menu entries do load it. Note for if/when we actually rollback boot.
- `os-prober` / Windows boot entry verification deferred (F12 fallback works).

**State at close of Layer 2.**
- 3 snapshots present (timeline #1, baseline #2, snap-pac #3).
- snap-pac configured to mark kernel + `-Syu` snapshots as `important`.
- grub-btrfsd watching `/.snapshots`, regenerating grub-btrfs.cfg on inotify events within seconds.
- Resilience floor in place. Cleared to start installing more packages.

**Next.** Layer 5 (hardware tuning): power-profiles-daemon, `amd_pstate=active`, battery 80% charge cap, fprintd, iio-sensor-proxy.

---

## 2026-04-27 — Day 1 (cont.): Layer 5 (hardware tuning)

**Survey before changes.**
- Microcode: AMD ucode loaded at early boot (revision `0x0b204037`). `amd-ucode` and `linux-firmware` packages already current (2026-04-10 builds).
- CPU pstate driver: `amd-pstate-epp`. `/sys/devices/system/cpu/amd_pstate/status` = `active`. **Kernel 6.19 enables `amd_pstate=active` by default for HX 370. The plan's GRUB cmdline edit was unnecessary — skipped, saved a reboot.**
- No power daemon installed (clean slate; no TLP to fight).
- Battery sysfs: `BAT1` exists; the standard `charge_control_end_threshold` file is **NOT present**. dmesg: `cros-charge-control cros-charge-control.5.auto: Framework charge control detected, preventing load`. The upstream cros driver intentionally bows out on FW hardware, so the plan's sysfs-write approach is dead. Pivot to `framework-system` (extra repo).
- Fingerprint reader: `Goodix Fingerprint USB Device` on usb 3-4.1 (libfprint-supported). `lsusb` was missing — installing `usbutils`.

**Decision pivots vs. original plan.**
1. **Skipped** `amd_pstate=active` GRUB edit — already active by kernel default. No reboot needed for this layer.
2. **Replaced** sysfs charge-threshold approach with `framework-system` (`framework_tool --charge-limit 80`) wrapped in a systemd oneshot. Reason: kernel deliberately suppresses cros-charge-control on FW hardware; sysfs path doesn't exist. User confirmed FW16's AC passthrough behavior makes 80% cap a clean win.

**Actions.**
1. Single pacman transaction (snap-pac pre #4 / post #5) installing: `power-profiles-daemon`, `framework-system`, `fprintd`, `libfprint`, `iio-sensor-proxy`, `usbutils`. Pulled `upower`, `libimobiledevice` stack, `libqmi`, `libmbim`, `protobuf` etc as deps.
2. Separate transaction (#6/#7) for `python-gobject` (optional dep of PPD; needed for `powerprofilesctl` CLI).
3. Enabled + started `power-profiles-daemon.service`. `powerprofilesctl` reports three profiles (performance/balanced/power-saver) all using `CpuDriver=amd_pstate` and `PlatformDriver=platform_profile`. Default profile = `balanced`.
4. Started `fprintd.service` and `iio-sensor-proxy.service` (D-Bus activated; the systemctl-enable warning about no install config is expected).
5. `fprintd-list ccsmith33` finds the device at `/net/reactivated/Fprint/Device/0` (`Goodix MOC Fingerprint Sensor`). No fingers enrolled — DEFERRED to next session at the laptop.
6. `iio-sensor-proxy`: `iio:device0` named `als` (ambient light) — visible to upower/Wayland compositor for auto-brightness later.
7. Tested `framework_tool --charge-limit 80`: response `Minimum 0%, Maximum 80%`. Verified persists.
8. Created `/etc/systemd/system/framework-charge-limit.service` (Type=oneshot, ExecStart calls framework_tool, WantedBy=multi-user.target). Enabled and started. Logs confirm clean exit (status=0).

**State at close of Layer 5.**
- amd_pstate active by kernel default.
- `power-profiles-daemon` running, three profiles available.
- Charge limit at 80% (framework-system + systemd, declarative, in-OS).
- Fingerprint daemon ready; sensor recognized; enrollment deferred.
- ALS visible via iio-sensor-proxy.
- 7 snapper snapshots total now (5 pre/post pairs + 2 manual + timeline).

**Issues / TODOs surfaced.**
- Fingerprint enrollment + PAM edits (sudo, system-local-login) deferred — needs physical access. PAM line will be `auth sufficient pam_fprintd.so` so password remains a fallback. (Tracked in TaskList.)
- Suspend/resume not yet exercised — the unknown variable on FW16 + Strix Point. Test before trusting overnight.
- HDMI/DP expansion cards: don't leave plugged in on battery (PCIe runtime PM blocked).

**Next.** Layer 6 (Hyprland) + Layer 7 (greetd/tuigreet). After that: chezmoi (L13) immediately, before any rice work, so configs go in version control from the start.

---

## 2026-04-27 — Day 1 (cont.): Verification reboot + Layer 6/7

**Verification reboot after L2/L5.** Clean. Verified post-boot:
- `framework_tool --charge-limit` → `Maximum 80%` (persisted across reboot).
- `framework-charge-limit.service` ran from boot (timestamps line up with system-start).
- `power-profiles-daemon` active, profile `balanced`, `CpuDriver=amd_pstate`.
- `/sys/.../amd_pstate/status` = `active` (kernel default for HX 370 on 6.19, no GRUB edit needed).
- 7 snapshots present.
- fprintd device + ALS still recognized.

**Boot errors observed (kernel-priority `err`).** All present, all benign:
- `ACPI BIOS Error (bug): Failure creating named object [\_SB.PCI0.GPPA.VGA.SINI/SREG], AE_ALREADY_EXISTS` — kernel-flagged firmware bug, cosmetic.
- `platform MSFT0201:00: AMD-Vi: [Firmware Bug]: No ACPI device matched UID, but 1 device matched HID` — cosmetic, IOMMU works.
- `hid-multitouch 0018:093A:0274.0007: Returned feature report did not match the request` — touchpad init noise, function unaffected.
- `ucsi_acpi USBC000:00: unknown error 256` (×3) — known AMD UCSI noise, USB-C functional.
- Documenting; not chasing. None block the build.

**Layer 6 + 7 actions.**
1. Surveyed audio state — archinstall **did not actually install pipewire packages** despite the option. Clean slate, no TLP/Pulse to fight.
2. Single pacman transaction (snap-pac #8/#9) installing: `hyprland xdg-desktop-portal-hyprland xorg-xwayland kitty hyprpolkitagent pipewire wireplumber pipewire-pulse pipewire-jack pipewire-alsa bluez bluez-utils greetd greetd-tuigreet qt5-wayland qt6-wayland noto-fonts noto-fonts-emoji`. Pulled `greeter`, `seat`, `rtkit`, `avahi` system users.
3. Enabled user-level `pipewire.socket`, `pipewire-pulse.socket`, `wireplumber.service` — all active.
4. Enabled + started `bluetooth.service` — active.
5. **Hyprland smoke test from TTY2** (before greetd): user logged in, ran `Hyprland`, landed in default session with background. Super+Q launched kitty. Trackpad/keyboard fine. Super+M exited cleanly. Default-config banner shown (expected). No errors.
6. Wrote `/etc/greetd/config.toml`:
   ```toml
   [terminal] vt = 1
   [default_session]
   command = "tuigreet --time --asterisks --remember --remember-session --user-menu --cmd Hyprland"
   user = "greeter"
   ```
   Backed up archinstall's default to `config.toml.archinstall.bak`.
7. Took manual snapshot `pre-greetd-enable` (#10). Disabled `getty@tty1.service`. Enabled `greetd.service` (also auto-symlinked as `display-manager.service`).

**State at close of Layer 6/7 (pre-reboot).**
- Hyprland 0.54.3 installed and proven runnable directly.
- PipeWire stack active for the user.
- Bluetooth daemon up.
- greetd configured but not yet reached (next reboot proves it).
- 8 snapshots after reboot work: 7 from earlier + the pre-greetd manual.

**Issues / TODOs surfaced.**
- Double-password UX (LUKS passphrase → login passphrase) is a friction the user wants reduced. Standard fix: TPM2 auto-unlock via `systemd-cryptenroll`. Tracked, deferred to end of build per user direction.
- `getty@tty1.service` now disabled. Recovery path if greetd fails: Ctrl+Alt+F2 spawns a fresh getty via systemd's auto-vt; alternatively boot a snapshot via grub-btrfs.

**Next.** Reboot to validate full graphical login path: GRUB → kernel → tuigreet → Hyprland. After that: Layer 13 (chezmoi) before any rice work.

---

## 2026-04-27 — Day 1 (cont.): Layer 13 (chezmoi scaffold)

**Reboot to greetd succeeded.** Login path: LUKS prompt → GRUB → tuigreet on tty1 → password → Hyprland default session with background. Verified post-boot:
- `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=Hyprland`, `WAYLAND_DISPLAY=wayland-1`.
- `greetd.service` active.
- pipewire + wireplumber active under user; `pactl info` reports PulseAudio-on-PipeWire 1.6.4 with HiFi Speaker as default sink.
- `framework_tool --charge-limit` still 80%.
- A user `~/.config/hypr/hyprland.conf` was auto-created on first launch (system default + an 8-line autogenerated banner).

**Actions.**
1. `git config --global` set `user.name=ccsmith33`, `user.email=ccsmith33@crimson.ua.edu`, `init.defaultBranch=main`, `pull.rebase=false`, `core.editor="kitty -e nvim"`.
2. Generated `~/.ssh/id_ed25519` with no passphrase. Reasoning: at-rest protection comes from LUKS FDE; key is OS-permission-protected. Adding a passphrase later is one command (`ssh-keygen -p -f ~/.ssh/id_ed25519`). Public key fingerprint: `SHA256:sQWlrqYjsb9n4Yi/DdY08GnjUN42HE5P20+IcDFrj24`.
3. Installed `chezmoi` (snap-pac #11/#12) and `github-cli` (#13/#14).
4. `chezmoi init` → `~/.local/share/chezmoi/` is now a git repo on branch `main`.
5. `chezmoi add ~/.config/hypr/hyprland.conf` → copied to `dot_config/hypr/hyprland.conf` in source.
6. Moved `~/JOURNAL.md` into the chezmoi repo as `JOURNAL.md` (this file's new home).
7. Wrote skeleton `bootstrap.sh` with package lists per layer (TODO: implement main()), `README.md` describing layout, and `.chezmoiignore` so JOURNAL/README/bootstrap.sh aren't applied to `~`.
8. First commit: `f46eafc Initial chezmoi scaffold`.

**State at close of Layer 13 (scaffold).**
- Local chezmoi repo with hyprland.conf and journal under version control.
- 14 snapshots total (snap-pac is now part of every pacman txn so the count climbs quickly).
- gh CLI installed but not yet authenticated.
- Bootstrap script lists packages installed so far across L2/L5/L6/L7/L13.
- Repo visibility decided: **public** (per build's "publishable cockpit" goal).

**Open / TODO before this layer is fully closed.**
- `gh auth login` (interactive, user runs).
- `gh repo create dotfiles --public --source=$(chezmoi source-path) --push`.
- Add a chezmoi data file (`.chezmoidata.yaml`) for machine-specific values once we have a second machine to template against — defer.

**Next.** Layer 8 (rice). Will pause and ask before picking a rice repo or making any UI/workflow choices.

---

## 2026-04-27 — Day 1 (cont.): Layer 8 (rice install — end-4 baseline)

**Pivot from plan.** end-4 has migrated **AGS → QuickShell** (QML/Qt) sometime before April 2026. Locked decision in `project_decisions` updated. QuickShell is functionally equivalent for cockpit purposes — same architectural role, richer UI toolkit (full Qt ecosystem) at cost of writing QML instead of GJS.

**Install ordeal worth recording for the bootstrap script.** end-4's `./setup install` runs `yay -S --sudoloop` for AUR builds. yay's `--sudoloop` invokes bare `sudo -v` periodically. Default sudoers `verifypw=all` requires *every* matching policy entry to have `NOPASSWD` for `-v` to skip password. archinstall's `/etc/sudoers.d/00_ccsmith33` grants `ccsmith33 ALL=(ALL) ALL` (with password); our temp `/etc/sudoers.d/99-end4-install-tmp` granted NOPASSWD. The interaction made yay prompt for password, where pty/term issues + scrolling output then made the user think the password was wrong (classic UX trap). Fix: add `Defaults:ccsmith33 !authenticate` and `Defaults:ccsmith33 verifypw=never` to the temp drop-in. After install, removed the temp drop-in cleanly.

**Bootstrap implication.** `bootstrap.sh` should write the temp NOPASSWD+!authenticate drop-in *before* invoking end-4 setup, then remove it after. Future-proofing.

**Actions.**
1. Pre-snapshot `pre-end-4-clone` (#10) before cloning end-4.
2. Cloned `end-4/dots-hyprland` to `~/end-4-dots/`.
3. Audited the install script (3-stage: deps / setups / files). Confirmed:
   - Deps: ~14 `illogical-impulse-*` meta-packages from local PKGBUILDs. Includes QuickShell, Bibata cursor, KDE Qt theming pipeline, microtex (math rendering), fonts.
   - Setups: adds user to `video,i2c,input` groups; loads `i2c-dev` module; enables `bluetooth.service`, `ydotool` user service; sets dark theme via gsettings + Darkly KDE widget style.
   - Files: rsyncs `dots/.config/*` into `~/.config/`. With `--firstrun`, replaces existing files cleanly (no `.new` siblings).
4. Ran `./setup install -f -F --skip-plasmaintg --skip-allgreeting`. After the sudoers fix, install completed cleanly. Total snapshot count climbed to 20 (snap-pac fired through every meta-package transaction).
5. Removed `/etc/sudoers.d/99-end4-install-tmp` after install.
6. QuickShell did NOT auto-start because `hyprctl reload` (which the install script runs at the end) does not re-run `exec-once` directives. Started manually with `qs -c ii` and the user is now seeing the rice live (welcome dialog + bar visible).
7. Imported `~/.config/{hypr,quickshell,kitty,fish,foot,fuzzel,wlogout,Kvantum,matugen,mpv,illogical-impulse,kde-material-you-colors,starship.toml}` into chezmoi. Single big commit (998 files): `f0265db Import end-4 default configs into chezmoi`. Pushed.
8. Saved planning doc at `docs/cockpit-quickshell-architecture.md` from earlier audit.

**User feedback gathered (input for the customization plan).**
- Aesthetic: "post-cyberpunk overgrown by plants." Green is dominant favorite color; dark mode default everywhere; green borders on dark terminals.
- Animations: smooth but fast.
- Top bar: like it, slightly small (defer).
- Terminal: text too small, no borders, "maybe migrate from kitty."
- Keybind muscle memory: `Super+Q` for terminal (end-4 has it on `killactive`), `Super+Space` for fuzzel (end-4 uses tap-Super), `Super+L` for hyprlock (end-4 uses `loginctl lock-session` which doesn't actually launch the lock UI), `Super+Tab` to hold-and-cycle workspaces (end-4 uses overview).

**Research delegated (in progress as user is at gym):**
- Keybind audit + animation tuning + lockscreen diagnosis. **DONE.** Lockscreen: `loginctl lock-session` only signals session state; doesn't launch hyprlock. Fix is binding directly to `hyprlock`. Animations: end-4's speeds are 200-700ms with overshoot beziers; user wants 100-200ms with gentle curves.
- Terminal alternatives. **DONE.** Recommendation: stay on kitty, fix the config. VHS uses ttyd internally so host terminal is irrelevant for recordings. Backup option: Ghostty 1.3.1.
- Theming pipeline (matugen → consumers; how to override with static palette). **PENDING.**

**Next.** Once theming agent returns, write a comprehensive plan doc at `docs/customization-plan.md`. User explicitly said: do the BIG things first, small adjustments (keybinds, navbar size) after.

---

## 2026-04-27 — Day 1 (close): everything from rice → cockpit-ready

Long single-day session. Full path: aesthetic application, terminal config, keybinds, lockscreen, login UX, kernel fallback, cloud tooling, dev toolchain, cockpit-supporting tools, wallpaper.

**Aesthetic Phase 1-3 applied.**
- Overgrowth palette locked (Strategy C: matugen-once from anchor `#6c8a59`, hand-edited M3 error→`#d68a4c` copper, tertiary→`#c4a37a` warm tan, surfaces darkened-and-browned, ANSI red/green matched in brightness for diff readability). Frozen artifacts at `aesthetic/overgrowth-locked/`. Pattern for future wallpaper changes documented in commit message: switchwall.sh → cp locked palette back → applycolor.sh → hyprctl reload.
- Kitty: font_size 13, padding 21.75 (kept end-4 default). Kitty's own border off (Hyprland draws it now).
- Hyprland custom/general.conf: border_size 3, solid moss-mid active, solid bark-deep inactive.
- baseBarHeight 40→48 in QuickShell Appearance.qml.
- workspaceZoom 1.07→1.0 (was cropping wallpaper unnecessarily on both axes).

**Functional Phase 3.**
- custom/keybinds.conf overrides (Super+Q terminal, Super+W close, Super+L hyprlock, Super+Tab/Shift+Tab cycle workspaces, Super+Space fuzzel, Super+Shift+S grim+slurp screenshot). Each `unbind` followed by `bind` because Hyprland fires both bindings when same key bound twice (Super+W discovery).
- hypridle: timeout/sleep listeners changed to call `hyprlock` directly instead of `loginctl lock-session`.
- hyprlock: dropped pam_fprintd.so (PAM serial evaluation makes "fingerprint OR password at lock" UX painful — fingerprint stayed at sudo where the wait pattern fits). fade_on_empty true→false (entry box was intentionally invisible-when-empty by end-4 default, surprising).

**Login UX unification.**
- mkinitcpio HOOKS: udev→systemd, encrypt→sd-encrypt, keymap+consolefont→sd-vconsole. /etc/crypttab.initramfs created with tpm2-device=auto. /etc/default/grub: cryptdevice=→rd.luks.name=. Initramfs regenerated for both kernels.
- TPM2 enrolled to LUKS keyslot 1 bound to PCR 7. Password slot 0 kept as fallback.
- /etc/pam.d/sudo: pam_fprintd.so sufficient. Right-index finger enrolled.
- /etc/greetd/config.toml: auto-login as ccsmith33 → start-hyprland. (Was tuigreet --cmd Hyprland — also fixed missing start-hyprland wrapper warning.)
- ~/.config/hypr/custom/execs.conf: exec-once = sleep 0.5 && hyprlock --immediate.
- Result: LUKS auto-unlocks (no prompt), no tuigreet, hyprlock UI as the only visible auth at boot. Single password, single beautiful screen.

**Sudoers ordeal worth journaling.** end-4's setup script uses `yay -S --sudoloop`. yay's --sudoloop runs bare `sudo -v` to keep credentials warm. Default sudoers `verifypw=all` requires *every* matching policy entry to have NOPASSWD before -v skips password. archinstall's `/etc/sudoers.d/00_ccsmith33` grants `ccsmith33 ALL=(ALL) ALL` (with password); our temp drop-in granted NOPASSWD. The interaction made yay prompt for password despite NOPASSWD; combined with pty/scrolling-output confusion, the user thought their password was wrong. **Fix: temp NOPASSWD drop-in needs `Defaults:ccsmith33 !authenticate` and `Defaults:ccsmith33 verifypw=never` for AUR builds.** Removed after install. **Bootstrap.sh implication: when calling end-4's setup, add the temp drop-in first.**

**Layer 8 / 11 / 10 / 12 packages.**
- linux-lts + headers installed, GRUB lists both kernels.
- L11 cloud: azure-cli, kubectl, helm, k9s, kubectx, kubens, terraform, opentofu. AUR: powershell-bin (PowerShell 7.6.1).
- L10 dev: mise, direnv, glab, podman, buildah, distrobox, eza, bat, fd, ripgrep, zoxide, fzf, lazygit. AUR: visual-studio-code-bin (1.117).
- L12 cockpit deps: dive, btop, chafa, glow, d2, vhs (pacman). lazydocker, ctop, viu (AUR).
- Firefox 150 installed for browsing.

**Wallpaper.**
- 4000×2249 alphacoders 1406300 set as ~/Pictures/wallpapers/City.jpg. switchwall.sh → restore overgrowth palette pattern works (after fixing the bug where /tmp/mc.scss.locked got saved as 0 bytes one round; chezmoi-locked artifact is canonical).
- QuickShell required full restart to pick up new wallpaper file at same path (FileView watcher didn't trigger on file content change without path change).

**Cockpit decision.**
- **Pivot from QML-widgets-in-QuickShell to Hyprland workspace orchestration.** Super+Shift+P → spawn workspaces N+1 (DEV: VS Code + kitty) and N+2 (MONITOR: lazydocker + k9s + btop + ctop). Way more direct for the teaching use case; bounded scope; uses the actual tools students will use.

**State at close of day 1.**
- Snapshot count well past 100.
- chezmoi commit `caad953` then `6e564d1` then various intermediate. All pushed to github.com/ccsmith33/dotfiles.
- All Layer 0-13 work complete; L14 (backup), L15 (maintenance), L12 cockpit-build pending.

**Next session.** Fresh chat. Read `docs/handoff-cockpit.md` and start with `pacman -S podman-docker` + the cockpit-spawn.sh script.





