import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Clipboard history (cliphist): the shell stores everything copied (text and
// pictures) and Super+Shift+V picks an older entry to copy again.
//   qs ipc call clipboard toggle
// ↑↓ choose · Enter copies · Delete removes · Esc closes · type to search
PanelWindow {
    id: win

    property bool open: false
    property bool available: false
    property var entries: []           // [{ id, text, image }]
    property int current: 0
    readonly property string cacheDir: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-clip"

    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-panel-clipboard"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card }

    // ---------- store: watch the clipboard (only when cliphist is installed) ----------
    // (checked again on open, so installing cliphist later just works)
    property bool wantOpen: false
    Timer { interval: 30000; repeat: true; running: !win.available; triggeredOnStart: true; onTriggered: check.running = true }
    Process {
        id: check
        command: ["sh", "-c", "command -v cliphist"]
        onExited: (code) => {
            win.available = code === 0;
            if (!win.wantOpen) return;
            win.wantOpen = false;
            if (win.available) win.show();
            else Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "content_paste_off", "Clipboard history needs cliphist"]);
        }
    }
    Process {
        running: win.available
        command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]
    }
    Process {
        running: win.available
        command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { win.open ? win.hide() : win.show(); }
        function wipe(): void { win.wipe(); }
    }

    function show() {
        if (!available) { wantOpen = true; check.running = true; return; }
        search.text = ""; current = 0;
        visible = true; open = true;
        load();
        search.forceActiveFocus();
    }
    function hide() { open = false; hideTimer.restart(); }
    Timer { id: hideTimer; interval: Theme.durMed; onTriggered: if (!win.open) win.visible = false }

    function load() { lister.running = true; }
    Process {
        id: lister
        // decode pictures for the thumbnails first, then print the list
        command: ["sh", "-c", "d='" + win.cacheDir + "'; mkdir -p \"$d\"; l=$(cliphist list | head -150); "
            + "printf '%s\\n' \"$l\" | grep -P '^\\d+\\t\\[\\[ binary data' | cut -f1 | while read -r i; do "
            + "[ -s \"$d/$i.png\" ] || printf '%s\\t\\n' \"$i\" | cliphist decode > \"$d/$i.png\"; done; printf '%s\\n' \"$l\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i < 0) continue;
                    const id = line.slice(0, i), t = line.slice(i + 1);
                    const img = /^\[\[ binary data .*(png|jpe?g|webp|bmp|gif)/i.test(t);
                    out.push({ id: id, text: t, image: img, line: line });
                }
                win.entries = out;
            }
        }
    }

    readonly property var filtered: {
        const q = search.text.trim().toLowerCase();
        return q ? entries.filter(e => !e.image && e.text.toLowerCase().indexOf(q) >= 0) : entries;
    }
    onFilteredChanged: current = 0

    function pick(e) {
        if (!e) return;
        // cliphist decode takes the list line on stdin
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist decode | wl-copy", "sh", e.id]);
        hide();
        Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "content_paste", "Copied — paste with Ctrl+V"]);
    }
    function remove(e) {
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", e.line]);
        entries = entries.filter(x => x.id !== e.id);
    }
    function wipe() {
        Quickshell.execDetached(["sh", "-c", "cliphist wipe; rm -rf '" + cacheDir + "'"]);
        entries = [];
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
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        width: 620
        height: Math.min(parent.height * 0.68, 76 + Math.max(1, win.filtered.length) * 62 + 52)
        radius: Theme.radiusPanel
        color: Theme.bg0s
        border.width: 1
        border.color: Theme.bg2
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
        Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
        MouseArea { anchors.fill: parent }       // keep clicks inside from closing

        // search
        Rectangle {
            id: box
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            height: 48; radius: Theme.radius
            color: Theme.bg1
            Text {
                id: sIcon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "content_paste_search"; color: Theme.fg4
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
                    text: "Clipboard history"
                    color: Theme.bg3
                    font: search.font
                }
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { win.hide(); e.accepted = true; }
                    else if (e.key === Qt.Key_Down || (e.key === Qt.Key_Tab)) { win.current = Math.min(win.filtered.length - 1, win.current + 1); list.positionViewAtIndex(win.current, ListView.Contain); e.accepted = true; }
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { win.current = Math.max(0, win.current - 1); list.positionViewAtIndex(win.current, ListView.Contain); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.pick(win.filtered[win.current]); e.accepted = true; }
                    else if (e.key === Qt.Key_Delete) { win.remove(win.filtered[win.current]); e.accepted = true; }
                }
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: box.bottom; bottom: foot.top; margins: 12; topMargin: 8; bottomMargin: 4 }
            clip: true
            spacing: 2
            model: win.filtered
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool sel: index === win.current
                width: ListView.view.width
                height: 60
                radius: Theme.radiusItem
                color: sel ? Theme.yellowDim : (rh.hovered ? Theme.bg2 : Theme.clear(Theme.bg2))
                HoverHandler { id: rh; onHoveredChanged: if (hovered) win.current = row.index }
                TapHandler { onTapped: win.pick(row.modelData) }

                Image {
                    id: thumb
                    visible: row.modelData.image
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: 72; height: 46
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(144, 92)
                    asynchronous: true
                    cache: false
                    source: row.modelData.image ? "file://" + win.cacheDir + "/" + row.modelData.id + ".png" : ""
                }
                Text {
                    anchors { left: row.modelData.image ? thumb.right : parent.left; leftMargin: 12; right: del.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: row.modelData.image ? "Picture" : row.modelData.text.replace(/\s+/g, " ").trim()
                    maximumLineCount: 2
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideRight
                    color: row.sel ? Theme.bg0 : Theme.fg1
                    font { family: Theme.fontUi; pixelSize: 14; weight: row.sel ? Font.Bold : Font.Normal }
                }
                RoundIcon {
                    id: del
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    size: 32
                    icon: "close"
                    visible: rh.hovered || row.sel
                    onClicked: win.remove(row.modelData)
                }
            }
        }
        Text {
            anchors.centerIn: list
            visible: win.filtered.length === 0
            text: win.entries.length ? "Nothing matches" : "Nothing copied yet"
            color: Theme.fg4
            font { family: Theme.fontUi; pixelSize: 14 }
        }

        Item {
            id: foot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            height: 36
            Text {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: "Enter copies · Delete removes · Esc closes"
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            PillButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                implicitHeight: 32
                text: "Clear all"
                visible: win.entries.length > 0
                onClicked: win.wipe()
            }
        }
    }
}
