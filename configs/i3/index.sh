#!/bin/bash
# i3 config deployment
# Variables provided by caller: $home, $cfg, $SRC, $KB_LAYOUT, $KB_VARIANT, $username

mkdir -p "$cfg/i3" "$cfg/polybar" "$cfg/picom" "$cfg/dunst" "$cfg/rofi" "$cfg/alacritty"
cp "$SRC/config" "$cfg/i3/config"
cp "$SRC/polybar/"* "$cfg/polybar/"
cp "$SRC/picom/"* "$cfg/picom/"
cp "$SRC/dunst/"* "$cfg/dunst/"
cp "$SRC/rofi/"* "$cfg/rofi/"
cp "$SRC/alacritty/"* "$cfg/alacritty/"
chmod +x "$cfg/polybar/launch.sh"

# Set keyboard layout
if [ -n "$KB_VARIANT" ]; then
    echo "exec_always --no-startup-id setxkbmap $KB_LAYOUT -variant $KB_VARIANT" >> "$cfg/i3/config"
else
    echo "exec_always --no-startup-id setxkbmap $KB_LAYOUT" >> "$cfg/i3/config"
fi
