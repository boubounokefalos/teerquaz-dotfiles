import QtQuick

// Rounded text button. primary: blue (confirm).
Rectangle {
    id: b
    property string text: ""
    property bool primary: false
    signal clicked()

    implicitWidth: label.implicitWidth + 36
    implicitHeight: 40
    radius: 20
    color: primary ? (h.hovered ? Qt.lighter(Theme.blueDim, 1.15) : Theme.blueDim) : (h.hovered ? Theme.bg3 : Theme.bg2)
    scale: m.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: Theme.durFast } }
    Behavior on scale { NumberAnimation { duration: Theme.durFast } }

    Text {
        id: label
        anchors.centerIn: parent
        text: b.text
        color: b.primary ? Theme.textOnBlue : Theme.fg1
        font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
    }
    HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
    MouseArea { id: m; anchors.fill: parent; onClicked: b.clicked() }
}
