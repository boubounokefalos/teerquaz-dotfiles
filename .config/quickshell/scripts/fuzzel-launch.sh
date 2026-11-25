#!/bin/sh
# fuzzel --launch-prefix when it runs over the overview: tell the shell an app
# was really started (so the overview closes to show it), then run the app.
qs ipc call overview fuzzelLaunched "$1" >/dev/null 2>&1 &
exec "$@"
