# Rebuild after every Hyprland update:  make && hyprctl reload
#   (after an update the plugin is not loaded at all, so the reload loads it fresh)
# After changing main.cpp: make, then log out and back in. Do NOT hot-swap it
# (hyprctl plugin unload/load) in a running session — that crashed Hyprland once.
# built-for records the hyprland package this .so matches; shell-bridge.lua only
# loads the plugin while that exact package is installed.
all:
	g++ -shared -fPIC -std=c++2b -O2 main.cpp -o shell-bridge.so `pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon`
	pacman -Q hyprland | awk '{print $$1 "-" $$2}' > built-for
