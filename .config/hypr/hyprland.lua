-- Hyprland 0.57 config for a desktop and a laptop: flat slate turquoise, GNOME-style floating + tiling.
-- Wiki: https://wiki.hypr.land/configuring/

local c     = require("colors")
local gnome = require("gnome-like")

local function rgb(hex, alpha) return "rgba(" .. hex .. (alpha or "ff") .. ")" end

-- Same files on an NVIDIA desktop and an Intel laptop: anything
-- hardware-specific is switched on by what is actually present.
local function exists(path) local f = io.open(path, "r"); if f then f:close() end; return f ~= nil end
local NVIDIA = exists("/proc/driver/nvidia/version")
-- Is a command on PATH? Pure Lua on purpose: os.execute() returns nil inside
-- Hyprland even on success (it ignores SIGCHLD, so the exit status is lost).
local function have(cmd)
    for dir in (os.getenv("PATH") or "/usr/bin"):gmatch("[^:]+") do
        if exists(dir .. "/" .. cmd) then return true end
    end
    return false
end

-------------------- MONITORS --------------------
-- NVIDIA desktop: only the monitor on the NVIDIA card is real. card0 is simpledrm (the boot
-- framebuffer left over with nvidia_drm.fbdev=0); GNOME shows it as a phantom
-- 31" "None-1" screen. Keep Hyprland on the NVIDIA card only.
if NVIDIA then hl.env("AQ_DRM_DEVICES", "/dev/dri/card1") end
require("monitors")   -- resolution, refresh, scale: ~/.config/hypr/monitors.lua (Settings → Displays)

-------------------- PROGRAMS --------------------
-- Terminal: whatever Settings → Default apps picked (xdg-terminal-exec reads
-- ~/.config/xdg-terminals.list); Ghostty until xdg-terminal-exec is installed.
local terminal    = have("xdg-terminal-exec") and "xdg-terminal-exec" or "ghostty"
local fileManager = "thunar"
-- over the overview, the shell closes it first (fuzzel quits when the overview takes the keyboard back); plain fuzzel if qs is down
local launcher    = "pkill -x fuzzel || qs ipc call overview launcher || fuzzel"

-------------------- ENVIRONMENT -----------------
-- NVIDIA (tested: GTX 1050 Ti, nvidia-580xx); Intel needs nothing extra
if NVIDIA then
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
end
-- Toolkits
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
-- Qt apps (ckb-next etc.): Hyprland accepts server-side decorations but draws
-- no title bars, so make Qt ignore that protocol and draw its own
-- GNOME-style (Adwaita) bar, following the GTK theme / dark preference.
hl.env("QT_WAYLAND_DISABLED_INTERFACES", "zxdg_decoration_manager_v1")
hl.env("QT_WAYLAND_DECORATION", "adwaita")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
-- Qt widget apps (ckb-next, …) use the KvTeerquaz Kvantum theme
-- (~/.config/Kvantum/build-kvteerquaz.py) so their controls match the shell.
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- Cursor (same as GNOME)
-- Cursor comes from dconf (set in the shell's Settings window), read once at startup.
local function gsetting(key, fallback)
    local h = io.popen("timeout 2 gsettings get org.gnome.desktop.interface " .. key .. " 2>/dev/null")
    if not h then return fallback end
    local v = (h:read("*l") or ""):gsub("^'", ""):gsub("'$", "")
    h:close()
    return v ~= "" and v or fallback
end
local cursorTheme = gsetting("cursor-theme", "phinger-cursors-light")
local cursorSize  = gsetting("cursor-size", "24")
hl.env("XCURSOR_THEME", cursorTheme)
hl.env("XCURSOR_SIZE", cursorSize)
hl.env("HYPRCURSOR_THEME", cursorTheme)
hl.env("HYPRCURSOR_SIZE", cursorSize)

-------------------- AUTOSTART -------------------
hl.on("hyprland.start", function()
    -- polkit password prompts come from the shell (PolkitPrompt.qml); hyprpolkitagent stays installed as a fallback:
    --   systemctl --user start hyprpolkitagent
    -- Quickshell: wallpaper + bar (~/.config/quickshell). Its Settings window lets
    -- Hyprland/hyprbars draw the title bar, like Thunar, instead of Qt's own.
    -- run-shell.sh starts it again if it dies and logs why to ~/.local/state/quickshell/qs.log
    hl.exec_cmd(os.getenv("HOME") .. "/.config/quickshell/scripts/run-shell.sh")
    -- ckb-next applies the keyboard lighting (the daemon alone leaves it dark);
    -- hidden: no window, its tray icon is Passive so the bar skips it
    if have("ckb-next") then
        hl.exec_cmd("env -u QT_WAYLAND_DISABLED_INTERFACES ckb-next --background")
    end
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_WAYLAND_DISABLED_INTERFACES QT_WAYLAND_DECORATION QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE")
end)

-------------------- LOOK AND FEEL ---------------
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border   = rgb(c.yellow_dim),
            inactive_border = rgb(c.bg1),
        },
        resize_on_border = true,        -- grab window edges like GNOME
        extend_border_grab_area = 12,
        layout = "dwindle",
        snap = {
            enabled = true,             -- floating windows snap to edges / each other
            window_gap = 12,
            monitor_gap = 12,
        },
    },

    decoration = {
        rounding       = 12,
        rounding_power = 2.4,           -- squircle-ish corners

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        dim_inactive = false,

        shadow = {
            enabled        = true,
            range          = 22,
            render_power   = 3,
            offset         = { 0, 4 },
            color          = 0x66000000,
            color_inactive = 0x33000000,
        },

        -- Blur is only used where something is translucent: the launcher,
        -- notifications and shell panels (see layer rules below).
        blur = {
            enabled   = true,
            size      = 6,
            passes    = 3,
            noise     = 0.02,
            contrast  = 1.0,
            brightness = 0.9,
            vibrancy  = 0.15,
            new_optimizations = true,
            xray      = false,
            popups    = false,
        },
    },

    animations = { enabled = true },
})
-- Settings → Windows writes ~/.config/hypr/windows.lua (gaps, snapping, dimming,
-- animations on/off); the values above are the fallback.
pcall(require, "windows")

-------------------- ANIMATIONS ------------------
-- Springs for things that move, short beziers for fades. Tuned to feel like
-- GNOME's, a little snappier.
hl.curve("emphasized", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1} } })
hl.curve("standard",   { type = "bezier", points = { {0.2, 0},    {0, 1}   } })
hl.curve("linear",     { type = "bezier", points = { {0, 0},      {1, 1}   } })
hl.curve("soft",   { type = "spring", mass = 1, stiffness = 260, damping = 26 })
hl.curve("bouncy", { type = "spring", mass = 1, stiffness = 300, damping = 22 })

hl.animation({ leaf = "global",        enabled = true, speed = 8,   bezier = "standard" })
hl.animation({ leaf = "windows",       enabled = true, speed = 5,   spring = "soft" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4,   spring = "bouncy", style = "popin 90%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2,   bezier = "standard", style = "popin 90%" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 5,   spring = "soft" })
hl.animation({ leaf = "border",        enabled = true, speed = 4,   bezier = "standard" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3,   bezier = "standard" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 2,   bezier = "linear" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3,   bezier = "emphasized", style = "slide" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 2,   bezier = "standard",   style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 2,   bezier = "standard" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.5, bezier = "linear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 4,   spring = "soft", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "emphasized", style = "slidevert" })

-------------------- LAYOUTS ---------------------
hl.config({
    dwindle = { preserve_split = true, smart_split = false },
})

-------------------- MISC ------------------------
hl.config({
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        focus_on_activate        = true,
        vrr = 0,
        middle_click_paste = true,
        allow_session_lock_restore = true,  -- if the lock screen crashes, restarting qs re-locks
    },
    cursor = {
        -- NVIDIA: software cursor — on the GTX 1050 Ti the hardware cursor plane is
        -- not restored after DPMS (screen-off idle), pointer invisible until a VT switch
        no_hardware_cursors = NVIDIA and 1 or 2,
        use_cpu_buffer = 2,
    },
})

-------------------- LAYER RULES (blur) ----------
-- (no blur rule for fuzzel: a blurred layer makes hyprbars title bars render dark; it is solid like menus instead)
-- shell panels ask for blur themselves (Quickshell BackgroundEffect), so no layer blur here
hl.layer_rule({ match = { namespace = "^shell-wallpaper$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^shell-panel-power$" }, animation = "fade" })
-- QS, calendar + music drop-down animate their own card out from under the bar; a layer slide
-- would move the whole full-screen surface in from the top of the screen
hl.layer_rule({ match = { namespace = "^shell-panel-(qs|date|music)$" }, no_anim = true })
-- title-bar menu: plays its own popup-like fade (TitleMenu.qml), like apps' popup menus
hl.layer_rule({ match = { namespace = "^shell-titlemenu$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^shell-desktopmenu$" }, no_anim = true })
-- bar menus (xdg popups of the bar) ignore Quickshell's blur request, so Hyprland
-- blurs them; ignore_alpha keeps the clear area around each card unblurred
hl.layer_rule({ match = { namespace = "^shell-bar$" }, blur_popups = true, ignore_alpha = 0.3 })

-------------------- INPUT -----------------------
hl.config({
    input = {
        kb_layout  = "us,gr",
        kb_options = "grp:alt_shift_toggle,terminate:ctrl_alt_bksp",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = { natural_scroll = false },
    },
})
-- Settings → Keyboard & mouse writes ~/.config/hypr/input.lua; the values above are the fallback.
pcall(require, "input")

-------------------- KEYBINDINGS ----------------
local mod = "SUPER"
local function bind(keys, action, flags) hl.bind(keys, action, flags) end

-- Apps
bind("Super_L", hl.dsp.exec_cmd("qs ipc call overview superTap"), { release = true, description = "Shell: Overview (tap Super)" })  -- tap Super: overview (like GNOME)
bind(mod .. " + A",      hl.dsp.exec_cmd("qs ipc call overview apps"), { description = "Shell: App grid" })   -- app grid
bind(mod .. " + R",      hl.dsp.exec_cmd(launcher), { description = "Shell: Run launcher (fuzzel)" })                      -- fuzzel, as a fallback
bind(mod .. " + Return", hl.dsp.exec_cmd(terminal), { description = "Apps: Terminal" })
bind(mod .. " + E",      hl.dsp.exec_cmd(fileManager), { description = "Apps: Files" })

-- Windows
bind(mod .. " + Q", hl.dsp.window.close(), { description = "Windows: Close" })
bind("ALT + F4",    hl.dsp.window.close(), { description = "Windows: Close" })
bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Windows: Fullscreen" })
bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Windows: Float / tile this window" })      -- float / tile this window
bind(mod .. " + T", gnome.toggle_workspace_tiling, { description = "Windows: Float / tile the whole workspace" })                    -- float / tile whole workspace
bind(mod .. " + P", hl.dsp.window.pin(), { description = "Windows: Keep on all workspaces" })                              -- keep on all workspaces
bind(mod .. " + H", function() gnome.minimize() end, { description = "Windows: Minimise" })                  -- minimise (like GNOME)
bind(mod .. " + M", gnome.restore_last, { description = "Windows: Bring back the last minimised" })                               -- bring back last minimised
bind(mod .. " + SHIFT + M", hl.dsp.workspace.toggle_special("minimized"), { description = "Windows: Show all minimised" })  -- show all minimised
bind(mod .. " + J", hl.dsp.layout("togglesplit"), { description = "Windows: Change split direction (tiled)" })
bind(mod .. " + G", hl.dsp.group.toggle(), { description = "Windows: Tabbed group" })                            -- tabbed group

bind(mod .. " + left",  function() gnome.snap("left") end, { description = "Windows: Snap left" })
bind(mod .. " + right", function() gnome.snap("right") end, { description = "Windows: Snap right" })
bind(mod .. " + up",    function() gnome.snap("up") end, { description = "Windows: Maximise (tiled: move up)" })
bind(mod .. " + down",  function() gnome.snap("down") end, { description = "Windows: Restore (tiled: move down)" })

-- Focus
-- Alt+Tab: the shell's switcher (live previews, all workspaces, MRU order).
-- Hyprland watches Alt and tells the switcher to commit when it's released.
-- (The timer is created on first use: creating one at load time crashes
--  `Hyprland --verify-config` in 0.57.)
local altWatch
local function switcher(dir)
    hl.exec_cmd("qs ipc call switcher " .. dir)
    if not altWatch then
        altWatch = hl.timer(function()
            -- physical keycodes (64 = left Alt, 108 = right Alt): keysyms can
            -- change with the us/gr layout and Alt+Shift switching
            if not hl.is_key_down(64) and not hl.is_key_down(108) then
                altWatch:set_enabled(false)
                hl.exec_cmd("qs ipc call switcher commit")
            end
        end, { timeout = 40, type = "repeat" })
    elseif not altWatch:is_enabled() then
        altWatch:set_enabled(true)
    end
end
bind("ALT + Tab", function() switcher("next") end, { description = "Windows: Switch windows" })
bind("ALT + grave", function() switcher("prev") end, { description = "Windows: Switch windows backwards" })
bind(mod .. " + ALT + left",  hl.dsp.focus({ direction = "left" }), { description = "Windows: Focus the window on the left" })
bind(mod .. " + ALT + right", hl.dsp.focus({ direction = "right" }), { description = "Windows: Focus the window on the right" })
bind(mod .. " + ALT + up",    hl.dsp.focus({ direction = "up" }), { description = "Windows: Focus the window above" })
bind(mod .. " + ALT + down",  hl.dsp.focus({ direction = "down" }), { description = "Windows: Focus the window below" })

-- Workspaces
for i = 1, 10 do
    local key = i % 10
    bind(mod .. " + " .. key,          hl.dsp.focus({ workspace = i }), { description = "Workspaces: Go to workspace " .. i })
    bind(mod .. " + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }), { description = "Workspaces: Move window to workspace " .. i })
end
bind(mod .. " + Page_Down",  hl.dsp.focus({ workspace = "e+1" }), { description = "Workspaces: Next workspace" })
bind(mod .. " + Page_Up",    hl.dsp.focus({ workspace = "e-1" }), { description = "Workspaces: Previous workspace" })
bind("CTRL + ALT + right",   hl.dsp.focus({ workspace = "r+1" }), { description = "Workspaces: Next workspace" })
bind("CTRL + ALT + left",    hl.dsp.focus({ workspace = "r-1" }), { description = "Workspaces: Previous workspace" })
bind(mod .. " + SHIFT + Page_Down", hl.dsp.window.move({ workspace = "r+1" }), { description = "Workspaces: Move window to the next workspace" })
bind(mod .. " + SHIFT + Page_Up",   hl.dsp.window.move({ workspace = "r-1" }), { description = "Workspaces: Move window to the previous workspace" })
bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Workspaces: Next workspace (scroll)" })
bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Workspaces: Previous workspace (scroll)" })

-- Scratchpad
bind(mod .. " + grave",         hl.dsp.workspace.toggle_special("scratch"), { description = "Workspaces: Show / hide the scratchpad" })
bind(mod .. " + SHIFT + grave", hl.dsp.window.move({ workspace = "special:scratch" }), { description = "Workspaces: Move window to the scratchpad" })

-- Mouse: Super+drag moves, Super+right-drag resizes
bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Windows: Move (drag)" })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Windows: Resize (drag)" })

-- Screenshots (saved to ~/Pictures/Screenshots and copied)
local shot = os.getenv("HOME") .. "/.config/quickshell/scripts/screenshot.sh "   -- notification with Edit / Open / Folder
bind("Print",         hl.dsp.exec_cmd(shot .. "area"),   { description = "Screenshots: Area (saved + copied)" })
bind("SHIFT + Print", hl.dsp.exec_cmd(shot .. "screen"), { description = "Screenshots: Whole screen (saved + copied)" })
bind("ALT + Print",   hl.dsp.exec_cmd(shot .. "window"), { description = "Screenshots: Active window (saved + copied)" })
-- (no Alt+Shift combos: with grp:alt_shift_toggle, Alt+Shift switches the layout and drops a modifier)
bind("CTRL + Print",         hl.dsp.exec_cmd("qs ipc call recorder toggle"), { description = "Screenshots: Record the screen (again to stop)" })
bind("CTRL + SHIFT + Print", hl.dsp.exec_cmd("qs ipc call recorder area"),   { description = "Screenshots: Record an area (again to stop)" })

-- Media keys
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Media: Volume up" })
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true, description = "Media: Volume down" })
bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, description = "Media: Mute" })
bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, description = "Media: Mute the microphone" })
bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Media: Next track" })
bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Media: Previous track" })
bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Media: Play / pause" })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Media: Play / pause" })
-- screen brightness (laptops; the shell shows the OSD and keeps it above 0)
bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs ipc call brightness up"),   { locked = true, repeating = true, description = "Media: Brightness up" })
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs ipc call brightness down"), { locked = true, repeating = true, description = "Media: Brightness down" })

-- touchpad gestures (laptops): three fingers sideways switch workspaces, up opens the overview
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd("qs ipc call overview toggle") end })

-- Session
bind(mod .. " + SHIFT + R", hl.dsp.reload_config(), { description = "Session: Reload Hyprland config" })
bind(mod .. " + L",      hl.dsp.exec_cmd("qs ipc call lock lock"), { description = "Session: Lock the screen" })      -- lock, like GNOME
bind(mod .. " + Escape", hl.dsp.exec_cmd("qs ipc call power toggle"), { description = "Session: Power menu" })   -- power menu
bind(mod .. " + S",      hl.dsp.exec_cmd("qs ipc call quicksettings toggle"), { description = "Shell: Quick settings" })  -- quick settings, like GNOME
bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"), { description = "Shell: Clipboard history" })
bind(mod .. " + F1",     hl.dsp.exec_cmd("qs ipc call shortcuts toggle"), { description = "Shell: Keyboard shortcuts" })   -- cheat sheet popup
bind(mod .. " + slash",  hl.dsp.exec_cmd("qs ipc call shortcuts toggle"), { description = "Shell: Keyboard shortcuts" })
bind("XF86PowerOff",     hl.dsp.exec_cmd("qs ipc call power button"), { description = "Session: Power button" })   -- Settings → Power & idle decides
bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/quickshell/scripts/logout.sh"), { description = "Session: Quit Hyprland (log out at once)" })
-- Restart the shell (bar + wallpaper). run-shell.sh already restarts it when it
-- dies; this is for when it hangs or gives up. Why it died: ~/.local/state/quickshell/qs.log
bind(mod .. " + SHIFT + Escape", hl.dsp.exec_cmd(
    os.getenv("HOME") .. "/.config/quickshell/scripts/run-shell.sh --restart"),
    { description = "Session: Restart the shell (bar + wallpaper)" })

-------------------- WINDOW RULES ----------------
-- No blur behind windows: they're all opaque, and any Hyprland blur pass
-- (e.g. behind a Qt app's semi-transparent title-bar shadow) makes hyprbars
-- title bars render dark for a moment. The shell's panels blur through
-- Quickshell's BackgroundEffect instead, which isn't affected.
hl.window_rule({ name = "no-window-blur", match = { class = ".*" }, no_blur = true })
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})
hl.window_rule({ name = "video-idle", match = { content = "video" }, idle_inhibit = "fullscreen" })
-- PiP also stays floating on tiled workspaces (utility tag) and doesn't take
-- focus; gnome-like.lua sizes it and puts it in the bottom-right corner.
hl.window_rule({
    name  = "pip",
    match = { title = "^Picture.in.[Pp]icture$" },
    pin = true, keep_aspect_ratio = true, no_initial_focus = true,
    tag = "+utility",
})
-- The terminal opens floating and centred even on tiled workspaces (utility
-- tag), at a size that fits fastfetch's logo + details. SUPER+V tiles it.
hl.window_rule({
    name   = "terminal-floating",
    match  = { class = [[^com\.mitchellh\.ghostty$]] },
    size   = { "monitor_w*0.45", "monitor_h*0.5" },
    center = true,
    tag    = "+utility",
})

-------------------- TITLE BARS -----------------
require("titlebars")   -- hyprbars for apps that need the compositor to draw one
require("shell-bridge")   -- local plugin: apps' minimize requests + title-bar right-click → shell
