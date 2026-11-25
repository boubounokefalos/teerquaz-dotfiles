import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

// Flat top bar: workspaces + window title | clock | tray, layout, battery, volume
PanelWindow {
    id: bar
    WlrLayershell.namespace: "shell-bar"
    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    color: Theme.bg0

    readonly property var monitor: Hyprland.monitorFor(bar.screen)

    // tray icon menus, drawn by the shell so they match Settings
    TrayMenu { id: trayMenu }
    NetMenu { id: netMenu }
    DrivesMenu { id: drivesMenu }
    LayoutMenu { id: layoutMenu }

    // "Keep Awake" from quick settings
    IdleInhibitor { window: bar; enabled: ShellState.keepAwake }

    // thin separator line under the bar
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.bg1
    }

    // ---------- left: workspaces + active window ----------
    RowLayout {
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 14

        Row {
            id: wsRow
            spacing: 6
            readonly property int activeId: bar.monitor && bar.monitor.activeWorkspace ? bar.monitor.activeWorkspace.id : 1
            readonly property int count: {
                let max = 5;
                const list = Hyprland.workspaces.values;
                for (let i = 0; i < list.length; i++)
                    if (list[i].id > max && list[i].id <= 10) max = list[i].id;
                return Math.max(max, activeId);
            }

            Repeater {
                model: wsRow.count
                delegate: Rectangle {
                    id: pill
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property bool active: wsId === wsRow.activeId
                    readonly property bool occupied: {
                        const list = Hyprland.workspaces.values;
                        for (let i = 0; i < list.length; i++)
                            if (list[i].id === wsId && list[i].toplevels.values.length > 0) return true;
                        return false;
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    height: 10
                    radius: 5
                    width: active ? 30 : (hover.hovered ? 14 : 10)
                    color: active ? Theme.yellow : (occupied ? Theme.fg4 : Theme.bg3)

                    Behavior on width { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
                    Behavior on color { ColorAnimation  { duration: Theme.durMed; easing.type: Theme.easeOut } }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: Hyprland.dispatch("hl.dsp.focus({ workspace = " + pill.wsId + " })")
                    }
                }
            }

            WheelHandler {
                onWheel: (e) => Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + (e.angleDelta.y < 0 ? "e+1" : "e-1") + "\" })")
            }
        }

        Text {
            id: title
            readonly property var toplevel: ToplevelManager.activeToplevel
            text: toplevel && toplevel.title ? toplevel.title : ""
            color: Theme.fg4
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            elide: Text.ElideRight
            Layout.maximumWidth: bar.width * 0.28
            opacity: text.length ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
        }
    }

    // ---------- centre: clock ----------
    SystemClock { id: clock; precision: SystemClock.Minutes }

    // clock (+ notification dot / DND); click opens the date menu (calendar + notifications)
    Row {
        anchors.centerIn: parent
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, Config.clock24 ? "ddd d MMM   HH:mm" : "ddd d MMM   h:mm AP")
            color: Theme.fg1
            font { family: Theme.fontDisplay; pixelSize: 14; weight: Font.Bold }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: ShellState.doNotDisturb
            text: "notifications_off"
            color: Theme.fg4
            font { family: Theme.fontIcons; pixelSize: 16 }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: !ShellState.doNotDisturb && Notifs.count > 0
            width: 7; height: 7; radius: 3.5
            color: Theme.blue
        }
        TapHandler { onTapped: ShellState.toggleDatePanel() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    // ---------- right: tray, keyboard layout, volume ----------
    RowLayout {
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 12

        // song from the Music player, scrolling while it plays; click = mini player
        Rectangle {
            id: songPill
            readonly property var track: ShellState.musicTrack
            readonly property string label: track ? track.title + (track.artist ? "  ·  " + track.artist : "") : ""
            readonly property int maxText: 220
            readonly property bool scrolls: ShellState.musicPlaying && songText.implicitWidth > maxText
            visible: opacity > 0
            opacity: track ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
            implicitHeight: 24
            implicitWidth: songRow.implicitWidth + 20
            radius: 12
            color: songHover.hovered ? Theme.bg2 : Theme.bg1
            Behavior on color { ColorAnimation { duration: Theme.durFast } }

            Row {
                id: songRow
                anchors.centerIn: parent
                spacing: 8

                // equaliser bars (still while paused)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    height: 12
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: 3; radius: 1.5
                            anchors.bottom: parent.bottom
                            color: Theme.blue
                            height: 4 + index * 2
                            SequentialAnimation on height {
                                running: ShellState.musicPlaying
                                loops: Animation.Infinite
                                NumberAnimation { to: 12; duration: 260 + index * 90; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 3; duration: 300 + index * 70; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }

                // marquee: two copies side by side, slid left by one copy's width
                Item {
                    id: songClip
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(songText.implicitWidth, songPill.maxText)
                    height: songText.implicitHeight
                    clip: true
                    Row {
                        id: marquee
                        spacing: 40
                        Text {
                            id: songText
                            text: songPill.label
                            // not scrolling: fit the pill and end in "…"
                            width: songPill.scrolls ? implicitWidth : songClip.width
                            elide: songPill.scrolls ? Text.ElideNone : Text.ElideRight
                            color: ShellState.musicPlaying ? Theme.fg1 : Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                        }
                        Text {
                            visible: songPill.scrolls
                            text: songPill.label
                            color: songText.color
                            font: songText.font
                        }
                        SequentialAnimation on x {
                            id: slide
                            running: songPill.scrolls && songPill.visible
                            loops: Animation.Infinite
                            PauseAnimation { duration: 1500 }
                            NumberAnimation {
                                from: 0; to: -(songText.implicitWidth + marquee.spacing)
                                duration: (songText.implicitWidth + marquee.spacing) * 28   // ~35 px/s
                            }
                        }
                    }
                    // soft edges while scrolling
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 10; visible: songPill.scrolls
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: songPill.color }
                            GradientStop { position: 1; color: Theme.clear(songPill.color) } }
                    }
                    Rectangle {
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: 10; visible: songPill.scrolls
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.clear(songPill.color) }
                            GradientStop { position: 1; color: songPill.color } }
                    }
                }
            }
            onScrollsChanged: if (!scrolls) marquee.x = 0
            onLabelChanged: { marquee.x = 0; if (slide.running) slide.restart(); }

            HoverHandler { id: songHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ShellState.toggleMusicMini() }
        }

        // minimised windows: left click restores the last one, right click shows them all
        Rectangle {
            id: minPill
            readonly property int count: {
                const list = Hyprland.workspaces.values;
                for (let i = 0; i < list.length; i++)
                    if (list[i].name === "special:minimized") return list[i].toplevels.values.length;
                return 0;
            }
            visible: opacity > 0
            opacity: count > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
            implicitHeight: 24
            implicitWidth: minRow.implicitWidth + 16
            radius: 12
            color: minHover.hovered ? Theme.bg2 : Theme.bg1
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
            Row {
                id: minRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "minimize"
                    color: Theme.blue
                    font { family: Theme.fontIcons; pixelSize: 16 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: minPill.count
                    color: Theme.fg1
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                }
            }
            HoverHandler { id: minHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (pt, button) => {
                    if (button === Qt.RightButton)
                        Hyprland.dispatch('hl.dsp.workspace.toggle_special("minimized")');
                    else
                        Quickshell.execDetached(["hyprctl", "eval", 'require("gnome-like").restore_last()']);
                }
            }
        }

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: trayItem
                required property var modelData
                // apps mark an icon Passive when it should be hidden
                // (e.g. ckb-next's "hide tray icon" setting)
                visible: modelData.status !== Status.Passive
                implicitWidth: 18; implicitHeight: 18
                Image {
                    anchors.fill: parent
                    source: trayItem.modelData.icon
                    sourceSize: Qt.size(36, 36)
                    smooth: true
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (m) => {
                        if (m.button === Qt.LeftButton && !trayItem.modelData.onlyMenu)
                            trayItem.modelData.activate();
                        else if (m.button === Qt.MiddleButton)
                            trayItem.modelData.secondaryActivate();
                        else if (trayItem.modelData.hasMenu) {
                            const p = trayItem.mapToItem(null, 0, trayItem.height + 8);
                            trayMenu.openAt(trayItem.modelData.menu, bar, p.x, p.y);
                        }
                    }
                }
            }
        }

        // screen recording: red pill with the time, click to stop
        Rectangle {
            id: recPill
            visible: Recorder.recording
            implicitWidth: recRow.implicitWidth + 20; implicitHeight: 26
            radius: 13
            color: recHover.hovered ? Qt.lighter(Theme.red, 1.1) : Theme.red
            Row {
                id: recRow
                anchors.centerIn: parent
                spacing: 5
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "stop_circle"; color: Theme.bg0
                    font { family: Theme.fontIcons; pixelSize: 16 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Recorder.clock(Recorder.elapsed); color: Theme.bg0
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                }
            }
            HoverHandler { id: recHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Recorder.stop() }
        }

        // removable drives: only while one is plugged in
        Rectangle {
            id: driveIcon
            visible: Drives.any
            implicitWidth: 28; implicitHeight: 28
            radius: 14
            color: driveHover.hovered || drivesMenu.visible ? Theme.bg2 : Theme.clear(Theme.bg2)
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
            Text {
                anchors.centerIn: parent
                text: "usb"
                color: Theme.fg1
                font { family: Theme.fontIcons; pixelSize: 18 }
            }
            HoverHandler { id: driveHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    if (drivesMenu.visible) { drivesMenu.close(); return; }
                    const p = driveIcon.mapToItem(null, driveIcon.width / 2 - 150, driveIcon.height + 8);
                    drivesMenu.openAt(bar, Math.min(p.x, bar.width - 306), p.y);
                }
            }
        }

        // network: left click menu, right click Settings → Network
        Rectangle {
            id: netIcon
            implicitWidth: 28; implicitHeight: 28
            radius: 14
            color: netHover.hovered || netMenu.visible ? Theme.bg2 : Theme.clear(Theme.bg2)
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
            Text {
                anchors.centerIn: parent
                text: Net.icon
                color: !Net.connected && !Net.connecting ? Theme.bg3
                     : Net.connectivity !== "full" && Net.connected ? Theme.orange : Theme.fg1
                font { family: Theme.fontIcons; pixelSize: 18 }
                SequentialAnimation on opacity {
                    running: Net.connecting
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.opacity = 1
                    NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                }
            }
            HoverHandler { id: netHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (pt, button) => {
                    if (button === Qt.RightButton) { netMenu.close(); ShellState.openSettingsPage(5); return; }
                    if (netMenu.visible) { netMenu.close(); return; }
                    const p = netIcon.mapToItem(null, netIcon.width / 2 - 150, netIcon.height + 8);
                    netMenu.openAt(bar, Math.min(p.x, bar.width - 306), p.y);
                }
            }
        }

        // keyboard layout (Alt+Shift switches): left click menu, right click Settings → Keyboard
        Rectangle {
            id: kb
            property string layout: "us"
            implicitWidth: kbText.implicitWidth + 16; implicitHeight: 28
            radius: 14
            color: kbHover.hovered || layoutMenu.visible ? Theme.bg2 : Theme.clear(Theme.bg2)
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
            Text {
                id: kbText
                anchors.centerIn: parent
                text: kb.layout.toUpperCase()
                color: Theme.fg1
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
            }
            HoverHandler { id: kbHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (pt, button) => {
                    if (button === Qt.RightButton) { layoutMenu.close(); ShellState.openSettingsPage(7); return; }
                    if (layoutMenu.visible) { layoutMenu.close(); return; }
                    const p = kb.mapToItem(null, kb.width / 2 - 130, kb.height + 8);
                    layoutMenu.openAt(bar, Math.min(p.x, bar.width - 266), p.y);
                }
            }
            Connections {
                target: Hyprland
                function onRawEvent(ev) {
                    if (ev.name !== "activelayout") return;
                    const name = ev.data.split(",").pop().toLowerCase();
                    kb.layout = name.startsWith("greek") ? "gr" : (name.startsWith("english") ? "us" : name.slice(0, 2));
                }
            }
        }

        // battery (laptops only): click opens quick settings
        Rectangle {
            id: bat
            visible: Hardware.hasBattery
            implicitWidth: batRow.implicitWidth + 20; implicitHeight: 28
            radius: 14
            color: batHover.hovered || ShellState.quickSettingsOpen ? Theme.bg2 : Theme.clear(Theme.bg2)
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
            readonly property color tint: Hardware.charging ? Theme.green : Hardware.low ? Theme.red : Theme.fg1
            Row {
                id: batRow
                anchors.centerIn: parent
                spacing: 3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Hardware.batteryIcon
                    rotation: 90       // Material battery glyphs stand upright; lie them down like GNOME's
                    color: bat.tint
                    font { family: Theme.fontIcons; pixelSize: 18 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Hardware.percent + "%"
                    color: bat.tint
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                }
            }
            HoverHandler { id: batHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ShellState.toggleQuickSettings() }
        }

        // volume
        Rectangle {
            id: vol
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property real level: sink && sink.audio ? sink.audio.volume : 0
            readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
            implicitWidth: volRow.implicitWidth + 20; implicitHeight: 28
            radius: 14
            color: volArea.containsMouse || ShellState.quickSettingsOpen ? Theme.bg2 : Theme.clear(Theme.bg2)
            Behavior on color { ColorAnimation { duration: Theme.durFast } }

            PwObjectTracker { objects: [ vol.sink ] }

            Row {
                id: volRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: vol.muted || vol.level === 0 ? "volume_off" : (vol.level < 0.4 ? "volume_down" : "volume_up")
                    color: vol.muted ? Theme.bg3 : Theme.fg1
                    font { family: Theme.fontIcons; pixelSize: 18 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(vol.level * 100) + "%"
                    color: vol.muted ? Theme.bg3 : Theme.fg1
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                }
            }
            MouseArea {
                id: volArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                // left click: quick settings, middle click: mute, wheel: volume
                onClicked: (m) => {
                    if (m.button === Qt.MiddleButton) { if (vol.sink && vol.sink.audio) vol.sink.audio.muted = !vol.sink.audio.muted; }
                    else ShellState.toggleQuickSettings();
                }
                onWheel: (w) => {
                    if (!vol.sink || !vol.sink.audio) return;
                    const v = vol.sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05);
                    vol.sink.audio.volume = Math.max(0, Math.min(1, v));
                }
            }
        }

        // power menu
        Rectangle {
            implicitWidth: 28; implicitHeight: 28
            radius: 14
            color: powerHover.hovered ? Theme.bg2 : Theme.clear(Theme.bg2)
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
            Text {
                anchors.centerIn: parent
                text: "power_settings_new"
                color: powerHover.hovered ? Theme.yellow : Theme.fg1
                font { family: Theme.fontIcons; pixelSize: 18 }
            }
            HoverHandler { id: powerHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ShellState.togglePowerMenu() }
        }
    }
}
