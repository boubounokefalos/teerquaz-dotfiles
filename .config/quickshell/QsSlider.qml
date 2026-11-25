import QtQuick

// Flat slider: icon button (mute) + track + percentage.
Item {
    id: root
    property real value: 0              // 0..1
    property string icon: "volume_up"
    property bool muted: false
    signal moved(real value)
    signal iconClicked()

    implicitHeight: 40

    Rectangle {
        id: iconBtn
        width: 40; height: 40; radius: 20
        color: iconHover.hovered ? Theme.bg2 : (root.muted ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.18) : "transparent")
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.muted ? Theme.red : Theme.fg1
            font { family: Theme.fontIcons; pixelSize: 22 }
        }
        HoverHandler { id: iconHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.iconClicked() }
    }

    Item {
        id: track
        anchors { left: iconBtn.right; leftMargin: 10; right: label.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        height: 22

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 8; radius: 4
            color: Theme.bg2
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(8, parent.width * Math.min(1, root.value)); height: 8; radius: 4
            color: root.muted ? Theme.bg3 : Theme.yellowDim
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
        }
        Rectangle {
            id: knob
            x: parent.width * Math.min(1, root.value) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: drag.pressed || knobHover.hovered ? 20 : 16
            height: width; radius: width / 2
            color: Theme.fg0
            Behavior on width { NumberAnimation { duration: Theme.durFast } }
            Behavior on x { enabled: !drag.pressed; NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
        }
        HoverHandler { id: knobHover; cursorShape: Qt.PointingHandCursor }

        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -6
            function set(mx) { root.moved(Math.max(0, Math.min(1, (mx - 6) / track.width))); }
            onPressed: (m) => set(m.x)
            onPositionChanged: (m) => { if (pressed) set(m.x); }
            onWheel: (w) => root.moved(Math.max(0, Math.min(1, root.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    Text {
        id: label
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 40
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.value * 100) + "%"
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
    }
}
