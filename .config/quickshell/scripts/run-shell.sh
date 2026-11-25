#!/usr/bin/env bash
# Runs Quickshell (bar + wallpaper) and starts it again when it dies, so the
# screen never stays grey. Everything qs prints goes to
# ~/.local/state/quickshell/qs.log (kept across reboots), and each time qs
# exits, Hyprland's own line about it from the journal is added there too.
#
#   run-shell.sh            start the shell (Hyprland autostart)
#   run-shell.sh --restart  restart it (Super+Shift+Esc)
#
# Only one copy runs per session. It stops once Hyprland is gone (log out),
# and gives up after 5 quick deaths in a row instead of looping forever.

state=${XDG_STATE_HOME:-$HOME/.local/state}/quickshell
log=$state/qs.log
lock=$XDG_RUNTIME_DIR/quickshell-run-shell.lock
mkdir -p "$state"

say() { printf '=== %s %s\n' "$(date '+%F %T')" "$*" >>"$log"; }
compositor_alive() { [ -S "$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY:-wayland-1}" ]; }

if [ "$1" = --restart ]; then
    if flock -n "$lock" true; then
        # No copy of this script is running: stop any stray qs, then become it.
        pkill -x qs
        # Only living ones: a dead qs nobody collected (e.g. one started in a
        # terminal) would otherwise keep this waiting forever.
        while pgrep -x -r R,S,D qs >/dev/null; do sleep 0.1; done
        exec "$0"
    fi
    # The running copy notices qs exiting and starts it again.
    say "restart asked for"
    exec pkill -x qs
fi

exec 9>"$lock"
flock -n 9 || exit 0

# Keep the log small: only the last 5000 lines from earlier runs.
if [ -f "$log" ]; then
    tail -n 5000 "$log" >"$log.tmp" && mv "$log.tmp" "$log"
fi

# More room for open files than the default 1024: running out freezes the
# whole desktop (2026-11-23, leaking window previews). The hard limit allows it.
ulimit -n 65536 2>/dev/null || ulimit -n "$(ulimit -Hn)"
# Window pictures still leak about one file each (Quickshell screencopy on
# NVIDIA), so past this many open files qs is restarted before it runs out.
fdmax=30000

quick=0
while compositor_alive; do
    started=$(date +%s)
    say "starting qs"
    env -u QT_WAYLAND_DISABLED_INTERFACES qs >>"$log" 2>&1 9>&- &
    qspid=$!
    # Guard: every 2 minutes, check how many files qs has open.
    (
        while sleep 120; do
            n=$(ls "/proc/$qspid/fd" 2>/dev/null | wc -l)
            if (( n > fdmax )); then
                say "qs has $n files open (leak); restarting it"
                kill "$qspid"
                break
            fi
        done
    ) 9>&- &
    guard=$!
    wait "$qspid"
    code=$?
    kill "$guard" 2>/dev/null
    say "qs exited with code $code"
    # Hyprland logs "error in client communication (pid N)" when it drops a client.
    journalctl -b -t session --since "@$started" --no-pager -q 2>/dev/null \
        | grep -i 'client communication' >>"$log"

    compositor_alive || break
    if (( $(date +%s) - started < 10 )); then quick=$((quick + 1)); else quick=0; fi
    if (( quick >= 5 )); then
        say "qs died 5 times within seconds of starting; giving up (Super+Shift+Esc to try again)"
        exit 1
    fi
    sleep 1
done
say "Hyprland is gone; stopping"
