import QtQuick

// Plain slider for a number between `from` and `to` (no mute icon).
// valueText: label on the right (defaults to the value).
Item {
    id: root
    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0.05
    property real mark: NaN                 // optional tick (e.g. the default)
    property string valueText: String(Math.round(value * 100) / 100)
    signal moved(real value)

    implicitWidth: 320
    implicitHeight: 40
    readonly property real frac: (Math.min(to, Math.max(from, value)) - from) / (to - from)

    Item {
        id: track
        anchors { left: parent.left; leftMargin: 8; right: label.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
        height: 22
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 8; radius: 4; color: Theme.bg2 }
        Rectangle {
            visible: !isNaN(root.mark)
            x: track.width * (root.mark - root.from) / (root.to - root.from) - 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2; height: 16; radius: 1; color: Theme.bg3
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(8, parent.width * root.frac); height: 8; radius: 4
            color: Theme.yellowDim
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
        }
        Rectangle {
            x: parent.width * root.frac - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: drag.pressed || kh.hovered ? 20 : 16
            height: width; radius: width / 2
            color: Theme.fg0
            Behavior on width { NumberAnimation { duration: Theme.durFast } }
            Behavior on x { enabled: !drag.pressed; NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
        }
        HoverHandler { id: kh; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -6
            function snap(v) { return Math.max(root.from, Math.min(root.to, Math.round(v / root.step) * root.step)); }
            function set(mx) { root.moved(snap(root.from + Math.max(0, Math.min(1, (mx - 6) / track.width)) * (root.to - root.from))); }
            onPressed: (m) => set(m.x)
            onPositionChanged: (m) => { if (pressed) set(m.x); }
            onWheel: (w) => root.moved(snap(root.value + (w.angleDelta.y > 0 ? root.step : -root.step)))
        }
    }
    Text {
        id: label
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 48
        horizontalAlignment: Text.AlignRight
        text: root.valueText
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
    }
}
