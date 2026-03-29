# Arch Linux Installer

Interactive Arch Linux installer with multiple desktop environments, GPU auto-detection, dual-boot support, and bundled rice configs.

## Features

- **6 desktop options**: i3, i3 Custom (full rice), Sway, Hyprland, KDE Plasma, or no GUI
- **GPU auto-detection**: Intel, AMD, NVIDIA (open-source or proprietary drivers)
- **Dual-boot friendly**: Preserves existing EFI entries, detects Windows/Ubuntu/Fedora, GRUB chainloading
- **LUKS + LVM**: Full-disk encryption with logical volume management
- **Pipewire audio**: Modern audio stack with PulseAudio compatibility
- **AUR helper**: Optional yay or paru installation
- **Browser selection**: Firefox, LibreWolf, Chromium, Brave, or none
- **Wine + Bottles**: Optional Windows app compatibility
- **eGPU support**: Thunderbolt NVIDIA auto-setup (bolt + systemd service + xorg config)
- **Bundled configs**: Nord-themed starter templates for all WMs
- **Custom fonts**: JetBrains Mono Nerd, Iosevka Nerd, MesloLGS NF, and more
- **Auto-start**: Boots straight to your desktop — no manual `startx` needed
- **Resumable**: Saves state between steps, resume if interrupted

## Quick Start

Boot into the Arch live ISO, connect to wifi, then:

```bash
iwctl station wlan0 connect <SSID>

# Latest release
curl -LO https://gitlab.com/code-pumpkin/arch-linux/-/archive/main/arch-linux-main.tar.gz
tar xzf arch-linux-main.tar.gz && cd arch-linux-main

# Or clone the repo
git clone https://gitlab.com/code-pumpkin/arch-linux.git && cd arch-linux

chmod +x arch-install.sh
./arch-install.sh
```

The installer walks you through 11 steps:

`UEFI check → Disk selection → Partitioning → Formatting → WiFi → Base install → System config → Bootloader → Packages → User setup → Reboot`

## i3 Custom Option

Option 2 deploys a full i3 rice with:

- Polybar with 14 custom scripts (battery, temps, VPN, privacy monitor, network menu, etc.)
- Picom compositor with animations
- Dunst notifications with sound alerts
- Rofi launcher with 5 themes
- Kitty terminal
- Flameshot screenshots
- Fastfetch system info
- Custom screenlayout scripts
- System monitor daemon with audio alerts

## Directory Structure

```
arch-linux/
├── arch-install.sh          # Main installer script
├── configs/
│   ├── i3/                  # Starter i3 config (alacritty, polybar, picom, dunst, rofi)
│   │   └── packages.txt     # i3 packages
│   ├── user_custom/         # Full i3 rice (kitty, 14 polybar scripts, sounds, etc.)
│   │   ├── packages.txt     # user_custom packages
│   │   ├── librewolf/       # LibreWolf extensions, chrome CSS, user.js
│   │   ├── deploy-librewolf.sh
│   │   └── screenlayout/    # Display layout scripts
│   ├── sway/                # Sway + waybar, mako, wofi, foot
│   │   └── packages.txt
│   ├── hyprland/            # Hyprland + waybar, wofi, foot
│   │   └── packages.txt
│   ├── kde/                 # KDE kwinrc + plasma panel layout
│   │   └── packages.txt
│   └── custom_template/     # Template for creating your own config
├── fonts/                   # Custom TTF fonts (JetBrains Mono Nerd, Iosevka, etc.)
└── README.md
```

Each config directory owns its own `packages.txt` — add or remove packages there without touching `arch-install.sh`.

## Requirements

- UEFI system (no legacy BIOS)
- Internet connection (ethernet or wifi)
- Arch Linux live ISO

## License

MIT
