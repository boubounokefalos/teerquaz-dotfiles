import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings → Sound: one app stream row (icon, name, volume).
Rectangle {
    id: row
    property var helpers: null   // SoundPage (devName, volIcon, …)
    property var node: null
    property bool input: false
    readonly property var a: node ? node.audio : null
    readonly property string iconSrc: node ? row.helpers.appIcon(node) : ""
    readonly property string media: node && node.properties ? (node.properties["media.name"] || "") : ""

    Layout.fillWidth: true
    implicitHeight: 64
    radius: Theme.radius
    color: Theme.bg1

    Image {
        id: appImg
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        width: 32; height: 32
        sourceSize: Qt.size(64, 64)
        source: row.iconSrc
        visible: status === Image.Ready
    }
    Text {
        anchors.centerIn: appImg
        visible: !appImg.visible
        text: row.input ? "mic" : "music_note"
        color: Theme.fg4
        font { family: Theme.fontIcons; pixelSize: 24 }
    }
    Column {
        id: names
        anchors { left: appImg.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: Math.min(220, row.width * 0.3)
        Text {
            width: parent.width; elide: Text.ElideRight
            text: row.node ? row.helpers.appName(row.node) : ""
            color: Theme.fg1
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
        }
        Text {
            visible: text.length > 0
            width: parent.width; elide: Text.ElideRight
            text: row.media
            color: Theme.fg4
            font { family: Theme.fontUi; pixelSize: 12 }
        }
    }
    QsSlider {
        anchors { left: names.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        value: row.a ? row.a.volume : 0
        muted: row.a ? row.a.muted : false
        icon: row.helpers.volIcon(row.a, row.input)
        onMoved: (v) => { if (row.a) { row.a.volume = v; if (row.a.muted && v > 0) row.a.muted = false; } }
        onIconClicked: if (row.a) row.a.muted = !row.a.muted
    }
}
