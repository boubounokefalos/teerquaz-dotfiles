import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → Power & idle: when to lock, turn the screen off and suspend,
// lock before sleep, what the power button does. Used by Lock.qml (idle
// monitors, sleep + power-key inhibitors) and PowerMenu.button().
ColumnLayout {
    id: page
    spacing: 14

    readonly property var times: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
    function label(m) {
        if (m === 0) return "Never";
        if (m < 60) return m + (m === 1 ? " minute" : " minutes");
        const h = m / 60;
        return (h === 1 ? "1 hour" : (Number.isInteger(h) ? h : h.toFixed(1)) + " hours");
    }
    function minutes(l) { return times.find(m => label(m) === l) || 0; }
    // keep a hand-edited value in the list too
    function choices(cur) { return (times.indexOf(cur) >= 0 ? times : times.concat([cur]).sort((a, b) => a - b)).map(label); }

    // apps holding an idle inhibitor right now (Hyprland's inhibitingIdle)
    property var blockers: []
    function load() { inhib.running = true; }
    Process {
        id: inhib
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const names = [];
                    for (const c of JSON.parse(text))
                        if (c.inhibitingIdle) {
                            const n = c.class.split(".").pop();
                            const pretty = n.charAt(0).toUpperCase() + n.slice(1);
                            if (names.indexOf(pretty) < 0) names.push(pretty);
                        }
                    page.blockers = names;
                } catch (e) {}
            }
        }
    }
    Timer { interval: 3000; repeat: true; running: page.visible; triggeredOnStart: true; onTriggered: page.load() }

    readonly property var buttonActions: [
        { label: "Show the power menu", value: "menu" },
        { label: "Suspend",             value: "suspend" },
        { label: "Lock the screen",     value: "lock" },
        { label: "Shut down",           value: "poweroff" },
        { label: "Do nothing",          value: "nothing" }
    ]

    SectionTitle { text: "When idle" }

    SettingRow {
        label: "Lock the screen after"
        Dropdown {
            model: page.choices(Config.lockAfter); current: page.label(Config.lockAfter)
            onPicked: (l) => Config.lockAfter = page.minutes(l)
        }
    }
    SettingRow {
        label: "Turn the screen off after"
        Dropdown {
            model: page.choices(Config.screenOffAfter); current: page.label(Config.screenOffAfter)
            onPicked: (l) => Config.screenOffAfter = page.minutes(l)
        }
    }
    SettingRow {
        label: "Suspend after"; hint: "Sleep to save power; any key or the mouse wakes the PC"
        Dropdown {
            model: page.choices(Config.suspendAfter); current: page.label(Config.suspendAfter)
            onPicked: (l) => Config.suspendAfter = page.minutes(l)
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Playing video or games (and the Keep Awake tile in Quick Settings) pause these timers."
            + (ShellState.keepAwake ? "\nPaused now: Keep Awake is on." : "")
            + (page.blockers.length ? "\nPaused now by: " + page.blockers.join(", ") + "." : "")
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 12 }
    }

    SectionTitle { text: "Sleep and power button"; Layout.topMargin: 14 }

    SettingRow {
        label: "Lock before sleep"; hint: "Also when something else suspends the PC (sleep key, other apps)"
        Toggle { checked: Config.lockOnSuspend; onToggled: (v) => Config.lockOnSuspend = v }
    }
    SettingRow {
        label: "Power button"
        Dropdown {
            model: page.buttonActions.map(a => a.label)
            current: (page.buttonActions.find(a => a.value === Config.powerButton) || page.buttonActions[0]).label
            onPicked: (l) => Config.powerButton = (page.buttonActions.find(a => a.label === l) || page.buttonActions[0]).value
        }
    }
}
