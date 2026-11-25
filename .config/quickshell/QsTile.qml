import QtQuick

// GNOME-style toggle pill: icon, title, subtitle; with `menu`, a chevron on the
// right opens a list (menuClicked) while the rest of the pill toggles (clicked).
Rectangle {
    id: tile
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool menu: false
    property bool menuOpen: false
    signal clicked()
    signal menuClicked()

    implicitHeight: 58
    radius: 29
    color: active ? Theme.blueDim : (hover.hovered ? Theme.bg2 : Theme.bg1)
    scale: tap.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
    Behavior on scale { NumberAnimation { duration: Theme.durFast } }

    Text {
        id: ic
        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
        text: tile.icon
        color: tile.active ? Theme.textOnBlue : Theme.fg1
        font { family: Theme.fontIcons; pixelSize: 22 }
    }
    Column {
        anchors { left: ic.right; leftMargin: 12; right: tile.menu ? sep.left : parent.right; rightMargin: tile.menu ? 8 : 14; verticalCenter: parent.verticalCenter }
        spacing: 0
        Text {
            width: parent.width
            text: tile.title
            elide: Text.ElideRight
            color: tile.active ? Theme.textOnBlue : Theme.fg1
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
        }
        Text {
            width: parent.width
            visible: tile.subtitle.length > 0
            text: tile.subtitle
            elide: Text.ElideRight
            color: tile.active ? Qt.rgba(Theme.textOnBlue.r, Theme.textOnBlue.g, Theme.textOnBlue.b, 0.8) : Theme.fg4
            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
        }
    }

    // menu part: thin divider + chevron
    Rectangle {
        id: sep
        visible: tile.menu
        anchors { right: chev.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
        width: 1; height: 26
        color: tile.active ? Qt.rgba(Theme.textOnBlue.r, Theme.textOnBlue.g, Theme.textOnBlue.b, 0.3) : Theme.bg3
    }
    Text {
        id: chev
        visible: tile.menu
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        text: "chevron_right"
        rotation: tile.menuOpen ? 90 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
        color: tile.active ? Theme.textOnBlue : Theme.fg1
        font { family: Theme.fontIcons; pixelSize: 20 }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        onTapped: (pt) => {
            if (tile.menu && pt.position.x >= sep.x - 4) tile.menuClicked();
            else tile.clicked();
        }
    }
}
