#!/bin/bash
# Run this once after first boot, after opening LibreWolf at least once.
# Deploys user.js, search engines, chrome CSS, extensions and tridactylrc.

SRC="$HOME/librewolf-configs"
lw_dir="$HOME/.librewolf"

if [ ! -f "$lw_dir/profiles.ini" ]; then
    echo "LibreWolf profile not found. Open LibreWolf once, close it, then re-run this script."
    exit 1
fi

lw_profile=$(grep -oP 'Path=\K.*' "$lw_dir/profiles.ini" | head -1)
mkdir -p "$lw_dir/$lw_profile/chrome" "$lw_dir/$lw_profile/extensions"
cp "$SRC/user.js"                    "$lw_dir/$lw_profile/"
cp "$SRC/search.json.mozlz4"         "$lw_dir/$lw_profile/" 2>/dev/null || true
cp "$SRC/chrome/"*                   "$lw_dir/$lw_profile/chrome/" 2>/dev/null || true
cp "$SRC/extensions/"*               "$lw_dir/$lw_profile/extensions/" 2>/dev/null || true
[ -f "$SRC/.tridactylrc" ] && cp "$SRC/.tridactylrc" "$HOME/.tridactylrc"

echo "LibreWolf config deployed to $lw_dir/$lw_profile"
