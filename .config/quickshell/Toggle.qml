import QtQuick

// Flat on/off switch.
Rectangle {
    id: t
    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 52; implicitHeight: 30
    radius: height / 2
    color: checked ? Theme.blueDim : Theme.bg2
    Behavior on color { ColorAnimation { duration: Theme.durMed } }

    Rectangle {
        width: 22; height: 22; radius: 11
        anchors.verticalCenter: parent.verticalCenter
        x: t.checked ? t.width - width - 4 : 4
        color: t.checked ? Theme.textOnBlue : Theme.fg4
        Behavior on x { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
        Behavior on color { ColorAnimation { duration: Theme.durMed } }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    MouseArea { anchors.fill: parent; onClicked: t.toggled(!t.checked) }
}
