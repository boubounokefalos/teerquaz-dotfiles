import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings → Notifications: Do Not Disturb, how long popups stay, history,
// and a rule per app (show popups / history only / off). Rules are applied
// in Notifs.qml as notifications arrive.
ColumnLayout {
    id: page
    spacing: 14

    readonly property var ruleNames: [
        { label: "Show popups",  value: "" },
        { label: "History only", value: "silent" },
        { label: "Off",          value: "off" }
    ]
    function ruleLabel(app) {
        const v = Config.notifRules[app] || "";
        return (ruleNames.find(r => r.value === v) || ruleNames[0]).label;
    }
    function setRule(app, label) {
        const r = ruleNames.find(x => x.label === label) || ruleNames[0];
        const rules = Object.assign({}, Config.notifRules);
        if (r.value) rules[app] = r.value; else delete rules[app];
        Config.notifRules = rules;
    }
    function forget(app) {
        const rules = Object.assign({}, Config.notifRules);
        delete rules[app];
        Config.notifRules = rules;
        Config.notifApps = Config.notifApps.filter(a => a !== app);
    }
    function iconFor(app) {
        const n = Notifs.history.find(x => x.appName === app);
        if (n) return Notifs.iconFor(n);
        return Quickshell.iconPath(app.toLowerCase().replace(/\s+/g, "-"), true);
    }

    SectionTitle { text: "Notifications" }

    SettingRow {
        label: "Do Not Disturb"; hint: "No popups; notifications still go to the history. Urgent ones always show."
        Toggle { checked: ShellState.doNotDisturb; onToggled: (x) => ShellState.doNotDisturb = x }
    }
    SettingRow {
        label: "Popups stay for"; hint: "When the app doesn't ask for a time itself"
        Stepper {
            value: Config.notifTimeout; min: 2; max: 30; step: 1; suffix: " s"; textWidth: 50
            onChanged: (x) => Config.notifTimeout = x
        }
    }
    SettingRow {
        label: "History"
        hint: Notifs.count === 0 ? "Empty" : Notifs.count + (Notifs.count === 1 ? " notification" : " notifications") + " · click the clock in the bar to see them"
        PillButton {
            text: "Clear"
            opacity: Notifs.count > 0 ? 1 : 0.4
            onClicked: Notifs.clearAll()
        }
    }
    SettingRow {
        label: "Try it"
        PillButton {
            text: "Send a test notification"
            onClicked: Quickshell.execDetached(["notify-send", "-a", "Settings", "-i", "preferences-system", "Test notification", "This is how notifications look."])
        }
    }

    SectionTitle { text: "Apps"; Layout.topMargin: 14 }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: Config.notifApps.length === 0
        text: "Apps show up here after they send their first notification."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }

    Rectangle {
        visible: Config.notifApps.length > 0
        Layout.fillWidth: true
        implicitHeight: apps.implicitHeight + 12
        radius: Theme.radius
        color: Theme.bg1

        Column {
            id: apps
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            Repeater {
                model: Config.notifApps
                delegate: Rectangle {
                    id: row
                    required property string modelData
                    width: apps.width; height: 56
                    radius: Theme.radiusItem
                    color: rh.hovered ? Theme.bg2 : Theme.clear(Theme.bg2)
                    HoverHandler { id: rh }

                    Image {
                        id: ic
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        sourceSize: Qt.size(56, 56)
                        source: page.iconFor(row.modelData)
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: ic
                        visible: !ic.visible
                        text: "notifications"
                        color: Theme.fg4
                        font { family: Theme.fontIcons; pixelSize: 22 }
                    }
                    Text {
                        anchors { left: ic.right; leftMargin: 12; right: dd.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: row.modelData
                        elide: Text.ElideRight
                        color: Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                    }
                    Dropdown {
                        id: dd
                        anchors { right: del.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        implicitWidth: 200
                        model: page.ruleNames.map(r => r.label)
                        current: page.ruleLabel(row.modelData)
                        onPicked: (l) => page.setRule(row.modelData, l)
                    }
                    RoundIcon {
                        id: del
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        size: 36
                        icon: "close"
                        onClicked: page.forget(row.modelData)
                    }
                }
            }
        }
    }
}
