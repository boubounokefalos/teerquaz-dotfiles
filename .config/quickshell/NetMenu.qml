import QtQuick
import Quickshell

// Menu under the bar's network icon: current connection, traffic, quick
// connect/disconnect, other profiles / Wi-Fi networks, link to Settings.
// Same panel look as TrayMenu.
DropMenu {
    id: pop
    implicitWidth: 300
    cardHeight: col.implicitHeight + 12

    function openAt(win, x, y) {
        place(win, x);
        Net.refresh();
        show();
    }
    function close() { hide(); }

    onVisibleChanged: Net.rateUsers += visible ? 1 : -1

    // other profiles of the primary device's kind, to switch to
    readonly property var others: {
        const p = Net.primary;
        if (!p || p.type !== "ethernet") return [];
        return Net.profiles.filter(c => c.type === "802-3-ethernet" && !c.active);
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.82)
        border.width: 1
        border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)

        Column {
            id: col
            x: 6; y: 6
            width: pop.width - 12

            // header: icon, connection, status
            Item {
                width: parent.width; height: 64
                Rectangle {
                    id: badge
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 40; height: 40; radius: 20
                    color: Net.connected ? Theme.blueDim : Theme.bg2
                    Text {
                        anchors.centerIn: parent
                        text: Net.icon
                        color: Net.connected ? Theme.textOnBlue : Theme.fg4
                        font { family: Theme.fontIcons; pixelSize: 22 }
                    }
                }
                Column {
                    anchors { left: badge.right; leftMargin: 12; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: Net.title
                        color: Theme.fg0
                        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: Net.statusText + (Net.connected && Net.details.speed ? "  ·  " + Net.details.speed : "")
                        color: Net.connected && Net.connectivity !== "full" ? Theme.orange : Theme.fg4
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                    }
                }
            }

            // address + live traffic
            Rectangle {
                visible: Net.connected
                x: 6; width: parent.width - 12; height: 58; radius: Theme.radius
                color: Theme.bg1
                Column {
                    anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Text {
                        text: (Net.details.ip4 && Net.details.ip4.length ? Net.details.ip4[0] : "No IPv4 address")
                        color: Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                    }
                    Row {
                        spacing: 16
                        Row {
                            spacing: 3
                            Text { text: "arrow_downward"; color: Theme.blue; font { family: Theme.fontIcons; pixelSize: 15 } }
                            Text { text: Net.rate(Net.rxRate); color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                        }
                        Row {
                            spacing: 3
                            Text { text: "arrow_upward"; color: Theme.yellow; font { family: Theme.fontIcons; pixelSize: 15 } }
                            Text { text: Net.rate(Net.txRate); color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                        }
                    }
                }
            }

            Item { width: 1; height: 6 }
            Rectangle { x: 8; width: parent.width - 16; height: 1; color: Theme.bg2 }
            Item { width: 1; height: 6 }

            TrayMenuRow {
                visible: Net.primary !== null && Net.networking
                label: Net.connected || Net.connecting ? "Disconnect" : "Connect"
                iconName: Net.connected || Net.connecting ? "link_off" : "link"
                onActivated: {
                    if (Net.connected || Net.connecting) Net.disconnectDevice(Net.primary.name);
                    else Net.connectDevice(Net.primary.name);
                    pop.close();
                }
            }
            Repeater {
                model: pop.others
                delegate: TrayMenuRow {
                    required property var modelData
                    label: "Switch to " + modelData.name
                    iconName: "swap_horiz"
                    onActivated: { Net.up(modelData.uuid); pop.close(); }
                }
            }
            // Wi-Fi networks (only on machines with a Wi-Fi card)
            Repeater {
                model: Net.hasWifi && Net.wifiEnabled ? Net.wifiList.slice(0, 6) : []
                delegate: TrayMenuRow {
                    required property var modelData
                    label: modelData.ssid
                    iconName: modelData.inUse ? "check" : (modelData.security ? "lock" : "wifi")
                    onActivated: {
                        // networks needing a password are joined from Settings
                        const known = Net.profiles.some(p => p.name === modelData.ssid);
                        if (modelData.inUse) {}
                        else if (known || !modelData.security) Net.connectWifi(modelData.ssid, "");
                        else ShellState.openSettingsPage(5);
                        pop.close();
                    }
                }
            }
            TrayMenuRow {
                visible: !Net.networking
                label: "Turn networking on"
                iconName: "power_settings_new"
                onActivated: { Net.setNetworking(true); pop.close(); }
            }
            TrayMenuRow {
                label: "Network settings"
                iconName: "settings"
                onActivated: { ShellState.openSettingsPage(5); pop.close(); }
            }
        }
    }
}
