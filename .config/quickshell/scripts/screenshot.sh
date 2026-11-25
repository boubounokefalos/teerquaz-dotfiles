#!/bin/sh
# screenshot.sh area|screen|window
# Saves to ~/Pictures/Screenshots, copies to the clipboard, then shows a
# notification with the picture and Edit / Open / Folder buttons.
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
f="$dir/$(date +%F_%H-%M-%S).png"

case ${1:-area} in
    area)
        geo=$(slurp -d < /dev/null) || exit 0   # Esc cancels quietly (stdin: slurp would wait for boxes on a pipe)
        grim -g "$geo" "$f" ;;
    window)
        id=$(hyprctl activewindow -j | sed -n 's/.*"stableId": "\([^"]*\)".*/\1/p')
        [ -n "$id" ] || exit 1
        grim -T "$id" "$f" ;;
    screen)
        mon=$(hyprctl activeworkspace -j | sed -n 's/.*"monitor": "\([^"]*\)".*/\1/p')   # the screen in use
        grim ${mon:+-o "$mon"} "$f" ;;
esac || exit 1

wl-copy --type image/png < "$f"
pw-play /usr/share/sounds/freedesktop/stereo/camera-shutter.oga >/dev/null 2>&1 &

if command -v satty >/dev/null; then edit="-A edit=Edit"; else edit=""; fi
choice=$(notify-send -a Screenshot -i "$f" -A default=Open $edit -A open=Open -A folder="Show in folder" \
    "Screenshot taken" "Copied to the clipboard and saved as $(basename "$f")")
case $choice in
    edit) satty --filename "$f" --output-filename "$f" --copy-command wl-copy --early-exit ;;
    open|default) xdg-open "$f" ;;
    folder) thunar "$dir" ;;
esac
