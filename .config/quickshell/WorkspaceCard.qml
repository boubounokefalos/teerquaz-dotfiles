import QtQuick
import QtQuick.Effects

// Mini-map of one workspace in the overview strip. Accepts dropped windows.
Item {
    id: card
    required property int wsId
    required property var windows       // [{ real: {x,y,w,h}, cls, top }] in screen coordinates, most recent first
    required property size screenSize
    property bool active: false
    signal clicked()

    readonly property bool hovering: hover.hovered || drop.containsDrag
    width: 192; height: 108
    scale: hovering ? 1.06 : 1
    Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Easing.OutBack } }

    Image {
        id: wp
        anchors.fill: parent
        source: Theme.wallpaper
        sourceSize: Qt.size(384, 216)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    Rectangle { id: mask; anchors.fill: parent; radius: 12; visible: false; layer.enabled: true }
    MultiEffect { anchors.fill: parent; source: wp; maskEnabled: true; maskSource: mask; brightness: -0.15 }

    // windows as small live previews; the list is most-recent first, so
    // earlier entries are stacked on top like on screen
    // own layer (so their z order stays below the border and label), clipped
    // to the card's rounded shape
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: mask }
        Repeater {
            model: card.windows
            delegate: CardWindow {
                required property var modelData
                required property int index
                win: modelData
                sx: card.width / card.screenSize.width
                sy: card.height / card.screenSize.height
                z: card.windows.length - index
            }
        }
    }

    Rectangle {
        anchors.fill: parent; radius: 12
        color: drop.containsDrag ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.18) : "transparent"
        border.width: card.active ? 3 : (card.hovering ? 2 : 1)
        border.color: card.active || drop.containsDrag ? Theme.yellow : (card.hovering ? Theme.fg4 : Theme.bg2)
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }

    Text {
        anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
        text: card.windows.length ? card.wsId : card.wsId + "  ·  empty"
        color: Theme.fg0
        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.4)
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.ExtraBold }
    }

    // Drag.target is this DropArea, so it carries the workspace number itself
    DropArea { id: drop; anchors.fill: parent; keys: ["window"]; property int wsId: card.wsId }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    // WithinBounds grabs the press, so the overview's click-to-close
    // background underneath never sees it
    TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: card.clicked() }
}
