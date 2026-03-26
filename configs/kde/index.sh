#!/bin/bash
# KDE Plasma config deployment
# Variables provided by caller: $home, $cfg, $SRC

cp "$SRC/kwinrc" "$cfg/kwinrc" 2>/dev/null || true
cp "$SRC/plasma-org.kde.plasma.desktop-appletsrc" "$cfg/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true
