# Arch Linux Installer — Full Documentation

## Overview

Interactive Arch Linux installer that runs from the live ISO. Supports plain, LVM, and LUKS+LVM partitioning with dual-boot detection, GPU auto-configuration, and bundled desktop environment configs.

## Installation Flow

The installer runs 11 sequential steps. State is saved between steps so you can resume if interrupted.

```
Step  1: UEFI Verification      — Confirms 64-bit UEFI boot mode
Step  2: Disk Detection          — Lists disks, analyzes existing partitions
Step  3: Partitioning            — Mode selection + partition creation/reuse
Step  4: Format & Mount          — Formats partitions, mounts to /mnt
Step  5: WiFi Config Copy        — Copies iwd profiles to new system
Step  6: Base Install            — pacstrap (base, linux, firmware, essentials)
Step  7: System Configuration    — Locale, timezone, hostname, fstab, chroot setup
Step  8: Bootloader              — systemd-boot with auto-detected entries
Step  9: Package Selection       — WM choice, GPU drivers, AUR helper, browser, extras
Step 10: User Account & Rice     — Creates user, deploys selected config
Step 11: Final Checks & Reboot   — Verifies install, offers reboot
```

## Partition Modes

### Plain
Standard GPT partitions: EFI (1G) + Swap + Root.

### LVM
EFI (1G) + single LVM partition containing: Swap LV + Root LV (+ optional Home LV + custom LVs).

### LUKS + LVM
EFI (1G) + LUKS-encrypted partition containing LVM: Swap LV + Root LV (+ optional Home LV + custom LVs). Full-disk encryption with passphrase.

## Disk Handling

The installer handles these scenarios:

| Scenario | What happens |
|----------|-------------|
| Empty disk | Creates fresh GPT table, new partitions |
| Disk with free space | Creates partitions in free space, reuses existing EFI |
| Disk with existing Linux | Offers reuse (format-in-place) or nuke-and-rebuild |
| Disk with Windows (dual-boot) | Preserves Windows partitions, reuses EFI, installs alongside |
| Disk with LUKS | Can reuse existing LUKS container and LVM inside it |
| Full disk, no free space | Offers shrink (ext4/ntfs) or full wipe |

### EFI Partition Handling
- Existing EFI partitions are auto-detected by GPT type GUID
- On dual-boot, the existing EFI is reused (not reformatted)
- EFI contents are backed up to `/root/efi-backup-TIMESTAMP/` before any destructive operation
- Previous Arch entries are identified by hostname tag and replaced; other OS entries are preserved

## Desktop Environments

| Option | WM | Terminal | Bar | Launcher | Extras |
|--------|-----|----------|-----|----------|--------|
| 1. i3 | i3-gaps | Alacritty | Polybar | Rofi | Picom, Dunst |
| 2. i3 Custom | i3-gaps | Kitty | Polybar (14 scripts) | Rofi (5 themes) | Picom, Dunst, Flameshot, Fastfetch, sounds, yazi, wezterm |
| 3. Sway | Sway | Foot | Waybar | Wofi | Mako |
| 4. Hyprland | Hyprland | Foot | Waybar | Wofi | — |
| 5. KDE | KDE Plasma | Konsole | Plasma panel | KRunner | — |
| 6. None | — | — | — | — | CLI only |

## Directory Structure

```
arch-linux/
├── arch-install.sh              # Main installer (2275 lines)
├── nuke-recovery.sh             # EFI recovery tool
├── configs/
│   ├── i3/                      # Starter i3 config
│   │   ├── index.sh             # Deployment script
│   │   ├── packages.txt         # Package list
│   │   ├── config               # i3 config
│   │   ├── alacritty/           # Terminal config
│   │   ├── polybar/             # Status bar
│   │   ├── picom/               # Compositor
│   │   ├── dunst/               # Notifications
│   │   └── rofi/                # Launcher
│   ├── user_custom/             # Full i3 rice (Hafeezh's setup)
│   │   ├── index.sh             # Deployment script
│   │   ├── packages.txt         # Package list
│   │   ├── i3/                  # i3 config
│   │   ├── polybar/             # 14 custom polybar scripts
│   │   ├── kitty/               # Terminal
│   │   ├── picom/               # Compositor with animations
│   │   ├── dunst/               # Notifications with sounds
│   │   ├── rofi/                # 5 launcher themes
│   │   ├── nvim/                # Neovim (LazyVim)
│   │   ├── fastfetch/           # System info
│   │   ├── yazi/                # File manager
│   │   ├── wezterm/             # Alt terminal
│   │   ├── lf/                  # Alt file manager
│   │   ├── bat/                 # Cat replacement
│   │   ├── librewolf/           # Browser config + extensions
│   │   ├── sounds/              # Alert sounds
│   │   ├── screenlayout/        # Display layout scripts
│   │   ├── vpn/                 # VPN configs
│   │   ├── fontconfig/          # Font rendering
│   │   ├── gtk-3.0/, gtk-4.0/  # GTK themes
│   │   ├── qt5ct/, qt6ct/       # Qt themes
│   │   └── flameshot/           # Screenshot tool
│   ├── sway/                    # Sway config
│   │   ├── index.sh, packages.txt
│   │   ├── config               # Sway config
│   │   ├── waybar/, wofi/, mako/, foot/
│   ├── hyprland/                # Hyprland config
│   │   ├── index.sh, packages.txt
│   │   ├── hyprland.conf
│   │   ├── waybar/, wofi/, foot/
│   ├── kde/                     # KDE Plasma config
│   │   ├── index.sh, packages.txt
│   │   ├── kwinrc, plasma-org.kde.plasma.desktop-appletsrc
│   └── custom_template/         # Template for creating your own config
│       ├── index.sh             # Annotated deployment template
│       └── README.md            # How to create a custom config
├── fonts/                       # Bundled TTF fonts
│   ├── JetBrains-Mono-Nerd-Font-Complete.ttf
│   ├── Iosevka-Nerd-Font-Complete.ttf
│   ├── MesloLGS NF *.ttf       # Powerlevel10k font
│   ├── Icomoon-Feather.ttf
│   └── GrapeNuts-Regular.ttf
└── README.md                    # Quick start guide
```

## How Configs Work

Each config directory contains:
- `index.sh` — Deployment script called by the installer. Receives variables: `$home`, `$cfg`, `$SRC`, `$username`, `$KB_LAYOUT`, `$KB_VARIANT`
- `packages.txt` — One package per line. Lines starting with `#` are comments. The installer reads this and installs via pacman/yay.
- Config files — Copied to the appropriate locations by `index.sh`

### Creating a Custom Config

Copy `configs/custom_template/` and modify:
```bash
cp -r configs/custom_template configs/mysetup
# Edit configs/mysetup/index.sh and packages.txt
```

The installer auto-discovers configs in `configs/` that have an `index.sh`.

## GPU Detection

The installer auto-detects GPU hardware and installs appropriate drivers:

| GPU | Driver packages |
|-----|----------------|
| Intel | `mesa`, `intel-media-driver`, `vulkan-intel` |
| AMD | `mesa`, `xf86-video-amdgpu`, `vulkan-radeon` |
| NVIDIA | Choice of open-source (`nouveau`) or proprietary (`nvidia`, `nvidia-utils`) |
| eGPU (Thunderbolt NVIDIA) | `bolt`, systemd service, Xorg config for hot-plug |

## Resume Support

State is saved to `/root/.arch-install-state` after each step. If the installer is interrupted:
```bash
./arch-install.sh
# "Resume from last checkpoint?" prompt appears
```

Saved state includes: disk, partition mode, partition paths, LUKS/LVM names, hostname, username, and all configuration choices.

## Recovery

If something goes wrong after install:
```bash
# Boot live ISO, mount, chroot
mount /dev/sdXn /mnt
arch-chroot /mnt

# Or use the EFI recovery tool
./nuke-recovery.sh /root/efi-backup-TIMESTAMP/
```

## Requirements

- UEFI system (64-bit preferred, 32-bit supported with warning)
- Internet connection (ethernet or WiFi via iwd)
- Arch Linux live ISO (latest monthly release recommended)
- Minimum ~20GB disk space for base + WM install
