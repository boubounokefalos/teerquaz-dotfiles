pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Night light: warmer screen colours through hyprsunset.
// Config.nightLight: "off" | "on" | "schedule" (Config.nightFrom → nightTo,
// "HH:MM", may pass midnight). Config.nightTemp: Kelvin (lower = warmer).
// The shell runs hyprsunset only while the light should be on.
Singleton {
    id: root

    property bool available: false
    readonly property bool active: available && (Config.nightLight === "on"
        || (Config.nightLight === "schedule" && inWindow))
    property bool inWindow: false

    function minutes(s) { const m = /^(\d+):(\d+)$/.exec(s || ""); return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : 0; }
    function check() {
        const d = new Date(), now = d.getHours() * 60 + d.getMinutes();
        const a = minutes(Config.nightFrom), b = minutes(Config.nightTo);
        inWindow = a <= b ? (now >= a && now < b) : (now >= a || now < b);
    }
    // quick on/off from Quick Settings: the schedule stays when it is in use
    function toggle() {
        if (Config.nightLight === "schedule") Config.nightLight = active ? "off" : "on";
        else Config.nightLight = Config.nightLight === "on" ? "off" : "on";
    }

    Timer { interval: 30000; repeat: true; running: Config.nightLight === "schedule"; triggeredOnStart: true; onTriggered: root.check() }
    Connections {
        target: Config
        function onNightFromChanged() { root.check(); }
        function onNightToChanged() { root.check(); }
    }

    Timer { interval: 30000; repeat: true; running: !root.available; triggeredOnStart: true; onTriggered: checkAgain.running = true }

    Process {
        id: sunset
        running: root.active
        command: ["hyprsunset", "-t", String(Config.nightTemp)]
    }
    // change the warmth while it is on (hyprsunset's IPC through hyprctl)
    Connections {
        target: Config
        function onNightTempChanged() {
            if (sunset.running) tempLater.restart();
        }
    }
    Timer {
        id: tempLater; interval: 150
        onTriggered: Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(Config.nightTemp)])
    }

    //   qs ipc call nightlight toggle
    IpcHandler {
        target: "nightlight"
        function toggle(): void { root.toggle(); }
        function recheck(): void { checkAgain.running = true; }
    }
    Process {
        id: checkAgain
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: (code) => root.available = code === 0
    }
}
