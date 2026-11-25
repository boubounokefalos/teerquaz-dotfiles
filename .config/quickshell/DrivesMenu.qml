import QtQuick
import Quickshell

// Menu under the bar's drive icon: every plugged-in drive with Open + Eject.
// Same panel look as TrayMenu / NetMenu.
DropMenu {
    id: pop
    implicitWidth: 300
    cardHeight: col.implicitHeight + 12

    function openAt(win, x, y) {
        place(win, x);
        Drives.refresh();
        show();
    }
    function close() { hide(); }

    // close by itself when the last drive goes away
    Connections {
        target: Drives
        function onAnyChanged() { if (!Drives.any) pop.close(); }
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

            Repeater {
                model: Drives.drives
                delegate: Item {
                    id: d
                    required property var modelData
                    width: col.width; height: 58

                    Rectangle {
                        id: badge
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        width: 40; height: 40; radius: 20
                        color: d.modelData.mountpoint ? Theme.blueDim : Theme.bg2
                        Text {
                            anchors.centerIn: parent
                            text: "usb"
                            color: d.modelData.mountpoint ? Theme.textOnBlue : Theme.fg4
                            font { family: Theme.fontIcons; pixelSize: 22 }
                        }
                    }
                    Column {
                        anchors { left: badge.right; leftMargin: 12; right: btns.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: d.modelData.name
                            color: Theme.fg0
                            font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: d.modelData.size + " · " + d.modelData.fstype + (d.modelData.mountpoint ? "" : " · not mounted")
                            color: Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                        }
                    }
                    Row {
                        id: btns
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        RoundIcon { size: 34; icon: "folder_open"; onClicked: { Drives.open(d.modelData); pop.close(); } }
                        RoundIcon { size: 34; icon: "eject"; onClicked: { Drives.eject(d.modelData); pop.close(); } }
                    }
                }
            }

            Item { width: 1; height: 6 }
            Rectangle { x: 8; width: parent.width - 16; height: 1; color: Theme.bg2 }
            Item { width: 1; height: 6 }

            TrayMenuRow {
                label: "Eject all"
                iconName: "eject"
                onActivated: { Drives.ejectAll(); pop.close(); }
            }
            TrayMenuRow {
                label: "Open Files"
                iconName: "folder"
                onActivated: { Quickshell.execDetached(["thunar"]); pop.close(); }
            }
        }
    }
}
