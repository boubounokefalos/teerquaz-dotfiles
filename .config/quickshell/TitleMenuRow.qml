import QtQuick

// A row of TitleMenu.qml, drawn like a GTK menu item from
// ~/.config/gtk-3.0/menus.css: 38 px (min-height 30 + 4 px padding), radius
// 10, Nunito 11pt regular, text 38 px in (44 from the menu edge, like GTK's
// icon/check column), hover = yellowDim pill + bg0 text.
Rectangle {
    id: r
    property string label: ""
    signal activated()

    width: parent ? parent.width : 200
    height: 38
    radius: 10
    implicitWidth: label_.implicitWidth + 38 + 32
    color: h.hovered ? Theme.yellowDim : Theme.clear(Theme.yellowDim)

    Text {
        id: label_
        anchors { left: parent.left; leftMargin: 38; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: r.label
        elide: Text.ElideRight
        color: h.hovered ? Theme.bg0 : Theme.fg1
        font { family: "Nunito"; pointSize: 11 }
    }

    HoverHandler { id: h }
    MouseArea { anchors.fill: parent; onClicked: r.activated() }
}
