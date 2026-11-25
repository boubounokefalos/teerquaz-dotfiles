import QtQuick
import QtQuick.Layouts

RowLayout {
    id: row
    property string label: ""
    property string hint: ""
    default property alias control: holder.data
    Layout.fillWidth: true
    spacing: 16
    Column {
        Layout.fillWidth: true
        Text { text: row.label; color: Theme.fg1; font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold } }
        Text {
            visible: row.hint.length > 0
            width: parent.width; wrapMode: Text.WordWrap
            text: row.hint; color: Theme.fg4
            font { family: Theme.fontUi; pixelSize: 12 }
        }
    }
    Item {
        id: holder
        implicitWidth: childrenRect.width
        implicitHeight: Math.max(40, childrenRect.height)
    }
}
