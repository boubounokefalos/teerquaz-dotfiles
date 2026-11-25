#!/bin/sh
# hold-inhibit.sh WHAT MODE WHY
# Holds a logind inhibitor (systemd-inhibit) until this process is killed or
# the shell that started it exits. The inner loop also ends when
# systemd-inhibit itself is killed, so nothing is left behind.
p=$PPID
exec systemd-inhibit --what="$1" --mode="$2" --who="Shell" --why="$3" \
    sh -c 'i=$PPID; while kill -0 "$0" 2>/dev/null && kill -0 "$i" 2>/dev/null; do sleep 1; done' "$p"
