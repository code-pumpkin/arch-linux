#!/bin/bash
# System Monitor — CPU & RAM alerts
#
# Thresholds:
#   ≥95%  severe-warning.mp3  critical  (2 min cooldown)
#   ≥90%  warning.mp3         critical  (2 min cooldown)
#   ≥70%  attention.mp3       normal    (10 min cooldown)
#   spike warning-original.mp3 normal   (10 min cooldown)
#
# Guardrails:
#   ≥95%  renice +19 top hogs  (30s cooldown)
#   ≥98%  SIGSTOP top hogs     (30s cooldown)
#   <85%  auto-resume stopped

SOUNDS="$HOME/.config/sounds"
COOLDOWN_HIGH=120   # 2 min for ≥90%
COOLDOWN_LOW=600    # 10 min for <90%
SPIKE=12

# --- state ---
PREV_TOTAL=0 PREV_IDLE=0 PREV_CPU=0 PREV_MEM=0 TICK=0
LAST_CPU_ALERT=0 LAST_MEM_ALERT=0
LAST_GUARDRAIL=0
PROTECTED="polybar|i3|dunst|pulseaudio|pipewire|Xorg|systemd|dbus|ssh|bash|system-monitor"
STOPPED_PIDS=()

# --- readers ---

read_cpu() {
  read -r _ u n s id io ir si st g gn < /proc/stat
  local t=$((u+n+s+id+io+ir+si+st+g+gn)) i=$((id+io))
  if [ "$PREV_TOTAL" -eq 0 ]; then
    PREV_TOTAL=$t PREV_IDLE=$i CPU=0; return
  fi
  local dt=$((t-PREV_TOTAL)) di=$((i-PREV_IDLE))
  PREV_TOTAL=$t PREV_IDLE=$i
  [ "$dt" -eq 0 ] && CPU=0 || CPU=$(((dt-di)*100/dt))
}

read_mem() {
  MEM=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%.0f",(t-a)*100/t}' /proc/meminfo)
}

# --- audio ---

play_sound() {
  pkill -f "ffplay.*$SOUNDS" 2>/dev/null
  local sink
  if [ "$(pactl list sinks short 2>/dev/null | wc -l)" -gt 1 ]; then
    sink=$(pactl list sinks short 2>/dev/null | grep -vi 'bluetooth\|usb\|hdmi' | head -1 | awk '{print $2}')
    : "${sink:=$(pactl list sinks short 2>/dev/null | head -1 | awk '{print $2}')}"
    PULSE_SINK="$sink" ffplay -nodisp -autoexit -loglevel quiet "$1" &
  elif pactl list sinks 2>/dev/null | grep -qi 'Active Port.*headphone'; then
    ffplay -nodisp -autoexit -loglevel quiet -volume 30 "$1" &
  else
    ffplay -nodisp -autoexit -loglevel quiet "$1" &
  fi
}

# --- guardrails ---

guardrail() {
  local val=$1 type=$2
  [ "$type" != "cpu" ] && return
  local now=$(date +%s)

  if [ "$val" -lt 85 ] && [ ${#STOPPED_PIDS[@]} -gt 0 ]; then
    for p in "${STOPPED_PIDS[@]}"; do kill -CONT "$p" 2>/dev/null; done
    notify-send -u normal "GUARDRAIL" "Resumed paused processes — CPU back to ${val}%" -t 4000
    STOPPED_PIDS=()
    return
  fi

  [ $((now-LAST_GUARDRAIL)) -lt 30 ] && return

  if [ "$val" -ge 98 ]; then
    local pids=$(ps -u "$USER" -o pid=,pcpu=,comm= --sort=-pcpu | grep -vE "$PROTECTED" | head -3 | awk '{print $1}')
    for p in $pids; do kill -STOP "$p" 2>/dev/null && STOPPED_PIDS+=("$p"); done
    notify-send -u critical "GUARDRAIL" "Paused top CPU hogs — CPU ${val}%, will resume when it calms down" -t 6000
    LAST_GUARDRAIL=$now
  elif [ "$val" -ge 95 ]; then
    local pids=$(ps -u "$USER" -o pid=,pcpu=,comm= --sort=-pcpu | grep -vE "$PROTECTED" | head -3 | awk '{print $1}')
    for p in $pids; do renice -n 19 -p "$p" >/dev/null 2>&1; done
    notify-send -u normal "GUARDRAIL" "Deprioritized top CPU hogs — CPU ${val}%" -t 4000
    LAST_GUARDRAIL=$now
  fi
}

# --- alerting ---

alert() {
  local type=$1 val=$2 prev=$3
  local now=$(date +%s) diff=$((val-prev))
  local sound="" urg="normal" msg="" cooldown=$COOLDOWN_LOW
  local tvar="LAST_${type^^}_ALERT"

  # pick severity
  if   [ "$val" -ge 95 ];       then sound=severe-warning.mp3 urg=critical msg="system at its limit, close something NOW" cooldown=$COOLDOWN_HIGH
  elif [ "$val" -ge 90 ];       then sound=warning.mp3        urg=critical msg="getting dangerous, rein it in"            cooldown=$COOLDOWN_HIGH
  elif [ "$val" -ge 70 ];       then sound=attention.mp3                   msg="usage is high, keep an eye on it"
  elif [ "$diff" -ge "$SPIKE" ]; then sound=warning-original.mp3           msg="jumped +${diff}% in 1s"
  fi
  [ -z "$sound" ] && return

  # cooldown — one notification per cooldown period, no exceptions
  local elapsed=$((now-${!tvar}))
  [ "$elapsed" -lt "$cooldown" ] && return

  play_sound "$SOUNDS/$sound"
  notify-send -u "$urg" "${type^^} ${val}%" "${val}% — $msg" -t 4000
  eval "$tvar=$now"
}

# --- main loop ---

while true; do
  read_cpu; read_mem
  [ "$TICK" -gt 0 ] && { alert cpu "$CPU" "$PREV_CPU"; alert mem "$MEM" "$PREV_MEM"; guardrail "$CPU" cpu; }
  PREV_CPU=$CPU PREV_MEM=$MEM TICK=$((TICK+1))
  sleep 1
done
