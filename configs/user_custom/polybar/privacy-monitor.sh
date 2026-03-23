#!/bin/bash

# FA icons via font-1 (T2)
ICON_CAM=$'%{T2}\uf030%{T-}'
ICON_MIC=$'%{T2}\uf130%{T-}'
ICON_MIC_MUTE=$'%{T2}\uf131%{T-}'
ICON_SCR=$'%{T2}\uf108%{T-}'

get_camera_status() {
    local apps=$(lsof /dev/video* 2>/dev/null | awk 'NR>1 {print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
    if [ -n "$apps" ]; then
        echo "%{F#F38BA8}${ICON_CAM}%{F-}"
    else
        echo "%{F#585B70}${ICON_CAM}%{F-}"
    fi
}

get_all_mic_sources() {
    pactl list sources short 2>/dev/null | grep -v '\.monitor' | awk '{print $2}'
}

get_mic_status() {
    local all_muted=true
    while IFS= read -r src; do
        if ! pactl get-source-mute "$src" 2>/dev/null | grep -q 'yes'; then
            all_muted=false
            break
        fi
    done < <(get_all_mic_sources)
    local apps=$(pactl list source-outputs 2>/dev/null | grep 'application.name' | sed 's/.*= "//;s/"//' | sort -u | tr '\n' ',' | sed 's/,$//')

    if $all_muted; then
        echo "%{F#585B70}${ICON_MIC_MUTE}%{F-}"
    elif [ -n "$apps" ]; then
        echo "%{F#F38BA8}${ICON_MIC}%{F-}"
    else
        echo "%{F#585B70}${ICON_MIC}%{F-}"
    fi
}

get_screen_share_status() {
    local sharing=0

    # Check for browser/app sharing indicator windows by parsing i3 window names properly
    # Firefox/LibreWolf creates a window named exactly "LibreWolf — Sharing Indicator" or "Firefox — Sharing Indicator"
    # Chromium creates "your_site is sharing your screen." as a small popup window
    # We parse the JSON to only match actual window "name" fields, not page content
    local sharing_windows=$(i3-msg -t get_tree 2>/dev/null | python3 -c "
import json, sys
def walk(node):
    name = node.get('name') or ''
    wp = node.get('window_properties') or {}
    title = wp.get('title', '')
    # Match exact sharing indicator window patterns
    if 'Sharing Indicator' in name or 'Sharing Indicator' in title:
        print(name)
    for n in node.get('nodes', []) + node.get('floating_nodes', []):
        walk(n)
walk(json.load(sys.stdin))
" 2>/dev/null)
    if [ -n "$sharing_windows" ]; then
        sharing=1
    fi

    # Check for screen recording tools (actively capturing screen)
    # Bracket trick [s] prevents pgrep from matching its own process
    if pgrep -x 'simplescreenrecorder\|kazam\|peek\|wf-recorder\|gpu-screen-recorder' >/dev/null 2>&1; then
        sharing=1
    fi
    if pgrep -f '[f]fmpeg.*x11grab' >/dev/null 2>&1; then
        sharing=1
    fi

    # Check for OBS actively running (it's only used for recording/streaming)
    if pgrep -x 'obs' >/dev/null 2>&1 || pgrep -f '[o]bs-studio' >/dev/null 2>&1; then
        sharing=1
    fi

    # Check for remote desktop software actively serving (these expose your screen by design)
    if pgrep -x 'x11vnc\|vino\|krfb\|anydesk\|rustdesk\|teamviewer' >/dev/null 2>&1; then
        sharing=1
    fi

    # Check PipeWire for active screencast streams (exclude Video/Source which is just webcams)
    if pw-dump 2>/dev/null | grep -qE '"Stream/Output/Video"|"Stream/Input/Video"'; then
        sharing=1
    fi

    # Check for active xdg-desktop-portal screencast sessions via D-Bus
    if dbus-send --print-reply --dest=org.freedesktop.portal.Desktop \
        /org/freedesktop/portal/desktop org.freedesktop.DBus.Introspectable.Introspect 2>/dev/null \
        | grep -q 'node name="session'; then
        sharing=1
    fi

    # Check for listening ports (VNC: 5900, RDP: 3389, AnyDesk: 7070)
    if ss -tlnp 2>/dev/null | grep -E ':5900|:3389|:7070' | grep -qv '127.0.0.1'; then
        sharing=1
    fi

    if [ "$sharing" -eq 1 ]; then
        echo "%{F#F38BA8}${ICON_SCR}%{F-}"
    else
        echo "%{F#585B70}${ICON_SCR}%{F-}"
    fi
}

toggle_all_mics() {
    while IFS= read -r src; do
        pactl set-source-mute "$src" toggle
    done < <(get_all_mic_sources)
}

show_notification() {
    local msg="Privacy Monitor\n"

    msg+="Camera:\n"
    local cam=$(lsof /dev/video* 2>/dev/null | awk 'NR>1 {print "  "$1" (PID:"$2")"}')
    [ -n "$cam" ] && msg+="$cam\n" || msg+="  Not in use\n"

    msg+="\nMicrophone:\n"
    while IFS= read -r src; do
        local mic_status=$(pactl get-source-mute "$src" 2>/dev/null)
        msg+="  $src: $mic_status\n"
    done < <(get_all_mic_sources)
    local mic_apps=$(pactl list source-outputs 2>/dev/null | grep 'application.name' | sed 's/.*= "//;s/"//' | sort -u | awk '{print "  "$0}')
    [ -n "$mic_apps" ] && msg+="$mic_apps\n" || msg+="  No apps\n"

    msg+="\nScreen Share:\n"
    local indicator=$(i3-msg -t get_tree 2>/dev/null | python3 -c "
import json, sys
def walk(node):
    name = node.get('name') or ''
    wp = node.get('window_properties') or {}
    title = wp.get('title', '')
    if 'Sharing Indicator' in name or 'Sharing Indicator' in title:
        print(name)
    for n in node.get('nodes', []) + node.get('floating_nodes', []):
        walk(n)
walk(json.load(sys.stdin))
" 2>/dev/null)
    local streams=$(pw-dump 2>/dev/null | grep -cE '"Stream/Output/Video"|"Stream/Input/Video"')
    local recorders=$(pgrep -x 'obs\|simplescreenrecorder\|kazam\|peek\|wf-recorder\|gpu-screen-recorder' 2>/dev/null | xargs -r -I{} ps -p {} -o comm= | sort -u | awk '{print "  "$0}')
    local remote=$(pgrep -x 'x11vnc\|vino\|krfb\|anydesk\|rustdesk\|teamviewer' 2>/dev/null | xargs -r -I{} ps -p {} -o comm= | sort -u | awk '{print "  "$0}')
    [ -n "$indicator" ] && msg+="  Browser: $indicator\n"
    [ "$streams" -gt 0 ] && msg+="  PipeWire streams: $streams\n"
    [ -n "$recorders" ] && msg+="  Recorders:\n$recorders\n"
    [ -n "$remote" ] && msg+="  Remote desktop:\n$remote\n"
    [ -z "$indicator" ] && [ "$streams" -eq 0 ] && [ -z "$recorders" ] && [ -z "$remote" ] && msg+="  Not sharing\n"

    notify-send "Privacy" "$msg" -t 6000
}

show_menu() {
    local menu="Toggle Mic Mute\n"
    menu+="Show Details\n"
    menu+="Kill Camera Apps\n"

    choice=$(echo -e "$menu" | rofi -dmenu -i -p "Privacy" -lines 3)

    case "$choice" in
        *"Toggle"*)
            toggle_all_mics
            notify-send "Microphone" "Toggled mute on all mics"
            ;;
        *"Details"*)
            show_notification
            ;;
        *"Kill"*)
            lsof -t /dev/video* 2>/dev/null | xargs -r kill
            notify-send "Camera" "Killed camera apps"
            ;;
    esac
}

case "$1" in
    menu) show_menu ;;
    notify) show_notification ;;
    toggle-mic) toggle_all_mics ;;
    *) echo "$(get_camera_status) $(get_mic_status) $(get_screen_share_status)" ;;
esac
