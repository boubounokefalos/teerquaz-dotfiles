#!/usr/bin/env bash
# Log out of Hyprland. Stop the desktop portals first: xdg-desktop-portal-hyprland
# segfaults if the compositor disappears under it, leaving a coredump every logout.
systemctl --user stop xdg-desktop-portal.service xdg-desktop-portal-hyprland.service \
    xdg-desktop-portal-gtk.service 2>/dev/null
exec hyprctl dispatch 'hl.dsp.exit()'
