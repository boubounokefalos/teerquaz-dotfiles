pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Laptop hardware: battery, screen brightness, power profiles.
// Everything here switches itself off on machines without the hardware
// (a desktop has no battery or backlight), so the UI that uses it stays hidden.
//   qs ipc call brightness up|down
Singleton {
    id: root

    // ---------- battery (UPower's combined "display device": all packs together) ----------
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.ready && battery.isLaptopBattery && battery.isPresent
    readonly property bool onBattery: UPower.onBattery
    readonly property int percent: hasBattery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging
                                                    || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: hasBattery && battery.state === UPowerDeviceState.FullyCharged
    readonly property bool low: hasBattery && !charging && onBattery && percent <= 15
    readonly property string batteryIcon: {
        if (!hasBattery) return "battery_unknown";
        if (charging) return "battery_charging_full";
        if (!onBattery && (full || percent >= 95)) return "battery_full";
        if (percent <= 10) return "battery_alert";
        const bars = ["battery_0_bar", "battery_1_bar", "battery_2_bar", "battery_3_bar",
                      "battery_4_bar", "battery_5_bar", "battery_6_bar", "battery_full"];
        return bars[Math.min(7, Math.floor(percent / 12.5))];
    }
    function duration(sec) {
        if (!(sec > 0)) return "";
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }
    // "1 h 20 min left", "40 min until full", "Fully charged", "Plugged in"
    readonly property string batteryText: {
        if (!hasBattery) return "";
        if (charging) { const d = duration(battery.timeToFull); return d ? d + " until full" : "Charging"; }
        if (!onBattery) return full || percent >= 95 ? "Fully charged" : "Plugged in, not charging";
        const d = duration(battery.timeToEmpty);
        return d ? d + " left" : "On battery";
    }

    // low-battery warnings, once per level per discharge
    property int warned: 101
    onPercentChanged: checkLow()
    onChargingChanged: if (charging) warned = 101
    onOnBatteryChanged: if (!onBattery) warned = 101
    function checkLow() {
        if (!hasBattery || charging || !onBattery) return;
        for (const lvl of [5, 10, 20]) {
            if (percent <= lvl && warned > lvl) {
                warned = lvl;
                Quickshell.execDetached(["notify-send", "-a", "Battery", "-i", "battery-caution",
                    "-u", lvl <= 10 ? "critical" : "normal",
                    lvl <= 5 ? "Battery almost empty" : "Battery low",
                    percent + "% left" + (duration(battery.timeToEmpty) ? " — about " + duration(battery.timeToEmpty) : "")
                    + (lvl <= 5 ? ". Plug in now: the laptop will hibernate on its own soon." : ". Plug in the charger.")]);
                return;
            }
        }
    }

    // ---------- power profiles (power-profiles-daemon or tlp-pd) ----------
    property bool powerProfilesAvailable: false
    Process {
        running: true
        command: ["gdbus", "introspect", "--system", "--dest", "org.freedesktop.UPower.PowerProfiles",
                  "--object-path", "/org/freedesktop/UPower/PowerProfiles"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (code) => root.powerProfilesAvailable = code === 0
    }
    readonly property var profileNames: ({ [PowerProfile.PowerSaver]: "Power Saver",
                                           [PowerProfile.Balanced]: "Balanced",
                                           [PowerProfile.Performance]: "Performance" })
    readonly property var profileIcons: ({ [PowerProfile.PowerSaver]: "eco",
                                           [PowerProfile.Balanced]: "balance",
                                           [PowerProfile.Performance]: "speed" })
    function nextProfile() {
        const p = PowerProfiles.profile;
        PowerProfiles.profile = p === PowerProfile.Balanced ? PowerProfile.PowerSaver
                              : p === PowerProfile.PowerSaver && PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance
                              : PowerProfile.Balanced;
    }

    // ---------- screen brightness (sysfs backlight, set through brightnessctl/logind) ----------
    property string backlight: ""
    property int maxBrightness: 0
    property int rawBrightness: 0
    readonly property bool hasBacklight: backlight !== "" && maxBrightness > 0
    readonly property real brightness: hasBacklight ? rawBrightness / maxBrightness : 0
    signal brightnessKey()          // OSD listens: only key presses show it, not the slider

    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] && { basename \"$d\"; cat \"$d/max_brightness\"; exit; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                if (l.length < 2) return;
                root.backlight = l[0];
                root.maxBrightness = parseInt(l[1]) || 0;
            }
        }
    }
    FileView {
        id: cur
        path: root.backlight ? "/sys/class/backlight/" + root.backlight + "/brightness" : ""
        onLoaded: if (!root.pending) root.rawBrightness = parseInt(text()) || 0
    }
    // the firmware can change it too (ThinkPad Fn keys); sysfs has no change events
    Timer { interval: 3000; repeat: true; running: root.hasBacklight && !root.pending; onTriggered: cur.reload() }

    // set: 0..1, never fully dark. Writes are throttled while a slider is dragged.
    property bool pending: false
    property int target: 0
    function setBrightness(v) {
        if (!hasBacklight) return;
        target = Math.round(Math.max(0.01, Math.min(1, v)) * maxBrightness);
        rawBrightness = target;
        pending = true;
        if (!writer.running && !writeLater.running) writeLater.start();
    }
    Timer { id: writeLater; interval: 40; onTriggered: { writer.command = ["brightnessctl", "-q", "-d", root.backlight, "set", String(root.target)]; writer.running = true; } }
    Process {
        id: writer
        onExited: {
            if (String(root.target) !== writer.command[5]) writeLater.start();
            else { root.pending = false; cur.reload(); }
        }
    }
    // keys: 5% steps, finer near the bottom where small changes matter
    function step(up) {
        const p = brightness * 100;
        const s = p < 10 || (!up && p <= 10) ? 2 : 5;
        setBrightness((Math.round(p / s) * s + (up ? s : -s)) / 100);
        brightnessKey();
    }

    IpcHandler {
        target: "brightness"
        function up(): void { root.step(true); }
        function down(): void { root.step(false); }
    }
}
