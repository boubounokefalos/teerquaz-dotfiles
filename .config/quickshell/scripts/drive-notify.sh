#!/bin/sh
# drive-notify.sh NAME MOUNTPOINT DISK — "drive ready" notification with
# Open / Eject buttons (notify-send waits for the click and prints its key).
name=$1; mnt=$2; disk=$3; here=$(dirname "$0")
choice=$(notify-send -a Drives -i drive-removable-media -A default=Open -A open=Open -A eject=Eject \
    "$name is ready" "Mounted at $mnt")
case $choice in
    open|default) xdg-open "$mnt" ;;
    eject) "$here/drive-eject.sh" "$disk" "$name" ;;
esac
