import QtQuick

// Flat single-line text field (same shape as Dropdown).
Rectangle {
    id: tb
    property alias text: input.text
    property string placeholder: ""
    property bool password: false
    property bool invalid: false
    readonly property bool editing: input.activeFocus
    signal accepted()
    function focusInput() { input.forceActiveFocus(); }

    implicitWidth: 320
    implicitHeight: 40
    radius: 12
    color: hover.hovered || input.activeFocus ? Theme.bg2 : Theme.bg1
    border.width: input.activeFocus || invalid ? 2 : 0
    border.color: invalid ? Theme.red : Theme.yellowDim
    Behavior on color { ColorAnimation { duration: Theme.durFast } }

    TextInput {
        id: input
        anchors { left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14; verticalCenter: parent.verticalCenter }
        color: Theme.fg1
        selectionColor: Theme.yellowDim
        selectedTextColor: Theme.bg0
        clip: true
        echoMode: tb.password ? TextInput.Password : TextInput.Normal
        font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
        onAccepted: tb.accepted()
        Text {
            anchors.fill: parent
            visible: !input.text && !input.activeFocus
            text: tb.placeholder
            color: Theme.bg3
            font: input.font
            verticalAlignment: Text.AlignVCenter
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
}
