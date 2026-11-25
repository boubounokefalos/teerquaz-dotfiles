import QtQuick

// Small round icon button (calendar arrows, …).
Rectangle {
    id: b
    property string icon: ""
    property int size: 32
    signal clicked()

    width: size; height: size; radius: size / 2
    color: h.hovered ? Theme.bg2 : Theme.clear(Theme.bg2)
    scale: t.pressed ? 0.92 : 1
    opacity: enabled ? 1 : 0.35
    Behavior on color { ColorAnimation { duration: Theme.durFast } }
    Behavior on scale { NumberAnimation { duration: Theme.durFast } }

    Text {
        anchors.centerIn: parent
        text: b.icon
        color: Theme.fg1
        font { family: Theme.fontIcons; pixelSize: 22 }
    }
    HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: t; gesturePolicy: TapHandler.WithinBounds; onTapped: b.clicked() }
}
