import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings → Sound: one output/input device card (Use, volume, live level).
Rectangle {
    id: card
    property var helpers: null   // SoundPage (devName, volIcon, …)
    property var node: null
    property bool input: false
    property bool isDefault: false
    property string icon: "speaker"
    property real level: -1            // 0..1 live level, -1 = none
    signal pick()
    readonly property var a: node ? node.audio : null

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 24
    radius: Theme.radius
    color: Theme.bg1
    border.width: isDefault ? 2 : 0
    border.color: Theme.yellowDim

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14; rightMargin: 14 }
        spacing: 6

        Item {
            width: parent.width; height: 34
            Text {
                id: ic
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: card.icon
                color: card.isDefault ? Theme.yellow : Theme.fg4
                font { family: Theme.fontIcons; pixelSize: 22 }
            }
            Text {
                anchors { left: ic.right; leftMargin: 12; right: pick.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: card.helpers.devName(card.node)
                elide: Text.ElideRight
                color: Theme.fg1
                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
            }
            Rectangle {
                id: pick
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                height: 30; radius: 15
                width: pickText.implicitWidth + 28
                color: card.isDefault ? Theme.yellowDim : (ph.hovered ? Theme.bg3 : Theme.bg2)
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                Text {
                    id: pickText
                    anchors.centerIn: parent
                    text: card.isDefault ? "In use" : "Use"
                    color: card.isDefault ? Theme.bg0 : Theme.fg1
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                }
                HoverHandler { id: ph; cursorShape: card.isDefault ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler { onTapped: if (!card.isDefault) card.pick() }
            }
        }

        QsSlider {
            width: parent.width
            value: card.a ? card.a.volume : 0
            muted: card.a ? card.a.muted : false
            icon: card.helpers.volIcon(card.a, card.input)
            onMoved: (v) => { if (card.a) { card.a.volume = v; if (card.a.muted && v > 0) card.a.muted = false; } }
            onIconClicked: if (card.a) card.a.muted = !card.a.muted
        }

        // live input level
        Item {
            visible: card.level >= 0
            width: parent.width; height: 18
            Rectangle {
                anchors { left: parent.left; leftMargin: 50; right: parent.right; rightMargin: 50; verticalCenter: parent.verticalCenter }
                height: 6; radius: 3
                color: Theme.bg2
                Rectangle {
                    height: parent.height; radius: 3
                    width: Math.max(0, parent.width * Math.min(1, card.level))
                    color: card.a && card.a.muted ? Theme.bg3 : Theme.blue
                    Behavior on width { NumberAnimation { duration: 80 } }
                }
            }
        }
    }
}
