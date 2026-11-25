import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Right-click menu for the desktop (opened by Wallpaper.qml, one per screen).
// Same look and motion as TitleMenu.qml (GTK menu look from
// ~/.config/gtk-3.0/menus.css, Hyprland popup fade); Hyprland's own layer
// animation is off for it (layer_rule no_anim on ^shell-desktopmenu$).
PanelWindow {
    id: win
    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-desktopmenu"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property bool shown: false
    property real px: 0
    property real py: 0
    property var wallpapers: []

    // x, y in this screen's coordinates
    function open(x, y) {
        px = x; py = y;
        hideTimer.stop();
        visible = true;
        shown = true;
        keys.forceActiveFocus();
        listWalls.running = true;
    }
    function close() { shown = false; hideTimer.restart(); }
    Timer { id: hideTimer; interval: 200; onTriggered: if (!win.shown) win.visible = false }

    // let go of the keyboard first, then act (see TitleMenu.act)
    function act(fn) { actTimer.fn = fn; close(); actTimer.restart(); }
    Timer {
        id: actTimer
        property var fn: null
        interval: 120
        onTriggered: if (fn) fn()
    }

    function nextWallpaper() {
        if (!wallpapers.length) return;
        const i = wallpapers.indexOf(Config.wallpaper);
        Config.setWallpaper(wallpapers[(i + 1) % wallpapers.length]);
    }

    // same list as Settings → Appearance (first copy of a name wins)
    Process {
        id: listWalls
        command: ["sh", "-c", 'for d in "$@"; do find "$d" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) 2>/dev/null; done | sort -u', "sh"].concat(Config.wallpaperDirs)
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, out = [];
                for (const w of text.split("\n")) {
                    if (!w) continue;
                    const b = w.split("/").pop();
                    if (!seen[b]) { seen[b] = 1; out.push(w); }
                }
                win.wallpapers = out;
            }
        }
    }

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
            border.width: 1
            border.color: Theme.bg2

            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

            Column {
                id: col
                x: 6; y: 6
                width: panel.width - 12
                readonly property real widest: {
                    let w = 0;
                    for (let i = 0; i < children.length; i++)
                        if (children[i].implicitWidth > w) w = children[i].implicitWidth;
                    return w;
                }

                TitleMenuRow {
                    label: "Open Terminal"
                    onActivated: win.act(() => Quickshell.execDetached({ command: ["xdg-terminal-exec"], workingDirectory: Quickshell.env("HOME") }))
                }
                TitleMenuRow {
                    label: "Open Files"
                    onActivated: win.act(() => Quickshell.execDetached(["xdg-open", Quickshell.env("HOME")]))
                }
                Item { width: parent.width; height: 13; implicitWidth: 0
                    Rectangle { x: 8; y: 6; width: parent.width - 8 + 5; height: 1; color: Theme.bg2 } }
                TitleMenuRow {
                    label: "Next Wallpaper"
                    visible: win.wallpapers.length > 1
                    onActivated: win.act(() => win.nextWallpaper())
                }
                TitleMenuRow {
                    label: "Change Wallpaper…"
                    onActivated: win.act(() => ShellState.openSettingsPage(0))
                }
                TitleMenuRow {
                    label: "Display Settings"
                    onActivated: win.act(() => ShellState.openSettingsPage(2))
                }
                Item { width: parent.width; height: 13; implicitWidth: 0
                    Rectangle { x: 8; y: 6; width: parent.width - 8 + 5; height: 1; color: Theme.bg2 } }
                TitleMenuRow {
                    label: "Keyboard Shortcuts"
                    onActivated: win.act(() => Quickshell.execDetached(["qs", "ipc", "call", "shortcuts", "toggle"]))
                }
                TitleMenuRow {
                    label: "Settings"
                    onActivated: win.act(() => ShellState.openSettings())
                }
            }
        }
    }
}
