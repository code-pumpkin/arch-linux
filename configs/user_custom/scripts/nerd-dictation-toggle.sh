#!/bin/bash
if pgrep -f "nerd-dictation begin" > /dev/null; then
    nerd-dictation end
    notify-send "Dictation" "Stopped"
else
    nerd-dictation begin
    notify-send "Dictation" "Started - speak now"
fi
