import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Settings → Sound: output and input devices (pick default, volume, mute),
// a live microphone level, per-app volume, apps using the microphone.
ColumnLayout {
    id: page
    spacing: 14

    property bool shown: false

    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks:   nodes.filter(n => n.audio && !n.isStream && n.type === PwNodeType.AudioSink).sort((x, y) => devName(x).localeCompare(devName(y)))
    readonly property var sources: nodes.filter(n => n.audio && !n.isStream && n.type === PwNodeType.AudioSource).sort((x, y) => devName(x).localeCompare(devName(y)))
    readonly property var playing:   nodes.filter(n => n.audio && n.isStream && n.type === PwNodeType.AudioOutStream)
    // (the level meter below is itself a capture stream: leave it out)
    readonly property var recording: nodes.filter(n => n.audio && n.isStream && n.type === PwNodeType.AudioInStream
                                                       && !/quickshell/i.test(n.name + " " + appName(n)))
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker { objects: page.shown ? page.sinks.concat(page.sources, page.playing, page.recording) : [] }

    // live level of the default microphone, only while the page is visible
    PwNodePeakMonitor {
        id: micPeak
        node: page.source
        enabled: page.shown && !!page.source
    }

    function devName(n) { return n ? (n.description || n.nickname || n.name).replace(/\s+/g, " ") : ""; }
    function devIcon(n, input) {
        const s = ((n.name || "") + " " + (n.description || "")).toLowerCase();
        if (input) return /headset|usb/.test(s) ? "headset_mic" : "mic";
        if (/hdmi|displayport|\bdp\b/.test(s)) return "tv";
        if (/headset|headphone|usb|bluez/.test(s)) return "headphones";
        return "speaker";
    }
    function volIcon(a, input) {
        if (!a) return input ? "mic" : "volume_up";
        if (input) return a.muted ? "mic_off" : "mic";
        if (a.muted || a.volume <= 0) return "volume_off";
        return a.volume < 0.34 ? "volume_mute" : a.volume < 0.67 ? "volume_down" : "volume_up";
    }
    function appName(n) {
        const p = n.properties || {};
        return p["application.name"] || n.description || n.name || "App";
    }
    function appIcon(n) {
        const p = n.properties || {};
        const name = p["application.icon-name"] || p["application.process.binary"] || "";
        return name ? Quickshell.iconPath(name.toLowerCase(), true) : "";
    }

    // ===== Output =====
    SectionTitle { text: "Output" }

    Repeater {
        model: page.sinks
        delegate: SoundDevice {
            helpers: page
            required property var modelData
            node: modelData
            isDefault: page.sink && modelData.id === page.sink.id
            icon: page.devIcon(modelData, false)
            onPick: Pipewire.preferredDefaultAudioSink = modelData
        }
    }
    Text {
        visible: page.sinks.length === 0
        text: "No output devices."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }

    // ===== Input =====
    SectionTitle { text: "Input"; Layout.topMargin: 14 }

    Repeater {
        model: page.sources
        delegate: SoundDevice {
            helpers: page
            required property var modelData
            node: modelData
            input: true
            isDefault: page.source && modelData.id === page.source.id
            icon: page.devIcon(modelData, true)
            level: isDefault ? micPeak.peak : -1
            onPick: Pipewire.preferredDefaultAudioSource = modelData
        }
    }
    Text {
        visible: page.sources.length === 0
        text: "No microphones."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }

    // ===== Apps =====
    SectionTitle { text: "Apps"; Layout.topMargin: 14 }

    Repeater {
        model: page.playing
        delegate: SoundApp {
            helpers: page
            required property var modelData
            node: modelData
        }
    }
    Text {
        visible: page.playing.length === 0
        text: "No apps are playing sound."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }

    Text {
        visible: page.recording.length > 0
        Layout.topMargin: 6
        text: "Using the microphone"
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
    }
    Repeater {
        model: page.recording
        delegate: SoundApp {
            helpers: page
            required property var modelData
            node: modelData
            input: true
        }
    }

    // ===== Options =====
    SectionTitle { text: "Options"; Layout.topMargin: 14 }

    SettingRow {
        label: "Volume change sound"; hint: "A short click at the new level when the volume changes"
        Toggle { checked: Config.volumeSound; onToggled: (v) => Config.volumeSound = v }
    }
}
