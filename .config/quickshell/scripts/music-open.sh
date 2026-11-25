#!/usr/bin/env bash
# "Open with Music": hands audio files to the shell's Music player
# (shell-music.desktop, Exec=music-open.sh %F). Falls back to plain mpv when
# the shell isn't running.
[ $# -gt 0 ] || exec qs ipc call music open
files=()
for f in "$@"; do
    f=${f#file://}
    [ -e "$f" ] && files+=("$(realpath -- "$f")")
done
[ ${#files[@]} -gt 0 ] || exit 1
qs ipc call music playFiles "$(printf '%s\n' "${files[@]}")" 2>/dev/null || exec mpv --player-operation-mode=pseudo-gui -- "${files[@]}"
