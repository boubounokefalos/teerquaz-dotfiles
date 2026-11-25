import QtQuick
import Quickshell
import Quickshell.Widgets

// One line of the shell-drawn tray menu (TrayMenu.qml).
Rectangle {
    id: r
    property var entry: null
    property string label: entry ? entry.text.replace(/_(?=[^_])/, "") : ""
    property string iconName: ""
    readonly property bool on: entry && entry.enabled === false ? false : true
    signal activated()

    width: parent ? parent.width : 200
    height: 32
    radius: 10
    color: h.hovered && r.on ? Theme.yellowDim : Theme.clear(Theme.yellowDim)
    readonly property color fg: !r.on ? Theme.bg3 : (h.hovered ? Theme.bg0 : Theme.fg1)

    Row {
        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 10

        // checkbox / radio state, a Material icon, or the app's own icon
        Item {
            width: 18; height: 18
            anchors.verticalCenter: parent.verticalCenter
            visible: r.iconName !== "" || (r.entry && (r.entry.buttonType !== QsMenuButtonType.None || r.entry.icon !== ""))
            Text {
                anchors.centerIn: parent
                visible: r.iconName !== "" || (r.entry && r.entry.buttonType !== QsMenuButtonType.None)
                text: r.iconName !== "" ? r.iconName
                    : !r.entry ? ""
                    : r.entry.buttonType === QsMenuButtonType.CheckBox
                        ? (r.entry.checkState === Qt.Checked ? "check_box" : "check_box_outline_blank")
                        : (r.entry.checkState === Qt.Checked ? "radio_button_checked" : "radio_button_unchecked")
                color: r.fg
                font { family: Theme.fontIcons; pixelSize: 18 }
            }
            IconImage {
                anchors.fill: parent
                visible: r.iconName === "" && r.entry && r.entry.buttonType === QsMenuButtonType.None && r.entry.icon !== ""
                source: r.entry ? r.entry.icon : ""
                asynchronous: true
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 60
            text: r.label
            elide: Text.ElideRight
            color: r.fg
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
        }
    }
    Text {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        visible: r.entry !== null && r.entry.hasChildren
        text: "chevron_right"
        color: r.fg
        font { family: Theme.fontIcons; pixelSize: 18 }
    }

    HoverHandler { id: h; cursorShape: r.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
    MouseArea { anchors.fill: parent; enabled: r.on; onClicked: r.activated() }
}
