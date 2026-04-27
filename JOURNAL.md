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


