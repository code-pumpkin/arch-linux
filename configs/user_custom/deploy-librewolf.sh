#!/bin/bash
# Deploys LibreWolf profile configs.
# Bootstraps ~/.librewolf if it doesn't exist yet (no need to open LibreWolf first).

SRC="$(cd "$(dirname "$0")/librewolf" && pwd)"
lw_dir="$HOME/.librewolf"

if [ ! -f "$lw_dir/profiles.ini" ]; then
    profile_id="$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8).default-default"
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
    echo "Bootstrapped LibreWolf profile: $profile_id"
fi

lw_profile=$(grep -oP 'Path=\K.*' "$lw_dir/profiles.ini" | head -1)
mkdir -p "$lw_dir/$lw_profile/chrome" "$lw_dir/$lw_profile/extensions"
cp "$SRC/user.js"                  "$lw_dir/$lw_profile/"
cp "$SRC/search.json.mozlz4"       "$lw_dir/$lw_profile/" 2>/dev/null || true
cp "$SRC/chrome/"*                 "$lw_dir/$lw_profile/chrome/" 2>/dev/null || true
cp "$SRC/extensions/"*             "$lw_dir/$lw_profile/extensions/" 2>/dev/null || true
[ -f "$SRC/.tridactylrc" ] && cp "$SRC/.tridactylrc" "$HOME/.tridactylrc"

echo "LibreWolf config deployed to $lw_dir/$lw_profile"
