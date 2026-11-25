-- Title bars (hyprbars plugin) for apps that don't draw their own and ask the
-- compositor for one, which Hyprland itself never draws (Thunar, Xarchiver, …).
-- Every other window keeps its own client-side title bar, so bars are off by
-- default and switched on per app below.
--
-- The plugin comes from the AUR (hyprland-plugin-hyprbars); keep it updated
-- together with Hyprland via `yay -Syu`. Without it, this file does nothing.

local c = require("colors")
local function rgb(hex) return "rgb(" .. hex .. ")" end

-- apps that get a bar (window class, lower case). One list for both the bar
-- rule (regex built below) and the right-click menu check at the end.
local BAR_CLASSES = { "thunar", "xarchiver", "org.pwmt.zathura", "org.quickshell", "ckb-next" }
local BAR_H = 34
local WANT_BAR
do
    local alts = {}
    for _, n in ipairs(BAR_CLASSES) do
        local first = n:sub(1, 1)
        local head = first:match("%a") and ("[" .. first:upper() .. first .. "]") or first
        alts[#alts + 1] = head .. n:sub(2):gsub("%.", "\\.")
    end
    WANT_BAR = "^(" .. table.concat(alts, "|") .. ")$"
end

local candidates = {
    "/usr/lib/libhyprbars.so",
    "/usr/lib/hyprland-plugins/hyprbars.so",
    "/usr/lib/hyprland/plugins/hyprbars.so",
    "/usr/lib/hyprland-plugins/libhyprbars.so",
}

-- The AUR build 0.57.2-1.1 (upstream d2427d4) lacks upstream fix 2e03a09
-- (#717): Hyprland's blur pass leaves the stencil write mask at 0, so a bar
-- under/near a blurred surface (Quick Settings, OSD, …) flickers dark. Until
-- `yay -Syu` brings a newer package, load a local build of 2e03a09 made
-- against Hyprland 0.57.2. Once the package changes, this is skipped.
local HOME = os.getenv("HOME") or ""
local fixed = HOME .. "/.local/lib/hyprland-plugins/hyprbars-2e03a09.so"
local stale = io.open("/var/lib/pacman/local/hyprland-plugin-hyprbars-0.57.2-1.1/desc", "r")
if stale then
    stale:close()
    table.insert(candidates, 1, fixed)
end

local path
for _, p in ipairs(candidates) do
    local f = io.open(p, "r")
    if f then f:close(); path = p; break end
end
if not path then return end

local ok = pcall(hl.plugin.load, path)
if not ok or not hl.plugin.hyprbars then return end

hl.config({
    plugin = {
        hyprbars = {
            bar_height = BAR_H,
            -- same look as the desktop bar's clock: bar background, Comfortaa bold 14 px
            bar_color = rgb(c.bg0),
            ["col.text"] = rgb(c.fg1),
            bar_text_font = "Comfortaa",
            bar_text_size = 14,
            bar_text_weight = "bold",
            bar_text_align = "center",
            bar_buttons_alignment = "right",
            bar_padding = 12,
            bar_button_padding = 8,
            bar_part_of_window = true,
            bar_precedence_over_border = true,
            inactive_button_color = rgb(c.bg1),
            on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
        },
    },
})

-- buttons, right to left
hl.plugin.hyprbars.add_button({
    bg_color = rgb(c.bg2), fg_color = rgb(c.fg1), size = 18, icon = "✕",
    action = "hyprctl dispatch 'hl.dsp.window.close()'",
})
-- (no □ button: maximise is double-click on the bar, Super+Up, or the right-click menu)
hl.plugin.hyprbars.add_button({   -- minimise to the shell's shelf (Super+M restores), like Super+H
    bg_color = rgb(c.bg2), fg_color = rgb(c.fg1), size = 18, icon = "–",
    action = [[hyprctl dispatch 'function() package.loaded["gnome-like"].minimize() end']],
})

-- off everywhere, on for the apps listed above (last matching rule wins)
hl.window_rule({ name = "hyprbars-off", match = { class = ".*" }, ["hyprbars:no_bar"] = true })
hl.window_rule({ name = "hyprbars-on",  match = { class = WANT_BAR }, ["hyprbars:no_bar"] = false })

-- Right-click on a bar → the shell's title-bar menu (Minimize / Maximize or
-- Restore / Close; TitleMenu.qml), like the right-click menu of GTK's own
-- title bars. hyprbars has no right-click action; the shell-bridge plugin hands
-- every right press to titlebar_menu_at, which checks whether it was on a bar. The bar sits above the
-- window's own area (at.y - BAR_H … at.y). The topmost window under the
-- pointer wins: floating above tiled, then most recently focused.
local bar_set = {}
for _, n in ipairs(BAR_CLASSES) do bar_set[n] = true end
local function fs_mode(w) return tonumber(w.fullscreen) or 0 end
local function title_bar_at(x, y)
    local ws = hl.get_active_workspace()
    local best, best_rank
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.mapped and not w.hidden and w.at and w.size and w.workspace
            and ((ws and w.workspace.id == ws.id) or w.pinned) then
            local has_bar = bar_set[(w.class or ""):lower()] and fs_mode(w) < 2
            local top = has_bar and (w.at.y - BAR_H) or w.at.y
            if x >= w.at.x and x < w.at.x + w.size.x and y >= top and y < w.at.y + w.size.y then
                local rank = (w.floating and 0 or 100000) + (w.focus_history_id or 0)
                if not best_rank or rank < best_rank then best, best_rank = w, rank end
            end
        end
    end
    if best and bar_set[(best.class or ""):lower()] and fs_mode(best) < 2 and y < best.at.y then
        return best
    end
end
function _G.titlebar_menu_at(x, y)   -- global so it can be tested: hyprctl dispatch 'function() titlebar_menu_at(x, y) end'
    local w = title_bar_at(x, y)
    if not w then return end
    hl.exec_cmd(string.format("qs ipc call titlemenu open %s %d %d %d",
        w.address, math.floor(x), math.floor(y), fs_mode(w) == 1 and 1 or 0))
end
-- (called by the shell-bridge plugin on every right press: hyprbars swallows
--  clicks on its bars before key binds run, so a Lua bind never fires there)
