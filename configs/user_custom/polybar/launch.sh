#!/usr/bin/env bash

# Terminate already running Polybar instances
killall -q polybar

# Wait until all Polybar processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch the Polybar bar
echo "---" | tee -a /tmp/polybar.log

# Launch single polybar instance
polybar --reload example 2>&1 | tee -a /tmp/polybar.log &

disown

# Confirm that Polybar was launched successfully
echo "Polybar launched..."
