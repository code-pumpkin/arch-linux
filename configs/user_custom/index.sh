#!/bin/bash
# user_custom (Hafeezh's i3 rice) config deployment
# Variables provided by caller: $home, $cfg, $SRC, $username

# --- Desktop environment configs ---
mkdir -p "$cfg/i3" "$cfg/polybar" "$cfg/picom" "$cfg/dunst" "$cfg/rofi" \
         "$cfg/kitty" "$cfg/fastfetch" "$cfg/scripts" "$cfg/sounds" "$home/vpn"
cp "$SRC/i3/"* "$cfg/i3/"
cp "$SRC/polybar/"* "$cfg/polybar/"
cp "$SRC/picom/"* "$cfg/picom/"
cp "$SRC/dunst/"* "$cfg/dunst/"
cp "$SRC/rofi/"* "$cfg/rofi/"
cp "$SRC/kitty/"* "$cfg/kitty/"
cp "$SRC/fastfetch/"* "$cfg/fastfetch/"
cp "$SRC/scripts/"* "$cfg/scripts/"
cp "$SRC/sounds/"* "$cfg/sounds/"
cp "$SRC/vpn/README.md" "$home/vpn/" 2>/dev/null || true
chmod +x "$cfg/polybar/"*.sh "$cfg/dunst/"*.sh "$cfg/scripts/"*

# --- Screenlayout ---
if [ -d "$SRC/screenlayout" ]; then
    mkdir -p "$home/.screenlayout"
    cp "$SRC/screenlayout/"* "$home/.screenlayout/"
    chmod +x "$home/.screenlayout/"*.sh
fi

# --- xorg.conf (substitute Intel BusID) ---
if [ -f "$SRC/xorg.conf" ]; then
    cp "$SRC/xorg.conf" /etc/X11/xorg.conf
    INTEL_PCI=$(lspci | grep -i 'vga.*intel' | head -1 | cut -d' ' -f1)
    if [ -n "$INTEL_PCI" ]; then
        INTEL_BUSID="PCI:$(echo "$INTEL_PCI" | awk -F'[:.]' '{printf "%d:%d:%d", $1, $2, $3}')"
        sed -i "s|__INTEL_BUSID__|$INTEL_BUSID|g" /etc/X11/xorg.conf
    fi
fi

# --- Additional app configs ---
for app in bat lf yazi wezterm nvim fontconfig; do
    if [ -d "$SRC/$app" ]; then
        mkdir -p "$cfg/$app"
        cp -r "$SRC/$app/"* "$cfg/$app/"
    fi
done
[ -f "$SRC/nvim/.neoconf.json" ] && cp "$SRC/nvim/.neoconf.json" "$cfg/nvim/"
[ -f "$SRC/nvim/.gitignore" ] && cp "$SRC/nvim/.gitignore" "$cfg/nvim/"
chmod +x "$cfg/lf/preview.sh" "$cfg/lf/cleaner.sh" 2>/dev/null || true

# --- GTK dark theme ---
cp "$SRC/gtk-3.0/.gtkrc-2.0" "$home/.gtkrc-2.0" 2>/dev/null || true
cp "$SRC/gtk-3.0/.xsettingsd" "$home/.xsettingsd" 2>/dev/null || true
mkdir -p "$cfg/gtk-3.0" "$cfg/gtk-4.0"
cp "$SRC/gtk-3.0/settings.ini" "$cfg/gtk-3.0/" 2>/dev/null || true
cp "$SRC/gtk-4.0/settings.ini" "$cfg/gtk-4.0/" 2>/dev/null || true

# --- Qt theme ---
for qt in qt5ct qt6ct; do
    if [ -d "$SRC/$qt" ]; then
        mkdir -p "$cfg/$qt"
        cp "$SRC/$qt/"* "$cfg/$qt/"
    fi
done

# --- Librewolf (bootstrap profile dir if missing, then deploy) ---
if [ -d "$SRC/librewolf" ]; then
    lw_dir="$home/.librewolf"

    if [ ! -f "$lw_dir/profiles.ini" ]; then
        # Profile ID: 8 random alphanumeric chars (matches Firefox's real format)
        profile_id="$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8).default-default"
        # Install hash is fixed — Firefox derives it from the install path (/usr/lib/librewolf)
        # and is consistent across all Arch installs of librewolf-bin
        install_hash="6C1CE26D3274EA5B"

        mkdir -p "$lw_dir/$profile_id/chrome" "$lw_dir/$profile_id/extensions"

        cat > "$lw_dir/profiles.ini" <<EOF
[Profile0]
Name=default
IsRelative=1
Path=${profile_id}

[General]
StartWithLastProfile=1
Version=2

[Install${install_hash}]
Default=${profile_id}
Locked=1
EOF

        cat > "$lw_dir/installs.ini" <<EOF
[${install_hash}]
Default=${profile_id}
Locked=1
EOF
        echo "Librewolf profile directory bootstrapped: $profile_id"
    fi

    lw_profile=$(grep -oP 'Path=\K.*' "$lw_dir/profiles.ini" | head -1)
    if [ -n "$lw_profile" ]; then
        mkdir -p "$lw_dir/$lw_profile/chrome" "$lw_dir/$lw_profile/extensions"
        cp "$SRC/librewolf/user.js"              "$lw_dir/$lw_profile/"
        cp "$SRC/librewolf/search.json.mozlz4"   "$lw_dir/$lw_profile/" 2>/dev/null || true
        cp "$SRC/librewolf/chrome/"*             "$lw_dir/$lw_profile/chrome/" 2>/dev/null || true
        cp "$SRC/librewolf/extensions/"*         "$lw_dir/$lw_profile/extensions/" 2>/dev/null || true
        cp "$SRC/librewolf/.tridactylrc"         "$home/.tridactylrc" 2>/dev/null || true
        chown -R "$username:$username" "$lw_dir"
        echo "Librewolf profile configured: $lw_profile"
    fi
fi
