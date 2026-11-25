import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Right-click menu for the title bars Hyprland draws (hyprbars: Thunar,
// zathura, Xarchiver, Settings, ckb-next). Those bars only have – and ✕, so
// Maximize lives here.
//
// It must look and move exactly like the right-click menus of apps' own title
// bars (Chrome, GTK apps), which are Wayland popups:
//   look   = ~/.config/gtk-3.0/menus.css, measured on a real GTK menu: solid
//            bg0s panel, corner ~12 px, shadow 0 8 24 rgba(0,0,0,.45) + 1 px
//            bg2 ring, padding 6, rows 38 px, text 44 px from the edge (GTK
//            keeps an icon/check column), Nunito 11pt regular, hover yellowDim
//            pill (radius 10) + bg0 text, 13 px separator block with the line
//            14 px in from the left, width fitted to the labels, no icons
//   motion = Hyprland's popup animation (hyprland.lua "fade" / "fadeOut"):
//            fade in 300 ms "standard" curve, fade out 200 ms linear, no slide.
//            Hyprland's own layer animation is off for this surface
//            (layer_rule no_anim on ^shell-titlemenu$) so only this one plays.
//   qs ipc call titlemenu open <address> <x> <y> <maximized 0|1>
// (called by ~/.config/hypr/titlebars.lua via the shell-bridge plugin)
PanelWindow {
    id: win
    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-titlemenu"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property bool shown: false
    property string address: ""
    property bool maximized: false
    property real px: 0
    property real py: 0

    function open(addr, x, y, max) {
        address = addr;
        maximized = max;
        // global layout coordinates → this screen
        const s = win.screen;
        px = x - (s ? s.x : 0);
        py = y - (s ? s.y : 0);
        hideTimer.stop();
        visible = true;
        shown = true;
        keys.forceActiveFocus();
    }
    function close() { shown = false; hideTimer.restart(); }
    Timer { id: hideTimer; interval: 200; onTriggered: if (!win.shown) win.visible = false }

    // The menu holds the keyboard; when it lets go, Hyprland refocuses the last
    // window. Done at the same time as Minimize, that refocus landed on the
    // window already on the shelf and opened the shelf (the window "stayed on
    // screen"). So: release the keyboard first, run the action a moment later.
    function act(lua) {
        const w = 'window = "address:' + address + '"';
        actTimer.cmd = lua.replace("%W", w).replace("%A", address);
        close();
        actTimer.restart();
    }
    Timer {
        id: actTimer
        property string cmd: ""
        interval: 120
        onTriggered: Hyprland.dispatch(cmd)
    }

    IpcHandler {
        target: "titlemenu"
        function open(address: string, x: int, y: int, maximized: int): void { win.open(address, x, y, maximized === 1); }
        function close(): void { win.close(); }
    }

    // any click outside the menu (left, right, middle) just closes it
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: win.close()
    }
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: win.close()
    }

    Item {
        id: menu
        width: Math.max(150, col.widest + 12)
        height: col.implicitHeight + 12
        // opens at the pointer (below-right), flipped to stay on screen — like a popup
        x: Math.max(8, Math.min(win.px, win.width - width - 8))
        y: Math.max(8, Math.min(win.py, win.height - height - 8))
        opacity: win.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: win.shown ? 300 : 200
                easing.type: win.shown ? Easing.BezierSpline : Easing.Linear
                easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]   // Hyprland "standard"
            }
        }

        // box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45)
        RectangularShadow {
            anchors.fill: panel
            offset.y: 8
            blur: 24
            radius: panel.radius
            color: Qt.rgba(0, 0, 0, 0.45)
        }
        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 12
            color: Theme.bg0s
            border.width: 1                 // the 0 0 0 1px #504945 ring
            border.color: Theme.bg2

            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // padding clicks stay here

            Column {
                id: col
                x: 6; y: 6
                width: panel.width - 12
                readonly property real widest: Math.max(r1.implicitWidth, r2.implicitWidth, r3.implicitWidth)

                TitleMenuRow {
                    id: r1
                    label: "Minimize"
                    onActivated: win.act('function() package.loaded["gnome-like"].minimize(hl.get_window("address:%A")) end')
                }
                TitleMenuRow {
                    id: r2
                    label: win.maximized ? "Restore" : "Maximize"
                    onActivated: win.act('hl.dsp.window.fullscreen({ %W, mode = "maximized", action = "toggle" })')
                }
                Item {               // menu separator: 13 px block, 1 px bg2 line 14 px from the panel's left
                    width: parent.width; height: 13
                    Rectangle { x: 8; y: 6; width: parent.width - 8 + 5; height: 1; color: Theme.bg2 }
                }
                TitleMenuRow {
                    id: r3
                    label: "Close"
                    onActivated: win.act('hl.dsp.window.close({ %W })')
                }
            }
        }
    }
}
