import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Shortcuts cheat sheet: every Hyprland binding (Binds.qml) in a popup,
// grouped into columns. Super+F1 or Super+/ (again, Esc or a click outside closes).
//   qs ipc call shortcuts toggle
// Type to search; the full list with a bigger layout is Settings → Shortcuts.
PanelWindow {
    id: win

    property bool open: false

    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-panel-shortcuts"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card }

    IpcHandler {
        target: "shortcuts"
        function toggle(): void { win.open ? win.hide() : win.show(); }
    }

    function show() {
        Binds.load();                 // re-read, so new binds show up at once
        search.text = "";
        visible = true; open = true;
        search.forceActiveFocus();
    }
    function hide() { open = false; hideTimer.restart(); }
    Timer { id: hideTimer; interval: Theme.durMed; onTriggered: if (!win.open) win.visible = false }

    readonly property string query: search.text.trim().toLowerCase()
    // groups with only the matching rows
    readonly property var shown: Binds.groups
        .map(g => ({ name: g.name, rows: g.rows.filter(r => Binds.matches(r, query)) }))
        .filter(g => g.rows.length > 0)

    // spread the groups over the columns: each goes to the shortest column so far
    readonly property int columnCount: card.width > 1300 ? 3 : 2
    readonly property real columnWidth: (cols.width - (columnCount - 1) * cols.spacing) / columnCount
    readonly property var columns: {
        const out = [], h = [];
        for (let i = 0; i < columnCount; i++) { out.push([]); h.push(0); }
        for (const g of shown) {
            let k = 0;
            for (let i = 1; i < columnCount; i++) if (h[i] < h[k]) k = i;
            out[k].push(g);
            h[k] += g.rows.length + 2;          // + the title
        }
        return out;
    }

    // click outside closes
    MouseArea { anchors.fill: parent; onClicked: win.hide() }
    Rectangle {
        anchors.fill: parent
        color: Theme.bg0
        opacity: win.open ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 160, 1480)
        height: Math.min(parent.height * 0.86, head.height + cols.implicitHeight + foot.height + 48)
        radius: Theme.radiusPanel
        color: Theme.bg0s
        border.width: 1
        border.color: Theme.bg2
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
        Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
        MouseArea { anchors.fill: parent }       // keep clicks inside from closing

        // ---------- header: title + search ----------
        Item {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            height: 48
            Text {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: "Keyboard shortcuts"
                color: Theme.fg0
                font { family: Theme.fontDisplay; pixelSize: 22; weight: Font.Bold }
            }
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 380
                radius: Theme.radius
                color: Theme.bg1
                Text {
                    id: sIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "search"; color: Theme.fg4
                    font { family: Theme.fontIcons; pixelSize: 22 }
                }
                TextInput {
                    id: search
                    anchors { left: sIcon.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: Theme.fg1
                    selectionColor: Theme.yellowDim
                    font { family: Theme.fontUi; pixelSize: 16; weight: Font.DemiBold }
                    clip: true
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search shortcuts"
                        color: Theme.bg3
                        font: search.font
                    }
                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Escape) { win.hide(); e.accepted = true; }
                        else if (e.key === Qt.Key_Down || e.key === Qt.Key_PageDown) { flick.flick(0, -1600); e.accepted = true; }
                        else if (e.key === Qt.Key_Up || e.key === Qt.Key_PageUp) { flick.flick(0, 1600); e.accepted = true; }
                    }
                }
            }
        }

        // ---------- groups in columns ----------
        Flickable {
            id: flick
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: 16; topMargin: 14; bottomMargin: 6 }
            clip: true
            contentHeight: cols.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: cols
                width: flick.width
                spacing: 16
                Repeater {
                    model: win.columns
                    delegate: Column {
                        id: column
                        required property var modelData
                        width: win.columnWidth
                        spacing: 16
                        Repeater {
                            model: column.modelData
                            delegate: Column {
                                id: grp
                                required property var modelData
                                width: column.width
                                spacing: 6
                                SectionTitle { text: grp.modelData.name; leftPadding: 4; font.pixelSize: 16 }
                                Rectangle {
                                    width: parent.width
                                    height: list.implicitHeight + 8
                                    radius: Theme.radius
                                    color: Theme.bg1
                                    Column {
                                        id: list
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                                        Repeater {
                                            model: grp.modelData.rows
                                            delegate: Rectangle {
                                                id: row
                                                required property var modelData
                                                width: list.width
                                                height: Math.max(38, keys.implicitHeight + 10)
                                                radius: Theme.radiusItem
                                                color: rh.hovered ? Theme.bg2 : Theme.clear(Theme.bg2)
                                                HoverHandler { id: rh }
                                                Text {
                                                    anchors { left: parent.left; leftMargin: 10; right: keys.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                                    text: row.modelData.text
                                                    elide: Text.ElideRight
                                                    color: Theme.fg1
                                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                                                }
                                                KeyCaps {
                                                    id: keys
                                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                                    combos: row.modelData.combos
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            anchors.centerIn: flick
            visible: win.shown.length === 0
            text: Binds.groups.length ? "No shortcut matches “" + search.text + "”" : "Reading shortcuts…"
            color: Theme.fg4
            font { family: Theme.fontUi; pixelSize: 14 }
        }

        // ---------- footer ----------
        Item {
            id: foot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
            height: 36
            Text {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: "Type to search · Esc closes"
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            PillButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                implicitHeight: 32
                text: "Open in Settings"
                onClicked: { win.hide(); ShellState.openSettingsPage(9); }
            }
        }
    }
}
