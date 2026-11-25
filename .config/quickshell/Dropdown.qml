import QtQuick
import QtQuick.Controls

// Flat dropdown with a search field. model: array of strings.
// previewFont: render each entry in its own font (for font pickers).
Item {
    id: dd
    property var model: []
    property string current: ""
    property bool previewFont: false
    property bool searchable: model.length > 8
    signal picked(string value)

    implicitWidth: 320
    implicitHeight: 40

    Rectangle {
        id: button
        anchors.fill: parent
        radius: 12
        color: hover.hovered || pop.opened ? Theme.bg2 : Theme.bg1
        border.width: pop.opened ? 2 : 0
        border.color: Theme.yellowDim
        Behavior on color { ColorAnimation { duration: Theme.durFast } }

        Text {
            anchors { left: parent.left; leftMargin: 14; right: arrow.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: dd.current || "—"
            elide: Text.ElideRight
            color: Theme.fg1
            font.family: dd.previewFont && dd.current ? dd.current : Theme.fontUi
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Text {
            id: arrow
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: "expand_more"
            rotation: pop.opened ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
            color: Theme.fg4
            font { family: Theme.fontIcons; pixelSize: 20 }
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pop.opened ? pop.close() : pop.open() }
    }

    Popup {
        id: pop
        y: dd.height + 6
        width: dd.width
        height: Math.min(380, (dd.searchable ? 52 : 0) + list.contentHeight + 16)
        padding: 8
        focus: true
        onOpened: { search.text = ""; if (dd.searchable) search.forceActiveFocus(); list.positionViewAtIndex(Math.max(0, filtered.indexOf(dd.current)), ListView.Center); }

        readonly property var filtered: {
            const q = search.text.toLowerCase();
            return q ? dd.model.filter(m => m.toLowerCase().indexOf(q) >= 0) : dd.model;
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durFast }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.durMed; easing.type: Theme.easeEmph }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.durFast } }

        background: Rectangle {
            radius: Theme.radiusPanel
            color: Theme.bg0s
            border.width: 1
            border.color: Theme.bg2
        }

        contentItem: Column {
            spacing: 8
            Rectangle {
                visible: dd.searchable
                width: parent.width; height: 40; radius: 10
                color: Theme.bg1
                Text {
                    id: searchIcon
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "search"; color: Theme.fg4
                    font { family: Theme.fontIcons; pixelSize: 18 }
                }
                TextInput {
                    id: search
                    anchors { left: searchIcon.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.fg1
                    selectionColor: Theme.yellowDim
                    font { family: Theme.fontUi; pixelSize: 14 }
                    clip: true
                    Keys.onEscapePressed: pop.close()
                    Keys.onReturnPressed: if (pop.filtered.length) { dd.picked(pop.filtered[0]); pop.close(); }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search…"; color: Theme.bg3
                        font: search.font
                    }
                }
            }
            ListView {
                id: list
                width: parent.width
                height: pop.height - pop.topPadding - pop.bottomPadding - (dd.searchable ? 48 : 0)
                clip: true
                model: pop.filtered
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                delegate: Rectangle {
                    required property string modelData
                    width: ListView.view.width
                    height: 36
                    radius: Theme.radiusItem
                    color: modelData === dd.current ? Qt.rgba(Theme.yellowDim.r, Theme.yellowDim.g, Theme.yellowDim.b, 0.25)
                         : rowHover.hovered ? Theme.bg2 : Theme.clear(Theme.bg2)
                    Text {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: modelData
                        elide: Text.ElideRight
                        color: modelData === dd.current ? Theme.yellow : Theme.fg1
                        font.family: dd.previewFont ? modelData : Theme.fontUi
                        font.pixelSize: 14
                    }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { dd.picked(modelData); pop.close(); }
                    }
                }
            }
        }
    }
}
