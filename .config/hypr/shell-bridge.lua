-- Local Hyprland plugin ~/.config/hypr/plugins/shell-bridge: apps' own minimize
-- button/menu → the shell's minimize, and right-clicks on hyprbars title bars →
-- the shell's title-bar menu (hyprbars swallows those before Lua binds run).
-- Loaded only while the Hyprland package it was built against is installed:
-- after an update, run `make` in that folder.
local dir = os.getenv("HOME") .. "/.config/hypr/plugins/shell-bridge/"
local f = io.open(dir .. "built-for", "r")
if not f then return end
local pkg = (f:read("l") or ""):gsub("%s", ""); f:close()
local d = io.open("/var/lib/pacman/local/" .. pkg .. "/desc", "r")
if not d then return end   -- Hyprland was updated: plugin needs a rebuild
d:close()
pcall(hl.plugin.load, dir .. "shell-bridge.so")

-- show_window_menu from apps' own title bars (GTK, libadwaita): the plugin
-- calls this with the window and the pointer; opens the same menu as the
-- hyprbars title bars (TitleMenu.qml).
function _G.titlebar_menu_for(address, x, y)
    local w = hl.get_window("address:" .. address)
    if not w then return end
    local max = (tonumber(w.fullscreen) or 0) == 1 and 1 or 0
    hl.exec_cmd(string.format("qs ipc call titlemenu open %s %d %d %d", w.address, math.floor(x), math.floor(y), max))
end
