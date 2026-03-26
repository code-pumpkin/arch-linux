#!/bin/bash
# Hyprland config deployment
# Variables provided by caller: $home, $cfg, $SRC, $KB_LAYOUT, $KB_VARIANT

mkdir -p "$cfg/hypr" "$cfg/waybar" "$cfg/wofi" "$cfg/foot"
cp "$SRC/hyprland.conf" "$cfg/hypr/hyprland.conf"
cp "$SRC/waybar/"* "$cfg/waybar/"
cp "$SRC/wofi/"* "$cfg/wofi/"
cp "$SRC/foot/"* "$cfg/foot/"

# Set keyboard layout
sed -i "s/kb_layout = us/kb_layout = $KB_LAYOUT/" "$cfg/hypr/hyprland.conf"
if [ -n "$KB_VARIANT" ]; then
    sed -i "/kb_layout = $KB_LAYOUT/a\\    kb_variant = $KB_VARIANT" "$cfg/hypr/hyprland.conf"
fi
