import QtQuick

Rectangle {
    id: sb
    property string icon: ""
    property int delta: 0
    property var stepper: null
    width: 40; height: 40; radius: 12
    opacity: enabled ? 1 : 0.4
    color: sbh.hovered && enabled ? Theme.bg2 : Theme.bg1
    Text { anchors.centerIn: parent; text: sb.icon; color: Theme.fg1; font { family: Theme.fontIcons; pixelSize: 18 } }
    HoverHandler { id: sbh; cursorShape: sb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        onTapped: {
            const s = sb.stepper;
            const v = Math.round((s.value + sb.delta * s.step) * 1000) / 1000;
            s.changed(Math.max(s.min, Math.min(s.max, v)));
        }
    }
}
