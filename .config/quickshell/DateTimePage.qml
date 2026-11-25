import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → Date & time. Time zone and automatic time go through
// systemd's timedatectl (asks for your password via the polkit agent);
// the clock format is a shell setting.
ColumnLayout {
    id: page
    spacing: 14

    property string timezone: ""
    property bool ntp: true
    property var zones: []

    function load() { info.running = true; if (!zones.length) zoneList.running = true; }

    Process {
        id: info
        command: ["timedatectl", "show", "-p", "Timezone", "-p", "NTP"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const [k, v] = line.split("=");
                    if (k === "Timezone") page.timezone = v;
                    else if (k === "NTP") page.ntp = v === "yes";
                }
            }
        }
    }
    Process {
        id: zoneList
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: page.zones = text.split("\n").filter(z => z) }
    }
    // re-read after a change (the polkit prompt may have been cancelled)
    Process {
        id: setter
        onExited: info.running = true
    }
    function run(args) { setter.command = args; setter.running = true; }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    SectionTitle { text: "Date & time" }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 96
        radius: 16
        color: Theme.bg1
        Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, Config.clock24 ? "HH:mm:ss" : "h:mm:ss AP")
                color: Theme.fg0
                font { family: Theme.fontDisplay; pixelSize: 34; weight: Font.Bold }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, "dddd d MMMM yyyy") + "  ·  " + page.timezone
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
        }
    }

    SettingRow {
        label: "Automatic date & time"; hint: "Synchronise the clock from the internet (NTP)"
        Toggle { checked: page.ntp; onToggled: (v) => { page.ntp = v; page.run(["timedatectl", "set-ntp", v ? "true" : "false"]); } }
    }
    SettingRow {
        label: "Time zone"; hint: "Changing it asks for your password"
        Dropdown {
            model: page.zones
            current: page.timezone
            onPicked: (v) => { page.timezone = v; page.run(["timedatectl", "set-timezone", v]); }
        }
    }
    SettingRow {
        label: "24-hour clock"; hint: "Used by the bar and the lock screen"
        Toggle { checked: Config.clock24; onToggled: (v) => Config.clock24 = v }
    }
}
