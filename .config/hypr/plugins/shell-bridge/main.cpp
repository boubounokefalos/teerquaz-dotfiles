// shell-bridge: small things Hyprland 0.57's Lua config can't reach.
//  1. Apps' own minimize requests (xdg_toplevel.set_minimized / X11 iconify:
//     the "_" button, Chrome's title-bar menu) are ignored by Hyprland. They
//     are forwarded to the window.minimize event, which gnome-like.lua turns
//     into the shell's minimize (special:minimized shelf, Super+M restores).
//  2. Right-clicks on hyprbars title bars: hyprbars swallows clicks on its bars
//     before key binds run, so a Lua bind never sees them. A right click on a
//     bar is kept from hyprbars (it would arm a window drag) and, on release,
//     handed to titlebar_menu_at(x, y) in titlebars.lua, which opens the
//     shell's title-bar menu.
//  3. Apps' own title bars (GTK, libadwaita) ask the compositor for the window
//     menu on a right click (xdg_toplevel.show_window_menu); Hyprland ignores
//     it, so nothing appeared. It now opens the same shell title-bar menu
//     (titlebar_menu_for in ~/.config/hypr/shell-bridge.lua).
//  4. Toplevels are told minimize + window menu are supported
//     (wm_capabilities), so GTK4 apps enable their "_" button.
#define WLR_USE_UNSTABLE
// std headers first: the private→public trick below must not touch them
#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <optional>
#include <format>
#include <fstream>
#include <unordered_map>
#include <hyprland/src/plugins/PluginAPI.hpp>
// XDGShell keeps the xdg_toplevel wrapper private; the plugin needs it to
// answer show_window_menu (same object layout, rebuilt for every Hyprland)
#define private public
#include <hyprland/src/protocols/XDGShell.hpp>
#undef private
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <fstream>
#include <cstdlib>
#include <linux/input-event-codes.h>
#include <format>
#include <unordered_map>

using Desktop::View::CWindow;

static HANDLE                                            g_handle = nullptr;
static CHyprSignalListener                               g_onCreate, g_onDestroy, g_onButton, g_onOpen;
struct SWatched {
    PHLWINDOWREF        window;
    CHyprSignalListener listener;
};
static std::unordered_map<CWindow*, SWatched> g_listeners;

// answer xdg_toplevel.show_window_menu for w with the shell's title-bar menu
static void hookWindowMenu(PHLWINDOW w) {
    if (!PROTO::xdgShell)
        return;
    for (auto& tl : PROTO::xdgShell->m_toplevels) {
        if (!tl || tl->m_window.lock() != w || !tl->m_resource)
            continue;
        PHLWINDOWREF ref = w;
        // Hyprland doesn't list minimize / window_menu in the toplevel's
        // wm_capabilities, so GTK4/libadwaita apps grey out their "_" button.
        // This plugin provides both, so announce them (xdg_toplevel v5+).
        if (tl->m_resource->version() >= 5) {
            wl_array caps;
            wl_array_init(&caps);
            for (uint32_t c : {XDG_TOPLEVEL_WM_CAPABILITIES_WINDOW_MENU, XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE, XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN,
                               XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE})
                *(uint32_t*)wl_array_add(&caps, sizeof(uint32_t)) = c;
            tl->m_resource->sendWmCapabilities(&caps);
            wl_array_release(&caps);
            // takes effect with the next configure; none may be sent before
            // the client's first commit (that first configure will carry it)
            if (auto owner = tl->m_owner.lock(); owner && !owner->m_initialCommit)
                owner->scheduleConfigure();
        }
        tl->m_resource->setShowWindowMenu([ref](CXdgToplevel*, wl_resource*, uint32_t, int32_t, int32_t) {
            const auto win = ref.lock();
            if (!win)
                return;
            // the request comes from a right click: open at the pointer
            const auto p = g_pInputManager->getMouseCoordsInternal();
            HyprlandAPI::invokeHyprctlCommand("dispatch",
                std::format("function() if titlebar_menu_for then titlebar_menu_for(\"0x{:x}\", {}, {}) end end", (uintptr_t)win.get(), (int)p.x, (int)p.y));
        });
        return;
    }
}

static void watch(PHLWINDOW w) {
    if (!w)
        return;
    // already hooked — unless that entry belongs to a dead window at the same address
    if (auto it = g_listeners.find(w.get()); it != g_listeners.end() && it->second.window.lock() == w)
        return;
    hookWindowMenu(w);
    PHLWINDOWREF ref = w;
    g_listeners[w.get()].window   = ref;
    g_listeners[w.get()].listener = w->backend().m_events.stateRequest.listen([ref](const Desktop::View::SBackendStateRequest& req) {
        if (!req.minimized.value_or(false))
            return;
        if (auto win = ref.lock())
            Event::bus()->m_events.window.minimize.emit(win, true);
    });
}


// --- title-bar right-click -------------------------------------------------
static constexpr double         BAR_H = 34;   // = BAR_H in ~/.config/hypr/titlebars.lua
static std::optional<Vector2D>  g_pressAt;
static bool                     g_synthetic = false;   // our own release, below


// Is p on a hyprbars title bar? The window under p counting its decorations,
// with p in the band just above its content (where hyprbars puts the bar;
// the thin border band right above content is left alone).
static bool onTitleBar(const Vector2D& p) {
    Desktop::CViewHitTester ht{*Desktop::viewState()};
    const auto w = ht.windowAt(p, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);
    if (!w)
        return false;
    const auto   box   = w->getWindowMainSurfaceBox();
    const double above = box.y - p.y;
    return p.x >= box.x && p.x < box.x + box.w && above > 3 && above <= BAR_H + 3;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_handle = handle;
    // Only mapped windows: the list also holds windows still playing their
    // close animation, whose backend is already gone — touching one crashed
    // Hyprland (2026-11-21, plugin reloaded right after a window closed).
    // New windows are hooked on create, while their backend surely exists.
    for (auto& w : Desktop::windowState()->windows())
        if (Desktop::View::validMapped(w))
            watch(w);
    g_onCreate  = Event::bus()->m_events.window.create.listen([](PHLWINDOW w) { watch(w); });
    // the xdg toplevel may only be linked to its window by the time it maps
    g_onOpen = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { hookWindowMenu(w); });
    g_onDestroy = Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF w) {
        // drop the hooks of windows that are gone (each remembers its own
        // window; the old check wiped every hook whenever w was already expired)
        std::erase_if(g_listeners, [&](auto& kv) { return kv.second.window.expired() || (!w.expired() && kv.first == w.get()); });
    });
    g_onButton = Event::bus()->m_events.input.mouse.button.listen([](const IPointer::SButtonEvent& e, Event::SCallbackInfo& info) {
        if (e.button != BTN_RIGHT || g_synthetic)
            return;
        const auto p = g_pInputManager->getMouseCoordsInternal();
        if (e.state == WL_POINTER_BUTTON_STATE_PRESSED) {
            if (!onTitleBar(p))
                return;
            // hyprbars arms a window drag on ANY press on its bar and only
            // disarms it on a release it accepts (none arrives once the menu
            // covers the bar). So it never gets a right press: the press is
            // turned into a release (hyprbars just tidies up), and Hyprland
            // core drops it (cancelled), so the app doesn't see it either.
            // Works for bars created after this plugin loaded (all of them
            // after login): listeners run in registration order.
            g_pressAt                                         = p;
            const_cast<IPointer::SButtonEvent&>(e).state = WL_POINTER_BUTTON_STATE_RELEASED;
            info.cancelled                                    = true;
            // Safety net for bars whose hyprbars listener runs before ours
            // (windows that were open when this plugin was (re)loaded): they
            // have already armed a drag, so hand every listener a release
            // right away — before the next pointer move can start the drag.
            IPointer::SButtonEvent rel = e;
            rel.state                  = WL_POINTER_BUTTON_STATE_RELEASED;
            g_pEventLoopManager->doLater([rel]() {
                Event::SCallbackInfo ignored;
                g_synthetic = true;
                Event::bus()->m_events.input.mouse.button.emit(rel, ignored);
                g_synthetic = false;
            });
            return;
        }
        if (!g_pressAt)
            return;
        info.cancelled   = true;   // its press never reached the app
        const bool moved = g_pressAt->distance(p) > 6;
        g_pressAt.reset();
        if (!moved)
            HyprlandAPI::invokeHyprctlCommand("dispatch", std::format("function() if titlebar_menu_at then titlebar_menu_at({}, {}) end end", (int)p.x, (int)p.y));
    });
    return {"shell-bridge", "Apps' minimize + window-menu requests, hyprbars right-click → the shell", "Teerquaz", "1.7"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_onCreate.reset();
    g_onDestroy.reset();
    g_onButton.reset();
    g_onOpen.reset();
    g_listeners.clear();
}
