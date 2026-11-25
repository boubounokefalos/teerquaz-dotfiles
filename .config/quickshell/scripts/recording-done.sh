#!/bin/sh
# recording-done.sh FILE — "recording saved" notification with Open / Folder.
f=$1
[ -s "$f" ] || exit 0
choice=$(notify-send -a "Screen recording" -i video-x-generic -A default=Open -A open=Open -A folder="Show in folder" \
    "Recording saved" "$(basename "$f") · $(du -h "$f" | cut -f1)")
case $choice in
    open|default) xdg-open "$f" ;;
    folder) thunar "$(dirname "$f")" ;;
esac
