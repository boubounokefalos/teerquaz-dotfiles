import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Alt+Tab switcher with live previews, most recently used first, all workspaces.
// Hyprland drives it (it watches the Alt key):
//   qs ipc call switcher next | prev | commit | cancel
PanelWindow {
    id: sw
    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-switcher"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: panel }
    BackgroundEffect.blurRegion: Region { item: blurArea; radius: Theme.radiusPanel }

    property bool open: false
    property bool loading: false
    property var items: []            // [{ address, title, cls, ws, top, w, h }]
    property int index: 0
    property int pendingSteps: 0      // Tab presses that arrived while loading
    property bool pendingCommit: false

    function step(d) {
        if (!open && !loading) { start(d); return; }
        if (loading) { pendingSteps += d; return; }
        if (items.length) index = (index + d + items.length) % items.length;
    }
    function start(d) {
        loading = true;
        pendingSteps = d;
        pendingCommit = false;
        loader.running = true;
    }
    function commit() {
        if (loading) { pendingCommit = true; return; }
        if (!open) return;
        const it = items[index];
        close();
        // Focus only after our panel has given up exclusive keyboard focus:
        // Hyprland ignores focus changes while an exclusive layer holds it.
        if (it) { focusTarget = it.address; focusTimer.restart(); }
    }
    property string focusTarget: ""
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: {
            const a = sw.focusTarget;
            if (!a) return;
            // cursor.no_warps for this call only, so the pointer stays where it is
            Hyprland.dispatch('function() hl.config({ cursor = { no_warps = true } }); '
                              + 'hl.dispatch(hl.dsp.focus({ window = "address:' + a + '" })); '
                              + 'hl.config({ cursor = { no_warps = false } }) end');
            Hyprland.dispatch('hl.dsp.window.alter_zorder({ window = "address:' + a + '", mode = "top" })');
            sw.focusTarget = "";
        }
    }
    function close() { open = false; hideTimer.restart(); }
    function cancel() { pendingCommit = false; loading = false; if (open) close(); }

    Timer { id: hideTimer; interval: Theme.durMed; onTriggered: if (!sw.open) sw.visible = false }

    IpcHandler {
        target: "switcher"
        function next(): void { sw.step(1); }
        function prev(): void { sw.step(-1); }
        function commit(): void { sw.commit(); }
        function cancel(): void { sw.cancel(); }
    }

    Process {
        id: loader
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!sw.loading) return;     // cancelled meanwhile
                let list = [];
                try { list = JSON.parse(text); } catch (e) {}
                list = list.filter(c => c.mapped && !c.hidden && c.workspace && c.workspace.id > 0)
                           .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
                const tops = Hyprland.toplevels.values;
                sw.items = list.map(c => ({
                    address: c.address, title: c.title, cls: c.class, ws: c.workspace.id,
                    w: c.size[0], h: c.size[1],
                    top: tops.find(t => t.address === c.address || "0x" + t.address === c.address) || null
                }));
                sw.loading = false;
                if (!sw.items.length) return;
                // first press goes to the previous window
                sw.index = ((sw.pendingSteps > 0 ? sw.pendingSteps : sw.items.length + sw.pendingSteps) % sw.items.length + sw.items.length) % sw.items.length;
                if (sw.pendingCommit) { sw.open = true; sw.commit(); return; }
                sw.visible = true;
                sw.open = true;
                keys.forceActiveFocus();
            }
        }
    }

    // ---------- look ----------
    readonly property int maxW: Math.min(width - 160, 1800)
    readonly property real cardH: Math.min(190, (maxW - 40) / Math.max(1, items.length) * 0.6)

    Item {
        id: blurArea
        anchors.centerIn: parent
        width: panel.width; height: panel.height
        opacity: 0
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(sw.maxW, Math.max(560, row.implicitWidth + 48))
        height: row.implicitHeight + 48 + 40
        radius: Theme.radiusPanel
        color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.82)
        border.width: 1
        border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)
        opacity: sw.open ? 1 : 0
        scale: sw.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
        Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { sw.cancel(); e.accepted = true; }
                else if (e.key === Qt.Key_Left) { sw.step(-1); e.accepted = true; }
                else if (e.key === Qt.Key_Right) { sw.step(1); e.accepted = true; }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { sw.commit(); e.accepted = true; }
            }
            Keys.onReleased: (e) => { if (e.key === Qt.Key_Alt) { sw.commit(); e.accepted = true; } }
        }

        Row {
            id: row
            anchors { top: parent.top; topMargin: 24; horizontalCenter: parent.horizontalCenter }
            spacing: 14

            Repeater {
                model: sw.items
                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === sw.index
                    readonly property real s: Math.min(sw.cardH / modelData.h, (sw.cardH * 1.7) / modelData.w)
                    width: Math.max(90, modelData.w * s)
                    height: sw.cardH

                    Rectangle {
                        anchors { fill: parent; margins: -6 }
                        radius: Theme.radius
                        color: card.sel ? Qt.rgba(Theme.yellowDim.r, Theme.yellowDim.g, Theme.yellowDim.b, 0.25) : (ch.hovered ? Theme.bg1 : Theme.clear(Theme.bg1))
                        border.width: card.sel ? 2 : 0
                        border.color: Theme.yellowDim
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                    }

                    ScreencopyView {
                        id: cap
                        anchors.centerIn: parent
                        width: card.modelData.w * card.s
                        height: card.modelData.h * card.s
                        captureSource: card.modelData.top ? card.modelData.top.wayland : null
                        // One picture per opening, not live: on NVIDIA every live
                        // frame leaks a few file handles until qs hits its limit
                        // and the desktop freezes (2026-11-23).
                        live: false
                        visible: false
                    }
                    Rectangle { id: mask; anchors.fill: cap; radius: 12; visible: false; layer.enabled: true }
                    MultiEffect { anchors.fill: cap; source: cap; maskEnabled: true; maskSource: mask }
                    Rectangle { anchors.fill: cap; radius: 12; color: Theme.bg1; visible: !cap.hasContent }

                    // app icon badge
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -14 }
                        width: 40; height: 40; radius: 12
                        color: Theme.bg0
                        border.width: 1; border.color: Theme.bg2
                        Image {
                            anchors.centerIn: parent
                            width: 28; height: 28
                            sourceSize: Qt.size(56, 56)
                            source: {
                                const e = DesktopEntries.heuristicLookup(card.modelData.cls);
                                return Quickshell.iconPath(e && e.icon ? e.icon : card.modelData.cls, "application-x-executable");
                            }
                        }
                    }

                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) sw.index = card.index }
                    TapHandler { onTapped: { sw.index = card.index; sw.commit(); } }
                }
            }
        }

        // title of the selected window
        Text {
            anchors { bottom: parent.bottom; bottomMargin: 18; horizontalCenter: parent.horizontalCenter }
            width: parent.width - 60
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            readonly property var it: sw.items[sw.index]
            text: it ? it.title + (it.ws ? "   ·   workspace " + it.ws : "") : ""
            color: Theme.fg1
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
        }
    }
}
