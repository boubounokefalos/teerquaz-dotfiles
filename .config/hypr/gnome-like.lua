-- GNOME-style window handling on top of Hyprland:
--  * new windows open floating and centred (like GNOME)
--  * SUPER+T switches the current workspace between floating and tiled
--  * SUPER+Left/Right snap a floating window to a screen half,
--    SUPER+Up/Down maximise / restore; on a tiled workspace they move the window

local M = {}

local GAP = 10          -- gap kept around snapped windows
local tiled_ws = {}     -- workspace id -> true when the workspace is in tile mode

-- Tile mode is remembered per workspace number across reloads and logins.
-- Quickshell reads the same file to show the state in quick settings.
local STATE_DIR  = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/hypr"
local STATE_FILE = STATE_DIR .. "/tiled-workspaces.json"

local function load_state()
    local f = io.open(STATE_FILE, "r")
    if not f then return end
    local txt = f:read("*a") or ""
    f:close()
    for id in txt:gmatch("-?%d+") do tiled_ws[tonumber(id)] = true end
end

local function save_state()
    local ids = {}
    for id, on in pairs(tiled_ws) do if on then ids[#ids + 1] = id end end
    table.sort(ids)
    os.execute("mkdir -p '" .. STATE_DIR .. "'")
    local f = io.open(STATE_FILE .. ".tmp", "w")
    if not f then return end
    f:write('{ "tiled": [' .. table.concat(ids, ", ") .. '] }\n')
    f:close()
    os.rename(STATE_FILE .. ".tmp", STATE_FILE)
end

load_state()

hl.window_rule({
    name  = "float-by-default",
    match = { class = ".*" },
    float  = true,
    center = true,
})

-- Dialogs keep floating even on tiled workspaces.
hl.window_rule({ name = "tag-modal", match = { modal = true }, tag = "+dialog" })
-- Non-modal dialogs can't be told apart from the Lua API (no parent/transient
-- field), so they're listed by title: they open floating at their own size.
hl.window_rule({
    name  = "tag-thunar-dialogs",
    match = { class = "^[Tt]hunar$",
              title = [[^(Rename ".*"|.* - Properties|Create New (File|Folder)|New Empty File|New Folder|Create Document from template ".*"|File Operation Progress|Confirm to replace files|Open With|File Manager Preferences|Attention|Bulk Rename.*)$]] },
    tag   = "+dialog",
})
hl.window_rule({
    name  = "tag-xarchiver-dialogs",
    match = { class = "^[Xx]archiver$",
              title = [[^(Create a new archive|Extract files|Add files|Archive Properties|Preferences|Comment|Open With|Rename|Multi-Extract|Confirm deletion of files|Overwrite.*|Enter.*[Pp]assword.*|Test result.*)$]] },
    tag   = "+dialog",
})

-- Utility windows (file choosers, password prompts, small GNOME apps, and
-- Picture-in-Picture, tagged in hyprland.lua) also stay floating on tiled
-- workspaces. SUPER+V still tiles one by hand.
-- Class names checked with `hyprctl clients` on the author's machines (2026-11-25); apps that
-- aren't installed (Calendar, Clocks, Weather, Settings, File Roller,
-- xdg-desktop-portal-gnome) are left out.
hl.window_rule({
    name  = "tag-utility",
    match = { class = [[^(xdg-desktop-portal-gtk|gcr-prompter|hyprpolkitagent|org\.gnome\.(Calculator|Loupe|SystemMonitor|Characters)|[Xx]archiver)$]] },
    tag   = "+utility",
})
-- the portal file chooser opens at about 60 % x 70 % of the monitor, centred
hl.window_rule({
    name   = "file-chooser-size",
    match  = { class = "^xdg-desktop-portal-gtk$" },
    size   = { "monitor_w*0.6", "monitor_h*0.7" },
    center = true,
})

local function has_tag(w, tag)
    local t = w.tags
    if type(t) == "string" then return t:find(tag, 1, true) ~= nil end
    if type(t) == "table" then
        for _, v in pairs(t) do
            if type(v) == "string" and v:find(tag, 1, true) then return true end
        end
    end
    return false
end

-- Windows that keep floating when their workspace is tiled.
local function keeps_floating(w)
    return has_tag(w, "dialog") or has_tag(w, "utility")
end

local function is_fs(w)
    local f = w.fullscreen
    return f == true or (type(f) == "number" and f ~= 0)
end

-- Show a message in the shell's on-screen display (same pill as volume).
local function notify(icon, text)
    local q = "'" .. text:gsub("'", "'\\''") .. "'"
    hl.exec_cmd("qs ipc call osd message " .. icon .. " " .. q)
end

-- Set a workspace's mode (also for workspaces that don't exist yet).
-- Used by SUPER+T and by Settings → Windows:
--   hyprctl eval 'package.loaded["gnome-like"].set_workspace_tiling(3, true)'
function M.set_workspace_tiling(id, on, quiet)
    id = tonumber(id)
    if not id then return end
    tiled_ws[id] = on and true or nil
    save_state()
    local ws = hl.get_workspace(id)
    if ws then
        for _, w in ipairs(hl.get_workspace_windows(ws) or {}) do
            if not keeps_floating(w) then
                hl.dispatch(hl.dsp.window.float({ window = w, action = on and "disable" or "enable" }))
                if not on then
                    -- restored floating geometry can land off-screen; recentre
                    hl.dispatch(hl.dsp.window.center({ window = w }))
                end
            end
        end
    end
    if not quiet then
        notify(on and "dashboard" or "filter_none", "Workspace " .. (ws and ws.name or id) .. (on and " · tiling" or " · floating"))
    end
end

function M.toggle_workspace_tiling()
    local ws = hl.get_active_workspace()
    if not ws then return end
    M.set_workspace_tiling(ws.id, not tiled_ws[ws.id])
end

function M.is_tiled(ws_id) return tiled_ws[ws_id] == true end

-- Apps launched from the shell open on the workspace they were launched on,
-- even if the user switched away before the (slow) app mapped its window.
-- The shell calls expect_launch({names}, ws); the first new window whose
-- class matches one of the names (either is a prefix of the other, so
-- "google-chrome" matches the exec name "google-chrome-stable") within 60 s
-- is moved there without following it. Matched in launch order.
local pending = {}
function M.expect_launch(names, ws)
    local n = {}
    for _, s in ipairs(names or {}) do if s ~= "" then n[#n + 1] = s:lower() end end
    if #n > 0 and ws then pending[#pending + 1] = { names = n, ws = ws, t = os.time() } end
end
local function name_match(class, names)
    for _, s in ipairs(names) do
        if class:sub(1, #s) == s or s:sub(1, #class) == class then return true end
        if class:sub(-#s - 1) == "." .. s then return true end   -- org.pwmt.zathura ↔ zathura
    end
    return false
end
hl.on("window.open", function(w)
    if not w or #pending == 0 then return end
    local class = ((w.initial_class ~= "" and w.initial_class) or w.class or ""):lower()
    local now = os.time()
    for i = #pending, 1, -1 do if now - pending[i].t > 60 then table.remove(pending, i) end end
    if class == "" then return end
    for i, p in ipairs(pending) do
        if name_match(class, p.names) then
            table.remove(pending, i)
            if w.workspace and w.workspace.id ~= p.ws then
                hl.dispatch(hl.dsp.window.move({ window = w, workspace = p.ws, follow = false }))
            end
            return
        end
    end
end)

hl.on("window.open", function(w)
    if w and w.workspace and tiled_ws[w.workspace.id] and w.floating and not keeps_floating(w) then
        hl.dispatch(hl.dsp.window.float({ window = w, action = "disable" }))
    end
end)

-- Keep floating windows inside the usable area (below the bar). Windows that
-- don't fit get maximised, like GNOME does for oversized windows.
function M.clamp(win)
    if not win or not win.mapped or not win.at or not win.size then return end
    if not win.floating or is_fs(win) then return end
    local m = win.monitor or hl.get_active_monitor()
    if not m then return end
    local s = (m.scale and m.scale > 0) and m.scale or 1
    local r = m.reserved or { top = 0, right = 0, bottom = 0, left = 0 }
    local ax, ay = m.x + r.left, m.y + r.top
    local aw, ah = m.width / s - r.left - r.right, m.height / s - r.top - r.bottom
    local x, y, w, h = win.at.x, win.at.y, win.size.x, win.size.y

    if w >= aw - 2 * GAP or h >= ah - 2 * GAP then
        hl.dispatch(hl.dsp.window.fullscreen({ window = win, mode = "maximized", action = "set" }))
        return
    end
    local nx = math.min(math.max(x, ax + GAP), ax + aw - w - GAP)
    local ny = math.min(math.max(y, ay + GAP), ay + ah - h - GAP)
    if nx ~= x or ny ~= y then
        hl.dispatch(hl.dsp.window.move({ window = win, x = math.floor(nx), y = math.floor(ny) }))
    end
end

function M.clamp_all()
    for _, w in ipairs(hl.get_windows() or {}) do M.clamp(w) end
end

hl.on("window.open", function(w)
    -- after the app has set its initial geometry
    hl.timer(function() M.clamp(w) end, { timeout = 150, type = "oneshot" })
end)
hl.on("monitor.layout_changed", function()
    hl.timer(M.clamp_all, { timeout = 300, type = "oneshot" })
end)

-- Minimise (Hyprland has none): minimised windows go to a hidden special
-- workspace; restore_last() brings the most recent one back.
local minimized = {}   -- stack of stable ids, most recent last

local function forget(id)
    for i = #minimized, 1, -1 do
        if minimized[i] == id then table.remove(minimized, i) end
    end
end

function M.minimize(win)
    win = win or hl.get_active_window()
    if not win or not win.stable_id then return end
    forget(win.stable_id)
    table.insert(minimized, win.stable_id)
    hl.dispatch(hl.dsp.window.move({ window = win, workspace = "special:minimized", follow = false }))
end

-- Restoring focuses the window, and Hyprland warps the pointer to the centre
-- of a newly focused window. A click on the bar pill must not move the
-- pointer, so warping is off for the duration (same as the overview/switcher).
local function without_warps(fn)
    hl.config({ cursor = { no_warps = true } })
    local ok, err = pcall(fn)
    hl.config({ cursor = { no_warps = false } })
    if not ok then error(err) end
end
local restore_last_impl
function M.restore_last() without_warps(restore_last_impl) end
restore_last_impl = function()
    local ws = hl.get_active_workspace()
    while #minimized > 0 do
        local id = table.remove(minimized)
        local w = hl.get_window("stableid:" .. tostring(id))
        if w and w.workspace and w.workspace.name == "special:minimized" then
            if ws and ws.special then
                hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
                ws = hl.get_active_workspace()
            end
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = ws and ws.id or "e+0", follow = true }))
            hl.dispatch(hl.dsp.focus({ window = w }))
            hl.dispatch(hl.dsp.window.alter_zorder({ window = w, mode = "top" }))
            return
        end
    end
    -- nothing tracked (e.g. after a config reload): take any window on the shelf
    local list = hl.get_workspace_windows("special:minimized") or {}
    if #list > 0 then
        local w = list[#list]
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = ws and ws.id or "e+0", follow = true }))
        hl.dispatch(hl.dsp.focus({ window = w }))
    end
end

hl.on("window.minimize", function(w, wants)
    if wants then M.minimize(w) end
end)
hl.on("window.close", function(w)
    if w and w.stable_id then forget(w.stable_id) end
end)

-- A window moved to another workspace takes on that workspace's mode.
hl.on("window.move_to_workspace", function(w, ws)
    if not w or not ws or not ws.id or ws.id < 0 or keeps_floating(w) then return end
    local want_tiled = tiled_ws[ws.id] == true
    if want_tiled and w.floating then
        hl.dispatch(hl.dsp.window.float({ window = w, action = "disable" }))
    elseif not want_tiled and not w.floating then
        hl.dispatch(hl.dsp.window.float({ window = w, action = "enable" }))
        hl.dispatch(hl.dsp.window.center({ window = w }))
    end
end)

-- Usable area of a monitor (logical px), minus bars and the snap gap.
local function work_area(m)
    local s = (m.scale and m.scale > 0) and m.scale or 1
    local r = m.reserved or { top = 0, right = 0, bottom = 0, left = 0 }
    local x = m.x + r.left + GAP
    local y = m.y + r.top + GAP
    local w = m.width / s - r.left - r.right - 2 * GAP
    local h = m.height / s - r.top - r.bottom - 2 * GAP
    return x, y, w, h
end

local function place(win, x, y, w, h)
    hl.dispatch(hl.dsp.window.resize({ window = win, x = math.floor(w), y = math.floor(h) }))
    hl.dispatch(hl.dsp.window.move({ window = win, x = math.floor(x), y = math.floor(y) }))
end

-- Picture-in-Picture: a quarter of the work area wide (height keeps the
-- video's aspect ratio), in the bottom-right corner above any bottom bar.
-- Placed here rather than with rule size/move because those are relative to
-- the whole monitor and don't know about the bar.
local function is_pip(w)
    return type(w.title) == "string" and w.title:match("^Picture.in.[Pp]icture$") ~= nil
end
hl.on("window.open", function(w)
    if not w or not is_pip(w) then return end
    -- after clamp() (150 ms) and the app's own initial size
    hl.timer(function()
        if not w.mapped or not w.floating or not w.size or w.size.x <= 0 then return end
        local m = w.monitor or hl.get_active_monitor()
        if not m then return end
        local x, y, aw, ah = work_area(m)
        local pw = aw * 0.25
        local ph = pw * w.size.y / w.size.x
        place(w, x + aw - pw, y + ah - ph, pw, ph)
    end, { timeout = 250, type = "oneshot" })
end)

function M.snap(dir)
    local win = hl.get_active_window()
    if not win then return end

    if not win.floating then
        if dir == "up" then
            hl.dispatch(hl.dsp.window.fullscreen({ window = win, mode = "maximized" }))
        else
            hl.dispatch(hl.dsp.window.move({ window = win, direction = dir }))
        end
        return
    end

    if dir == "up" then
        hl.dispatch(hl.dsp.window.fullscreen({ window = win, mode = "maximized" }))
        return
    end
    if dir == "down" then
        if is_fs(win) then
            hl.dispatch(hl.dsp.window.fullscreen({ window = win, mode = "maximized", action = "unset" }))
        else
            hl.dispatch(hl.dsp.window.center({ window = win }))
        end
        return
    end

    if is_fs(win) then
        hl.dispatch(hl.dsp.window.fullscreen({ window = win, mode = "maximized", action = "unset" }))
    end
    local m = win.monitor or hl.get_active_monitor()
    if not m then return end
    local x, y, w, h = work_area(m)
    local half = (w - GAP) / 2
    if dir == "left" then
        place(win, x, y, half, h)
    else
        place(win, x + half + GAP, y, half, h)
    end
end

return M
