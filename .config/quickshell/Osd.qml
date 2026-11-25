import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Io

// On-screen display near the bottom of the screen for volume, mute,
// microphone mute, output device, screen brightness and keyboard layout changes.
// Doesn't take clicks. Quiet while quick settings has its own sliders open.
PanelWindow {
    id: osd
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { bottom: true }
    margins { bottom: 90 }
    implicitWidth: 360
    implicitHeight: 72
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-osd"
    mask: Region {}                                        // click-through
    BackgroundEffect.blurRegion: Region { item: blurArea; radius: 28 }
    visible: shown || fade.running

    property bool shown: false
    property string icon: "volume_up"
    property string label: ""
    property real value: -1          // 0..1 shows a bar, -1 hides it
    property bool dim: false         // muted look
    property bool ready: false       // ignore the burst of changes at startup

    function show(icon, label, value, dim) {
        if (!ready) return;
        osd.icon = icon; osd.label = label; osd.value = value; osd.dim = dim;
        shown = true;
        hideTimer.restart();
    }

    Timer { interval: 1500; running: true; onTriggered: osd.ready = true }

    // messages from Hyprland's Lua config etc.:  qs ipc call osd message <icon> <text>
    IpcHandler {
        target: "osd"
        function message(icon: string, text: string): void { osd.show(icon, text, -1, false); }
    }
    Timer { id: hideTimer; interval: 1400; onTriggered: osd.shown = false }

    // ---------- sources ----------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [osd.sink, osd.source] }

    function showVolume() {
        const a = sink && sink.audio;
        if (!a) return;
        const v = a.volume;
        show(a.muted || v === 0 ? "volume_off" : v < 0.4 ? "volume_down" : "volume_up",
             a.muted ? "Muted" : Math.round(v * 100) + "%", Math.min(1, v), a.muted);
    }

    // Feedback click at the new volume (like GNOME). Rate-limited so holding
    // the volume key or dragging a slider doesn't machine-gun it.
    property real lastClick: 0
    function click() {
        if (!ready || !Config.volumeSound) return;
        const a = sink && sink.audio;
        if (!a || a.muted || a.volume === 0) return;
        const now = Date.now();
        if (now - lastClick < 110) return;
        lastClick = now;
        Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"]);
    }

    Connections {
        target: osd.sink ? osd.sink.audio : null
        ignoreUnknownSignals: true
        function onVolumeChanged() { osd.click(); if (!ShellState.quickSettingsOpen) osd.showVolume(); }
        function onMutedChanged()  { osd.click(); if (!ShellState.quickSettingsOpen) osd.showVolume(); }
    }
    Connections {
        target: osd.source ? osd.source.audio : null
        ignoreUnknownSignals: true
        function onMutedChanged() {
            if (ShellState.quickSettingsOpen) return;
            const m = osd.source.audio.muted;
            osd.show(m ? "mic_off" : "mic", m ? "Microphone off" : "Microphone on", -1, m);
        }
    }
    Connections {
        target: Hardware
        function onBrightnessKey() {
            if (ShellState.quickSettingsOpen) return;
            const b = Hardware.brightness;
            osd.show(b < 0.34 ? "brightness_low" : b < 0.67 ? "brightness_medium" : "brightness_high",
                     Math.round(b * 100) + "%", b, false);
        }
    }
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            const s = Pipewire.defaultAudioSink;
            if (s) osd.show("speaker", s.description || s.nickname || s.name, -1, false);
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name !== "activelayout") return;
            const name = ev.data.split(",").pop();
            osd.show("keyboard", name, -1, false);
        }
    }

    // ---------- look ----------
    Item {
        id: blurArea
        anchors.centerIn: parent
        width: card.width; height: card.height
        opacity: 0
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: osd.value >= 0 ? 340 : Math.min(340, row.implicitWidth + 44)
        height: 56
        radius: 28
        color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.85)
        border.width: 1
        border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)
        Behavior on width { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }

        opacity: osd.shown ? 1 : 0
        scale: osd.shown ? 1 : 0.9
        transform: Translate { y: osd.shown ? 0 : 16; Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEmph } } }
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.durMed; easing.type: Theme.easeOut } }
        Behavior on scale   { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.OutBack } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 14
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: osd.icon
                color: osd.dim ? Theme.red : Theme.yellow
                font { family: Theme.fontIcons; pixelSize: 24 }
            }
            Item {
                visible: osd.value >= 0
                anchors.verticalCenter: parent.verticalCenter
                width: 200; height: 8
                Rectangle { anchors.fill: parent; radius: 4; color: Theme.bg2 }
                Rectangle {
                    height: parent.height; radius: 4
                    width: Math.max(8, parent.width * Math.max(0, osd.value))
                    color: osd.dim ? Theme.bg3 : Theme.yellowDim
                    Behavior on width { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: osd.value >= 0 ? 52 : Math.min(implicitWidth, 270)
                horizontalAlignment: osd.value >= 0 ? Text.AlignRight : Text.AlignLeft
                text: osd.label
                elide: Text.ElideRight
                color: osd.dim ? Theme.fg4 : Theme.fg1
                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
            }
        }
    }
}
