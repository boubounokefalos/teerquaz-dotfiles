import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Shell settings window: appearance, fonts, displays, windows, sound, keyboard
// & mouse, shortcuts, notifications, power & idle, network, default apps,
// date & time, about.
//   qs ipc call settings open
FloatingWindow {
    id: win
    visible: false
    title: "Settings"
    color: Theme.bg0
    implicitWidth: 980
    implicitHeight: 680
    minimumSize: Qt.size(760, 520)

    property int page: 0
    property bool hasGnomeSettings: false
    Process {
        id: gnomeCheck
        command: ["sh", "-c", "command -v gnome-control-center"]
        onExited: (code) => win.hasGnomeSettings = code === 0
    }

    // Closing with the title-bar ✕ unmaps the window but leaves `visible` true,
    // so toggle it to really map a window again.
    function open() {
        visible = false;
        visible = true;
        scan.running = true; displays.load(); defaultApps.load(); dateTime.load(); Net.refresh(); input.load(); shortcuts.load(); windows.load(); about.load(); gnomeCheck.running = true;
    }

    function showPage(n) {
        page = n;
        if (n === 2) displays.load();
        if (n === 3) defaultApps.load();
        if (n === 4) dateTime.load();
        if (n === 5) Net.refresh();
        if (n === 7) input.load();
        if (n === 9) shortcuts.load();
        if (n === 10) windows.load();
        if (n === 12) about.load();
    }

    IpcHandler {
        target: "settings"
        function open(): void { win.open(); }
        function openPage(n: int): void { win.open(); win.showPage(n); }
    }
    Connections {
        target: ShellState
        function onOpenSettings() { win.open(); }
        function onOpenSettingsPage(n) { win.open(); win.showPage(n); }
    }

    // ---------- current values + what's installed ----------
    property var s: ({})              // gsettings values (org.gnome.desktop.interface)
    property var gtkThemes: []
    property var iconThemes: []
    property var cursorThemes: []
    property var wallpapers: []
    readonly property var fontFamilies: Qt.fontFamilies()

    function gset(key, value) {
        const v = {}; for (const k in s) v[k] = s[k]; v[key] = value; s = v;
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", key, String(value)]);
    }
    function setCursor(theme, size) {
        gset("cursor-theme", theme);
        gset("cursor-size", size);
        Quickshell.execDetached(["hyprctl", "setcursor", theme, String(size)]);
    }
    // "Family Name 11" / "Roboto Flex 12 @opsz=12"  ->  { family, size }
    function splitFont(v) {
        const m = /^(.*?)\s+(\d+(?:\.\d+)?)(?:\s+@.*)?$/.exec(v || "");
        return m ? { family: m[1], size: parseFloat(m[2]) } : { family: v || "", size: 11 };
    }
    function setFont(key, family, size) { gset(key, family + " " + size); }

    Process {
        id: scan
        command: ["sh", "-c", `
            for k in gtk-theme icon-theme cursor-theme cursor-size font-name document-font-name monospace-font-name; do
                printf 'S\\t%s\\t%s\\n' "$k" "$(gsettings get org.gnome.desktop.interface $k | sed "s/^'//;s/'$//")"
            done
            for d in "$HOME/.local/share/themes" "$HOME/.themes" /usr/share/themes; do
                for t in "$d"/*/; do [ -d "$t/gtk-3.0" ] && printf 'G\\t%s\\n' "$(basename "$t")"; done
            done
            for d in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
                for t in "$d"/*/; do
                    [ -f "$t/index.theme" ] || [ -d "$t/cursors" ] || continue
                    n=$(basename "$t")
                    [ -d "$t/cursors" ] && printf 'C\\t%s\\n' "$n"
                    other=$(find "$t" -mindepth 1 -maxdepth 1 -type d ! -name cursors | head -1)
                    [ -n "$other" ] && [ "$n" != default ] && [ "$n" != hicolor ] && [ "$n" != locolor ] && printf 'I\\t%s\\n' "$n"
                done
            done
            for d in ${win.wallpaperDirsShell}; do
                find "$d" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null
            done | sort -u | sed 's/^/W\\t/'
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const st = {}, g = [], ic = [], cu = [], wp = [];
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "S") st[p[1]] = p[2];
                    else if (p[0] === "G" && g.indexOf(p[1]) < 0) g.push(p[1]);
                    else if (p[0] === "I" && ic.indexOf(p[1]) < 0) ic.push(p[1]);
                    else if (p[0] === "C" && cu.indexOf(p[1]) < 0) cu.push(p[1]);
                    else if (p[0] === "W") wp.push(p[1]);
                }
                win.s = st;
                win.gtkThemes = g.sort();
                win.iconThemes = ic.sort();
                win.cursorThemes = cu.sort();
                // same picture in two folders: keep the first
                const seen = {}, uniq = [];
                for (const w of wp) { const b = w.split("/").pop(); if (!seen[b]) { seen[b] = 1; uniq.push(w); } }
                win.wallpapers = uniq;
            }
        }
    }
    readonly property string wallpaperDirsShell: Config.wallpaperDirs.map(d => "'" + d + "'").join(" ")

    // ---------- layout ----------
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // sidebar
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            color: Theme.bg0s

            Column {
                anchors { fill: parent; margins: 14 }
                spacing: 4

                Text {
                    text: "Settings"
                    color: Theme.fg0
                    leftPadding: 8; bottomPadding: 12; topPadding: 6
                    font { family: Theme.fontDisplay; pixelSize: 22; weight: Font.Bold }
                }

                Repeater {
                    model: [
                        // page numbers stay fixed (ShellState.openSettingsPage / IPC openPage use them)
                        { icon: "palette",         label: "Appearance",       page: 0 },
                        { icon: "text_fields",     label: "Fonts",            page: 1 },
                        { icon: "desktop_windows", label: "Displays",         page: 2 },
                        { icon: "select_window",   label: "Windows",          page: 10 },
                        { icon: "volume_up",       label: "Sound",            page: 6 },
                        { icon: "keyboard",        label: "Keyboard & mouse", page: 7 },
                        { icon: "keyboard_command_key", label: "Shortcuts",   page: 9 },
                        { icon: "notifications",   label: "Notifications",    page: 11 },
                        { icon: "power_settings_new", label: "Power & idle",  page: 8 },
                        { icon: "lan",             label: "Network",          page: 5 },
                        { icon: "apps",            label: "Default apps",     page: 3 },
                        { icon: "schedule",        label: "Date & time",      page: 4 },
                        { icon: "info",            label: "About",            page: 12 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: win.page === modelData.page
                        width: parent.width; height: 42; radius: 12
                        color: sel ? Theme.yellowDim : (nh.hovered ? Theme.bg1 : Theme.clear(Theme.bg1))
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 12
                            Text { text: modelData.icon; color: sel ? Theme.bg0 : Theme.fg1; font { family: Theme.fontIcons; pixelSize: 20 } }
                            Text { text: modelData.label; color: sel ? Theme.bg0 : Theme.fg1; font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                        }
                        HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.showPage(modelData.page) }
                    }
                }
            }

            // fallback for everything not covered here yet (gone once GNOME is removed)
            Rectangle {
                visible: win.hasGnomeSettings
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                height: 42; radius: 12
                color: gh.hovered ? Theme.bg1 : Theme.clear(Theme.bg1)
                Row {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Text { text: "open_in_new"; color: Theme.fg4; font { family: Theme.fontIcons; pixelSize: 20 } }
                    Text { text: "GNOME Settings"; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                }
                HoverHandler { id: gh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Quickshell.execDetached(["sh", "-c", "XDG_CURRENT_DESKTOP=GNOME gnome-control-center"]) }
            }
        }

        // pages
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: pages.implicitHeight + 64
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: pages
                x: 32; y: 28
                width: flick.width - 64
                implicitHeight: [appearance, fonts, displays, defaultApps, dateTime, network, sound, input, power, shortcuts, windows, notifications, about][win.page].implicitHeight

                // ===== Appearance =====
                ColumnLayout {
                    id: appearance
                    width: parent.width
                    spacing: 14
                    visible: win.page === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }

                    SectionTitle { text: "Wallpaper" }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 14
                        Repeater {
                            model: win.wallpapers
                            delegate: Item {
                                id: thumb
                                required property string modelData
                                readonly property bool sel: Config.wallpaper === modelData
                                width: 208; height: 117
                                scale: th.hovered ? 1.03 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Easing.OutBack } }
                                Image {
                                    id: img
                                    anchors.fill: parent
                                    source: "file://" + thumb.modelData
                                    sourceSize: Qt.size(416, 234)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: false
                                }
                                Rectangle { id: mask; anchors.fill: parent; radius: 14; visible: false; layer.enabled: true }
                                MultiEffect { anchors.fill: parent; source: img; maskEnabled: true; maskSource: mask }
                                Rectangle {
                                    anchors.fill: parent; radius: 14
                                    color: "transparent"
                                    border.width: thumb.sel ? 3 : (th.hovered ? 2 : 0)
                                    border.color: thumb.sel ? Theme.yellow : Theme.bg3
                                }
                                Rectangle {
                                    visible: thumb.sel
                                    anchors { right: parent.right; top: parent.top; margins: 8 }
                                    width: 26; height: 26; radius: 13
                                    color: Theme.yellow
                                    Text { anchors.centerIn: parent; text: "check"; color: Theme.bg0; font { family: Theme.fontIcons; pixelSize: 18; weight: Font.Bold } }
                                }
                                HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Config.setWallpaper(thumb.modelData) }
                            }
                        }
                        // open folder tile
                        Rectangle {
                            width: 208; height: 117; radius: 14
                            color: fh.hovered ? Theme.bg2 : Theme.bg1
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "add_photo_alternate"; color: Theme.fg4; font { family: Theme.fontIcons; pixelSize: 30 } }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Open Wallpapers folder"; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                            }
                            HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/Pictures/Wallpapers\" && xdg-open \"$HOME/Pictures/Wallpapers\""]) }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Pictures in ~/Pictures/Wallpapers show up here (reopen Settings after adding some)."
                        color: Theme.fg4
                        wrapMode: Text.WordWrap
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }

                    SectionTitle { text: "Style"; Layout.topMargin: 14 }

                    SettingRow {
                        label: "Application theme"; hint: "GTK 3 apps; GTK 4 apps use the Teerquaz libadwaita override"
                        Dropdown { model: win.gtkThemes; current: win.s["gtk-theme"] || ""; onPicked: (v) => win.gset("gtk-theme", v) }
                    }
                    SettingRow {
                        label: "Icons"
                        Dropdown { model: win.iconThemes; current: win.s["icon-theme"] || ""; onPicked: (v) => win.gset("icon-theme", v) }
                    }
                    SettingRow {
                        label: "Cursor"
                        Dropdown {
                            model: win.cursorThemes; current: win.s["cursor-theme"] || ""
                            onPicked: (v) => win.setCursor(v, parseInt(win.s["cursor-size"] || "24"))
                        }
                    }
                    SettingRow {
                        label: "Cursor size"
                        Dropdown {
                            model: ["16", "24", "32", "48", "64"]; current: win.s["cursor-size"] || "24"
                            onPicked: (v) => win.setCursor(win.s["cursor-theme"] || "default", parseInt(v))
                        }
                    }
                }

                // ===== Default apps =====
                DefaultAppsPage {
                    id: defaultApps
                    width: parent.width
                    visible: win.page === 3
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                // ===== Date & time =====
                DateTimePage {
                    id: dateTime
                    width: parent.width
                    visible: win.page === 4
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                // ===== Network =====
                NetworkPage {
                    id: network
                    width: parent.width
                    shown: win.visible && win.page === 5
                    visible: win.page === 5
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                // ===== Sound =====
                SoundPage {
                    id: sound
                    width: parent.width
                    shown: win.visible && win.page === 6
                    visible: win.page === 6
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                // ===== Keyboard & mouse =====
                InputPage {
                    id: input
                    width: parent.width
                    visible: win.page === 7
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                // ===== Power & idle =====
                PowerPage {
                    id: power
                    width: parent.width
                    visible: win.page === 8
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                ShortcutsPage {
                    id: shortcuts
                    width: parent.width
                    visible: win.page === 9
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                WindowsPage {
                    id: windows
                    width: parent.width
                    visible: win.page === 10
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                NotificationsPage {
                    id: notifications
                    width: parent.width
                    visible: win.page === 11
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                AboutPage {
                    id: about
                    width: parent.width
                    visible: win.page === 12
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                // ===== Displays =====
                DisplaysPage {
                    id: displays
                    width: parent.width
                    visible: win.page === 2
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                }

                // ===== Fonts =====
                ColumnLayout {
                    id: fonts
                    width: parent.width
                    spacing: 14
                    visible: win.page === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durMed } }

                    SectionTitle { text: "Fonts" }

                    Repeater {
                        model: [
                            { key: "font-name",           label: "Interface",  hint: "Menus, buttons, labels" },
                            { key: "document-font-name",  label: "Documents",  hint: "Reading text in documents and web pages" },
                            { key: "monospace-font-name", label: "Monospace",  hint: "Terminals and code" }
                        ]
                        delegate: SettingRow {
                            id: fr
                            required property var modelData
                            readonly property var f: win.splitFont(win.s[modelData.key])
                            label: modelData.label
                            hint: modelData.hint
                            Row {
                                spacing: 8
                                Dropdown {
                                    model: win.fontFamilies; previewFont: true
                                    current: fr.f.family
                                    onPicked: (v) => win.setFont(fr.modelData.key, v, fr.f.size)
                                }
                                Stepper {
                                    value: fr.f.size
                                    onChanged: (v) => win.setFont(fr.modelData.key, fr.f.family, v)
                                }
                            }
                        }
                    }

                    // preview
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        implicitHeight: prev.implicitHeight + 32
                        radius: 16
                        color: Theme.bg1
                        Column {
                            id: prev
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                            spacing: 10
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "Interface — The quick brown fox jumps over the lazy dog"
                                color: Theme.fg1
                                font.family: win.splitFont(win.s["font-name"]).family
                                font.pointSize: win.splitFont(win.s["font-name"]).size
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "Documents — Η γρήγορη καφέ αλεπού πηδάει πάνω από τον τεμπέλη σκύλο"
                                color: Theme.fg1
                                font.family: win.splitFont(win.s["document-font-name"]).family
                                font.pointSize: win.splitFont(win.s["document-font-name"]).size
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "Monospace — fn main() { println!(\"0O 1lI {}\", 42); }"
                                color: Theme.fg1
                                font.family: win.splitFont(win.s["monospace-font-name"]).family
                                font.pointSize: win.splitFont(win.s["monospace-font-name"]).size
                            }
                        }
                    }
                }
            }
        }
    }

}
