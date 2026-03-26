#!/bin/bash
# Sway config deployment
# Variables provided by caller: $home, $cfg, $SRC, $KB_LAYOUT, $KB_VARIANT

mkdir -p "$cfg/sway" "$cfg/waybar" "$cfg/mako" "$cfg/wofi" "$cfg/foot"
cp "$SRC/config" "$cfg/sway/config"
cp "$SRC/waybar/"* "$cfg/waybar/"
cp "$SRC/mako/"* "$cfg/mako/"
cp "$SRC/wofi/"* "$cfg/wofi/"
cp "$SRC/foot/"* "$cfg/foot/"

# Set keyboard layout
sed -i "s/xkb_layout us/xkb_layout $KB_LAYOUT/" "$cfg/sway/config"
if [ -n "$KB_VARIANT" ]; then
    sed -i "/xkb_layout $KB_LAYOUT/a\\    xkb_variant $KB_VARIANT" "$cfg/sway/config"
fi
