# Custom Config Template

This is a template for creating your own desktop environment configuration
that the arch-install.sh script will automatically discover and deploy.

## How It Works

The installer looks for an `index.sh` in your config directory. When you
select your config during installation, it copies the directory to the
new system and runs `index.sh` to deploy everything.

## Quick Start

1. Copy this directory:
   ```
   cp -r configs/custom_template configs/my_setup
   ```

2. Add your config files (i3, sway, polybar, kitty, etc.)

3. Edit `index.sh` to deploy them

4. Add your setup as a menu option in `arch-install.sh` (see below)

## Available Variables

Your `index.sh` receives these variables:

| Variable      | Description                          | Example                    |
|---------------|--------------------------------------|----------------------------|
| `$home`       | User's home directory                | `/home/alice`              |
| `$cfg`        | User's .config directory             | `/home/alice/.config`      |
| `$SRC`        | Path to your config files (source)   | `/root/wm-configs`         |
| `$username`   | The created username                 | `alice`                    |
| `$KB_LAYOUT`  | Selected keyboard layout             | `us`, `de`, `fr`           |
| `$KB_VARIANT` | Selected keyboard variant (or empty) | `colemak_dh`, `dvorak`, `` |

## Directory Structure

```
configs/my_setup/
├── index.sh          ← REQUIRED — deployment script
├── packages.txt      ← OPTIONAL — pacman packages to install (one per line)
├── i3/
│   └── config
├── polybar/
│   ├── config.ini
│   └── launch.sh
├── kitty/
│   └── kitty.conf
└── ...any other configs
```

## packages.txt

If your config needs specific packages, list them in `packages.txt` (one per line).
Lines starting with `#` are ignored. The installer reads this automatically.

```
# Window manager
i3-wm
i3lock
polybar
picom

# Terminal
kitty

# Tools
fzf
bat
```

## Example index.sh

```bash
#!/bin/bash
# My custom setup deployment
# Variables: $home, $cfg, $SRC, $username, $KB_LAYOUT, $KB_VARIANT

# Deploy i3 config
mkdir -p "$cfg/i3"
cp "$SRC/i3/config" "$cfg/i3/config"

# Deploy polybar
mkdir -p "$cfg/polybar"
cp "$SRC/polybar/"* "$cfg/polybar/"
chmod +x "$cfg/polybar/"*.sh

# Deploy terminal config
mkdir -p "$cfg/kitty"
cp "$SRC/kitty/kitty.conf" "$cfg/kitty/"

# Set keyboard layout in i3
if [ -n "$KB_VARIANT" ]; then
    echo "exec_always --no-startup-id setxkbmap $KB_LAYOUT -variant $KB_VARIANT" >> "$cfg/i3/config"
else
    echo "exec_always --no-startup-id setxkbmap $KB_LAYOUT" >> "$cfg/i3/config"
fi

# Files that go to $home (not .config)
# cp "$SRC/some-dotfile" "$home/.some-dotfile"
```

## Adding to the Installer Menu

In `arch-install.sh`, find the WM selection menu and add your option:

> **Note:** If using the "Custom from Git" option (option 6) during install,
> your repo must be **public**. SSH keys and Git credentials won't be
> configured yet on a fresh system.

```bash
echo -e "  ${BOLD}7)${NC} My Setup  — Description of your setup"
# ...
7) WM_CHOICE="my_setup"; break ;;
```

And add matching packages in the `case` block:

```bash
my_setup)
    wm_pkgs="i3-wm polybar dunst rofi kitty ..."
    ;;
```

## Tips

- Use `2>/dev/null || true` for optional files that may not exist
- Use `chmod +x` on any scripts after copying
- Files needing root (e.g., `/etc/X11/xorg.conf`) work because the
  script runs inside `arch-chroot` as root
- For user-level commands, use `sudo -u "$username" <command>`
- Test with a dry run:
  ```bash
  home=/tmp/test cfg=/tmp/test/.config SRC=./configs/my_setup \
    username=test KB_LAYOUT=us KB_VARIANT="" bash ./configs/my_setup/index.sh
  ```
