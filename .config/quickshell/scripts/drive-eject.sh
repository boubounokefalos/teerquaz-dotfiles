#!/bin/sh
# drive-eject.sh DISK [NAME] — unmount every mounted partition of DISK
# (e.g. /dev/sdd), then power it off so it is safe to unplug.
disk=$1; name=${2:-Drive}
osd() { qs ipc call osd message "$1" "$2" >/dev/null 2>&1; }
for part in $(lsblk -nrpo PATH,MOUNTPOINT "$disk" | awk '$2 != "" { print $1 }'); do
    if ! err=$(udisksctl unmount --no-user-interaction -b "$part" 2>&1); then
        case $err in
            *busy*|*Busy*) osd eject "$name is in use — close the files on it first" ;;
            *) osd error "Couldn't eject $name" ;;
        esac
        exit 1
    fi
done
udisksctl power-off --no-user-interaction -b "$disk" >/dev/null 2>&1
osd check_circle "$name can be unplugged"
