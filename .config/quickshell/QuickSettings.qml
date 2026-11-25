import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Bluetooth

// GNOME-style quick settings, dropping down under the bar on the right.
//   qs ipc call quicksettings toggle
PanelWindow {
    id: qs
    required property var lock

    property bool open: false
    // card offset: 0 open, fully hidden under the bar closed
    property real drop: open ? 0 : -(card.height + 10)
    Behavior on drop { NumberAnimation { duration: qs.open ? Theme.durSlow : Theme.durMed; easing.type: qs.open ? Theme.easeEmph : Theme.easeOut } }
    onOpenChanged: ShellState.quickSettingsOpen = open
    property bool showOutputs: false
    property bool showBt: false
    readonly property var bt: Bluetooth.defaultAdapter

    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-panel-qs"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // Blur follows a static copy of the card's final geometry: a Region tied to
    // the animated card itself gets stuck at its start-of-animation position.
    BackgroundEffect.blurRegion: Region { item: blurArea; radius: card.radius }

    function show() { showOutputs = false; showBt = false; tileFile.reload(); visible = true; open = true; keys.forceActiveFocus(); }
    function hide() { open = false; hideTimer.restart(); if (bt && bt.discovering) bt.discovering = false; }
    function toggle() { open ? hide() : show(); }
    function run(cmd) { hide(); Quickshell.execDetached(["sh", "-c", cmd]); }

    Timer { id: hideTimer; interval: Theme.durMed; onTriggered: if (!qs.open) qs.visible = false }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { qs.toggle(); }
    }
    Connections {
        target: ShellState
        function onToggleQuickSettings() { qs.toggle(); }
        function onDatePanelOpenChanged() { if (ShellState.datePanelOpen && qs.open) qs.hide(); }
    }

    // ---------- data ----------
    // tile mode per workspace, written by ~/.config/hypr/gnome-like.lua
    readonly property int activeWs: Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace ? Hyprland.focusedMonitor.activeWorkspace.id : 1
    property var tiledWs: []
    FileView {
        id: tileFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hypr/tiled-workspaces.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { qs.tiledWs = JSON.parse(text()).tiled || []; } catch (e) { qs.tiledWs = []; } }
        onLoadFailed: qs.tiledWs = []
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: [qs.sink, qs.source].concat(qs.sinks) }

    readonly property var player: {
        const ps = Mpris.players.values;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length ? ps[0] : null;
    }
    Timer {   // MPRIS position is not pushed; poll while visible and playing
        interval: 1000; repeat: true
        running: qs.open && qs.player !== null && qs.player.isPlaying
        onTriggered: qs.player.positionChanged()
    }


    // ---------- click outside closes ----------
    MouseArea { anchors.fill: parent; onClicked: qs.hide() }

    // ---------- the card ----------
    // clipped at the bar's bottom edge: the card slides out from under the bar
    Item {
        id: dropClip
        anchors { fill: parent; topMargin: Theme.barHeight }
        clip: true

        Item {
            id: blurArea
            // visible part of the card only, so no empty blur shows while it slides
            anchors.right: card.right
            width: card.width
            y: Math.max(0, card.y + qs.drop)
            height: Math.max(0, card.y + qs.drop + card.height - y)
            opacity: 0   // stays in the scene so the Region can track it
        }
        Rectangle {
            id: card
            anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
            width: 420
            height: body.implicitHeight + 36
            radius: Theme.radiusPanel
            color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.82)
            border.width: 1
            border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)
            clip: true

            opacity: qs.open ? 1 : 0
            transform: Translate { y: qs.drop }
            Behavior on opacity { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
            Behavior on height  { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }

            MouseArea { anchors.fill: parent }   // swallow clicks so they don't close the panel

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: qs.hide()

                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                    spacing: 14

                    // ---- header: user + round buttons ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item {
                            implicitWidth: 40; implicitHeight: 40
                            Image {
                                id: av
                                anchors.fill: parent
                                source: "file:///var/lib/AccountsService/icons/" + Quickshell.env("USER")
                                sourceSize: Qt.size(80, 80)
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                            }
                            Rectangle { id: avMask; anchors.fill: parent; radius: 20; visible: false; layer.enabled: true }
                            MultiEffect { anchors.fill: parent; source: av; maskEnabled: true; maskSource: avMask }
                        }
                        Column {
                            Layout.fillWidth: true
                            Text {
                                text: Quickshell.env("USER")
                                color: Theme.fg1
                                font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                            }
                            Text {   // laptops: battery instead of uptime
                                visible: Hardware.hasBattery
                                text: Hardware.percent + "%  ·  " + Hardware.batteryText
                                color: Hardware.charging ? Theme.green : Hardware.low ? Theme.red : Theme.fg4
                                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                            }
                            Text {
                                id: uptimeText
                                visible: !Hardware.hasBattery
                                color: Theme.fg4
                                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                                FileView { id: uptimeFile; path: "/proc/uptime" }
                                Timer {
                                    interval: 30000; repeat: true; triggeredOnStart: true
                                    running: qs.open
                                    onTriggered: {
                                        uptimeFile.reload();
                                        const s = parseFloat(uptimeFile.text());
                                        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
                                        uptimeText.text = "up " + (h > 0 ? h + " h " : "") + m + " min";
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: [
                                { icon: "screenshot_region", tip: "Screenshot", act: () => qs.run('sleep 0.4; ~/.config/quickshell/scripts/screenshot.sh area < /dev/null') },
                                { icon: "settings",          tip: "Settings",   act: () => { qs.hide(); ShellState.openSettings(); } },
                                { icon: "lock",              tip: "Lock",       act: () => { qs.hide(); qs.lock.lock(); } },
                                { icon: "power_settings_new",tip: "Power",      act: () => { qs.hide(); ShellState.togglePowerMenu(); } }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: 40; implicitHeight: 40; radius: 20
                                color: hb.hovered ? Theme.bg2 : Theme.bg1
                                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    color: hb.hovered ? Theme.yellow : Theme.fg1
                                    font { family: Theme.fontIcons; pixelSize: 20 }
                                }
                                HoverHandler { id: hb; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: modelData.act() }
                            }
                        }
                    }

                    // ---- volume ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        QsSlider {
                            Layout.fillWidth: true
                            readonly property var a: qs.sink && qs.sink.audio ? qs.sink.audio : null
                            value: a ? a.volume : 0
                            muted: a ? a.muted : false
                            icon: muted || value === 0 ? "volume_off" : (value < 0.4 ? "volume_down" : "volume_up")
                            onMoved: (v) => { if (a) { a.volume = v; if (v > 0) a.muted = false; } }
                            onIconClicked: if (a) a.muted = !a.muted
                        }
                        Rectangle {   // output picker toggle
                            implicitWidth: 32; implicitHeight: 32; radius: 16
                            color: ob.hovered || qs.showOutputs ? Theme.bg2 : Theme.clear(Theme.bg2)
                            Text {
                                anchors.centerIn: parent
                                text: "chevron_right"
                                rotation: qs.showOutputs ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
                                color: Theme.fg1
                                font { family: Theme.fontIcons; pixelSize: 20 }
                            }
                            HoverHandler { id: ob; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: qs.showOutputs = !qs.showOutputs }
                        }
                    }

                    // ---- output devices ----
                    Column {
                        Layout.fillWidth: true
                        visible: qs.showOutputs
                        spacing: 4
                        Repeater {
                            model: qs.sinks
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool current: qs.sink && modelData.id === qs.sink.id
                                width: parent.width; height: 38; radius: 12
                                color: dh.hovered ? Theme.bg2 : Theme.bg1
                                Text {
                                    id: chk
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: current ? "check_circle" : "radio_button_unchecked"
                                    color: current ? Theme.yellow : Theme.fg4
                                    font { family: Theme.fontIcons; pixelSize: 18 }
                                }
                                Text {
                                    anchors { left: chk.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: modelData.description || modelData.nickname || modelData.name
                                    elide: Text.ElideRight
                                    color: Theme.fg1
                                    font { family: Theme.fontUi; pixelSize: 13; weight: current ? Font.Bold : Font.DemiBold }
                                }
                                HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Pipewire.preferredDefaultAudioSink = modelData }
                            }
                        }
                    }

                    // ---- microphone ----
                    QsSlider {
                        Layout.fillWidth: true
                        visible: qs.source !== null
                        readonly property var a: qs.source && qs.source.audio ? qs.source.audio : null
                        value: a ? a.volume : 0
                        muted: a ? a.muted : false
                        icon: muted ? "mic_off" : "mic"
                        onMoved: (v) => { if (a) { a.volume = v; if (v > 0) a.muted = false; } }
                        onIconClicked: if (a) a.muted = !a.muted
                    }

                    // ---- screen brightness (laptops) ----
                    QsSlider {
                        Layout.fillWidth: true
                        visible: Hardware.hasBacklight
                        value: Hardware.brightness
                        icon: value < 0.34 ? "brightness_low" : value < 0.67 ? "brightness_medium" : "brightness_high"
                        onMoved: (v) => Hardware.setBrightness(v)
                    }

                    // ---- tiles ----
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 10

                        QsTile {
                            Layout.fillWidth: true
                            icon: Net.icon
                            title: Net.isWifi ? "Wi-Fi" : "Wired"
                            subtitle: Net.statusText
                            active: Net.connected
                            onClicked: { ShellState.toggleQuickSettings(); ShellState.openSettingsPage(5); }
                        }
                        QsTile {
                            Layout.fillWidth: true
                            visible: qs.bt !== null
                            readonly property var connectedDevs: qs.bt ? qs.bt.devices.values.filter(d => d.connected) : []
                            icon: !qs.bt || !qs.bt.enabled ? "bluetooth_disabled" : connectedDevs.length ? "bluetooth_connected" : "bluetooth"
                            title: "Bluetooth"
                            subtitle: !qs.bt || qs.bt.state === BluetoothAdapterState.Blocked ? "Blocked"
                                    : !qs.bt.enabled ? "Off"
                                    : connectedDevs.length === 1 ? connectedDevs[0].name
                                    : connectedDevs.length > 1 ? connectedDevs.length + " devices" : "On"
                            active: qs.bt !== null && qs.bt.enabled
                            menu: true
                            menuOpen: qs.showBt
                            onClicked: if (qs.bt) qs.bt.enabled = !qs.bt.enabled
                            onMenuClicked: { qs.showBt = !qs.showBt; if (qs.showBt && qs.bt && !qs.bt.enabled) qs.bt.enabled = true; }
                        }
                        QsTile {
                            Layout.fillWidth: true
                            visible: Hardware.powerProfilesAvailable
                            icon: Hardware.profileIcons[PowerProfiles.profile] || "balance"
                            title: "Power Mode"
                            subtitle: Hardware.profileNames[PowerProfiles.profile] || ""
                            active: PowerProfiles.profile !== PowerProfile.Balanced
                            onClicked: Hardware.nextProfile()
                        }
                        QsTile {
                            Layout.fillWidth: true
                            icon: ShellState.doNotDisturb ? "notifications_off" : "notifications"
                            title: "Do Not Disturb"
                            subtitle: ShellState.doNotDisturb ? "On" : "Off"
                            active: ShellState.doNotDisturb
                            onClicked: {
                                ShellState.doNotDisturb = !ShellState.doNotDisturb;
                            }
                        }
                        QsTile {
                            Layout.fillWidth: true
                            icon: "coffee"
                            title: "Keep Awake"
                            subtitle: ShellState.keepAwake ? "Screen stays on" : "Off"
                            active: ShellState.keepAwake
                            onClicked: ShellState.keepAwake = !ShellState.keepAwake
                        }
                        QsTile {
                            Layout.fillWidth: true
                            icon: Recorder.recording ? "stop_circle" : "screen_record"
                            title: "Screen Record"
                            subtitle: Recorder.recording ? Recorder.clock(Recorder.elapsed) : "Ctrl+Print"
                            active: Recorder.recording
                            onClicked: { ShellState.toggleQuickSettings(); recStart.restart(); }
                            // let the panel close first so it isn't in the video
                            Timer { id: recStart; interval: 350; onTriggered: Recorder.toggle() }
                        }
                        QsTile {
                            Layout.fillWidth: true
                            visible: NightLight.available
                            icon: NightLight.active ? "nightlight" : "light_mode"
                            title: "Night Light"
                            subtitle: NightLight.active ? Config.nightTemp + " K" : (Config.nightLight === "schedule" ? "From " + Config.nightFrom : "Off")
                            active: NightLight.active
                            onClicked: NightLight.toggle()
                        }
                        QsTile {
                            Layout.fillWidth: true
                            icon: "dashboard"
                            title: "Tile Workspace"
                            subtitle: active ? "Tiling (Super+T)" : "Floating (Super+T)"
                            active: qs.tiledWs.indexOf(qs.activeWs) >= 0
                            onClicked: Quickshell.execDetached(["hyprctl", "eval", 'require("gnome-like").toggle_workspace_tiling()'])
                        }
                    }

                    // ---- Bluetooth devices (tile chevron) ----
                    Column {
                        Layout.fillWidth: true
                        visible: qs.showBt && qs.bt !== null
                        spacing: 4
                        readonly property var devs: {
                            if (!qs.bt) return [];
                            const all = qs.bt.devices.values.filter(d => d.paired || d.connected || (qs.bt.discovering && d.deviceName.length));
                            const rank = d => d.connected ? 0 : d.paired ? 1 : 2;
                            return all.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
                        }
                        Text {
                            visible: parent.devs.length === 0
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: 4; bottomPadding: 4
                            text: qs.bt && qs.bt.enabled ? (qs.bt.discovering ? "Searching…" : "No paired devices") : "Bluetooth is off"
                            color: Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                        }
                        Repeater {
                            model: parent.devs
                            delegate: Rectangle {
                                id: devRow
                                required property var modelData
                                readonly property bool busy: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting
                                                             || modelData.state === BluetoothDeviceState.Disconnecting
                                width: parent.width; height: 44; radius: 12
                                color: devHover.hovered ? Theme.bg2 : Theme.bg1
                                Text {
                                    id: devIcon
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: {
                                        const i = devRow.modelData.icon || "";
                                        return i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0 ? "headphones"
                                             : i.indexOf("audio") >= 0 ? "speaker" : i.indexOf("mouse") >= 0 ? "mouse"
                                             : i.indexOf("keyboard") >= 0 ? "keyboard" : i.indexOf("phone") >= 0 ? "smartphone"
                                             : i.indexOf("computer") >= 0 ? "computer" : i.indexOf("gaming") >= 0 ? "sports_esports" : "bluetooth";
                                    }
                                    color: devRow.modelData.connected ? Theme.yellow : Theme.fg4
                                    font { family: Theme.fontIcons; pixelSize: 20 }
                                }
                                Column {
                                    anchors { left: devIcon.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: devRow.modelData.name || devRow.modelData.address
                                        color: Theme.fg1
                                        font { family: Theme.fontUi; pixelSize: 13; weight: devRow.modelData.connected ? Font.Bold : Font.DemiBold }
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: devRow.modelData.pairing ? "Pairing…"
                                            : devRow.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…"
                                            : devRow.modelData.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                                            : devRow.modelData.connected ? "Connected" + (devRow.modelData.batteryAvailable ? "  ·  " + Math.round(devRow.modelData.battery * 100) + "%" : "")
                                            : devRow.modelData.paired ? "Not connected" : "Click to pair"
                                        color: Theme.fg4
                                        font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                                    }
                                }
                                HoverHandler { id: devHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        const d = devRow.modelData;
                                        if (devRow.busy) return;
                                        if (d.connected) d.disconnect();
                                        else if (d.paired) d.connect();
                                        else { d.trusted = true; d.pair(); }
                                    }
                                }
                                // a fresh pairing connects right away
                                Connections {
                                    target: devRow.modelData
                                    function onPairedChanged() { if (devRow.modelData.paired && !devRow.modelData.connected) devRow.modelData.connect(); }
                                }
                            }
                        }
                        Rectangle {   // search for new devices
                            visible: qs.bt !== null && qs.bt.enabled
                            width: parent.width; height: 38; radius: 12
                            color: scanHover.hovered ? Theme.bg2 : Theme.clear(Theme.bg2)
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qs.bt && qs.bt.discovering ? "stop_circle" : "bluetooth_searching"
                                    color: Theme.fg1
                                    font { family: Theme.fontIcons; pixelSize: 18 }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qs.bt && qs.bt.discovering ? "Stop searching" : "Search for devices"
                                    color: Theme.fg1
                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                                }
                            }
                            HoverHandler { id: scanHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    if (!qs.bt) return;
                                    if (!qs.bt.discovering) qs.bt.pairable = true;   // BlueZ refuses new pairings otherwise
                                    qs.bt.discovering = !qs.bt.discovering;
                                }
                            }
                        }
                    }

                    // ---- media ----
                    Rectangle {
                        Layout.fillWidth: true
                        visible: qs.player !== null
                        implicitHeight: 92
                        radius: Theme.radius
                        color: Theme.bg1
                        clip: true

                        Image {
                            id: art
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 12 }
                            width: height
                            source: qs.player ? qs.player.trackArtUrl : ""
                            sourceSize: Qt.size(136, 136)
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                        }
                        Rectangle { id: artMask; anchors.fill: art; radius: 12; visible: false; layer.enabled: true }
                        MultiEffect {
                            anchors.fill: art; source: art; maskEnabled: true; maskSource: artMask
                            visible: art.status === Image.Ready
                        }
                        Rectangle {
                            anchors.fill: art; radius: 12; color: Theme.bg2
                            visible: art.status !== Image.Ready
                            Text { anchors.centerIn: parent; text: "music_note"; color: Theme.fg4; font { family: Theme.fontIcons; pixelSize: 30 } }
                        }

                        Column {
                            anchors { left: art.right; leftMargin: 12; right: controls.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: qs.player ? (qs.player.trackTitle || qs.player.identity) : ""
                                color: Theme.fg1
                                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: qs.player ? (qs.player.trackArtist || qs.player.identity) : ""
                                color: Theme.fg4
                                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                            }
                            Rectangle {   // progress
                                width: parent.width; height: 4; radius: 2
                                color: Theme.bg2
                                visible: qs.player !== null && qs.player.lengthSupported && qs.player.length > 0
                                Rectangle {
                                    height: parent.height; radius: 2
                                    color: Theme.yellowDim
                                    width: qs.player && qs.player.length > 0 ? parent.width * Math.min(1, qs.player.position / qs.player.length) : 0
                                    Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                                }
                            }
                        }

                        Row {
                            id: controls
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Repeater {
                                model: [
                                    { icon: "skip_previous", act: () => qs.player.previous(), ok: () => qs.player && qs.player.canGoPrevious },
                                    { icon: qs.player && qs.player.isPlaying ? "pause" : "play_arrow", act: () => qs.player.togglePlaying(), ok: () => qs.player && qs.player.canTogglePlaying, big: true },
                                    { icon: "skip_next", act: () => qs.player.next(), ok: () => qs.player && qs.player.canGoNext }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: modelData.big ? 40 : 32; height: width; radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.big ? Theme.blueDim : (mh.hovered ? Theme.bg2 : Theme.clear(Theme.bg2))
                                    opacity: modelData.ok() ? 1 : 0.4
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        color: modelData.big ? Theme.textOnBlue : Theme.fg1
                                        font { family: Theme.fontIcons; pixelSize: modelData.big ? 24 : 20 }
                                    }
                                    HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: if (modelData.ok()) modelData.act() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
