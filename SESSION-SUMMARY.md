# Arch Installer — Session Summary

## Overview

Continued building the interactive Arch Linux installer at `/home/hafeezh/arch-installer/`. This session focused on auto-start behavior, bug fixes, Git hosting, and keyboard layout support.

## Changes Made

### Auto-Start Behavior

1. **Extended auto-start question to Sway and Hyprland** — previously only i3/user_custom got the TTY vs auto-start choice. Added Sway (`exec sway`) and Hyprland (`exec Hyprland`) to `.bash_profile` auto-start.

2. **Removed the auto-start question entirely** — user requested all WMs auto-start by default. No more manual `startx`/`sway`/`Hyprland` typing.

3. **Added getty autologin on TTY1** — systemd override at `/etc/systemd/system/getty@tty1.service.d/autologin.conf` auto-logs in the user. Combined with `.bash_profile`, the user goes straight from boot to desktop with zero interaction. KDE still uses SDDM. "None" stays as plain TTY.

### Bug Fixes (4 found during full audit)

1. **i3 installed `kitty` but config uses `alacritty`** — changed i3 (option 1) packages to `alacritty`. user_custom keeps `kitty`.
2. **`nm-applet` wrong package name** — changed to `network-manager-applet` (correct Arch package) for both i3 and user_custom.
3. **`bolt` package missing for eGPU** — added `pacman -S bolt` and `systemctl enable bolt.service` in the eGPU deployment block.
4. **Menu description said "kitty" for i3** — changed to "alacritty".

### Pacstrap Fix

- **`intel-ucode.img` conflict on EFI reuse** — the backup list for conflicting boot files only had `vmlinuz-linux` and `initramfs-*`. Added `intel-ucode.img` and `amd-ucode.img` so pacstrap retries cleanly when reusing an EFI partition from another install.

### GPU Package Fix

- **Removed `mesa-vdpau`, `libva-mesa-driver`, `libva-intel-driver`** — these were merged into `mesa` itself since mesa 24.2. Caused "target not found" errors on fresh installs.
- Intel GPU packages now: `mesa vulkan-intel intel-media-driver sof-firmware`
- AMD GPU packages now: `mesa vulkan-radeon sof-firmware`

### AUR Helper Fix

- **Changed from `-bin` to source build** — `paru-bin` was compiled against `libalpm.so.15` but fresh Arch has a newer version. Now clones `paru` (or `yay`) and builds from source via `makepkg`, linking against the correct libalpm.
- Added helpful error message on AUR helper install failure telling the user how to fix conflicts.

### User Exists Check

- **Detect existing user on resume** — checks `/etc/passwd` in the chroot for UID ≥ 1000 users before prompting. If found, asks "Continue with 'username'?" instead of blindly running `useradd` and failing.

### Keyboard Layout Support

1. **Live session keyboard** — at the very start of the installer (before any questions), offers to load a console keymap via `loadkeys` so non-QWERTY users can type comfortably through the install.

2. **X11/Wayland keyboard layout picker** — searchable layout selection using `localectl list-x11-keymap-layouts`, then shows available variants for the chosen layout via `localectl list-x11-keymap-variants`. No freetext guessing.

3. **Layout injected into all WMs**:
   - i3: `setxkbmap <layout> -variant <variant>` appended to config
   - Sway: `xkb_layout` + `xkb_variant` in sway config
   - Hyprland: `kb_layout` + `kb_variant` in hyprland.conf
   - KDE/system-wide: `localectl set-x11-keymap`
   - user_custom: untouched (hardcoded `colemak_dh`)

4. **New global variables**: `KB_LAYOUT` (default: `us`), `KB_VARIANT` (default: empty) — both persisted in `save_state()`.

### Git Hosting

- **GitLab**: pushed to `git@gl-cp:code-pumpkin/arch-linux.git` (remote: `origin`)
- **GitHub**: created repo via `gh repo create`, pushed to `git@gh-cp:code-pumpkin/arch-linux.git` (remote: `github`)
- **Squashed history** into one clean initial commit, then incremental fixes after
- **Wrote proper README.md** replacing GitLab's default template

## Commits Pushed

1. `de6943e` — Arch Linux interactive installer (squashed initial)
2. `ef5a26d` — Fix pacstrap: back up stale intel/amd-ucode.img on EFI reuse
3. `61b40cd` — Fix GPU packages: remove mesa-vdpau, libva-mesa-driver, libva-intel-driver
4. `897249d` — Build AUR helper from source (not -bin) to fix libalpm mismatch
5. `b750018` — Check if user exists before useradd, offer to reuse
6. `77dffc5` — Add helpful error message on AUR helper install failure
7. `41b7b92` — Detect existing user before prompting, offer to reuse on resume
8. `b93274c` — Add X11 keyboard layout: ask during config, inject into all WMs
9. `f64d88e` — Fix keyboard: split into layout + variant
10. `5cbf62d` — Ask keyboard layout at installer start for live session
11. `43dfb8b` — X11 keyboard: searchable layout picker + variant list

## Current State

- **Script**: 2080+ lines, `bash -n` passes clean
- **11 install steps**: uefi → disks → partitions → format → wifi → base → config → bootloader → packages → user → finish
- **6 global variables persisted**: `WM_CHOICE`, `AUR_HELPER`, `BROWSER_PKG`, `EGPU_SETUP`, `KB_LAYOUT`, `KB_VARIANT`
- **Zero dangling references**: no scrot, pulseaudio, EXT_SCRIPT, nm-applet, auto_startx, mesa-vdpau
- **All WMs boot to desktop automatically** (except "None")
