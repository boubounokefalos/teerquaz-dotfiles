import QtQuick
import Quickshell
import Quickshell.Wayland

// Notification popups, dropping down under the clock (where the date menu
// opens). Hidden while the date menu is open: the list is there anyway.
PanelWindow {
    id: win
    visible: (Notifs.popups.count > 0 || list.removing) && !ShellState.datePanelOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true }        // top only: centred horizontally, under the clock
    margins { top: Theme.barHeight + 8 }
    implicitWidth: 420
    implicitHeight: Math.max(1, list.contentHeight + 20)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-notifications"

    ListView {
        id: list
        property bool removing: false
        anchors { fill: parent; leftMargin: 10; rightMargin: 10; bottomMargin: 20 }
        interactive: false
        spacing: 10
        model: Notifs.popups

        delegate: NotifCard {
            required property int nid
            width: ListView.view.width
            notif: Notifs.find(nid)
            popup: true
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "y"; from: -60; duration: Theme.durSlow; easing.type: Theme.easeEmph }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durMed }
            }
        }
        remove: Transition {
            SequentialAnimation {
                ScriptAction { script: list.removing = true }
                ParallelAnimation {
                    NumberAnimation { property: "scale"; to: 0.94; duration: Theme.durMed; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: Theme.durMed }
                }
                ScriptAction { script: list.removing = false }
            }
        }
        // items pushed down while their own slide-in is still running must
        // finish it too, or they get stuck half-way (overlapping cards)
        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.durMed; easing.type: Theme.easeOut }
            NumberAnimation { property: "scale"; to: 1; duration: Theme.durMed }
            NumberAnimation { property: "opacity"; to: 1; duration: Theme.durMed }
        }
    }
}
