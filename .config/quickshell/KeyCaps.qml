import QtQuick

// One or more key combos drawn as keycaps, right-aligned, one combo per line.
// combos: [["Super", "Shift", "V"], …]
Column {
    id: caps
    property var combos: []
    spacing: 4
    Repeater {
        model: caps.combos
        delegate: Row {
            id: cmb
            required property var modelData
            anchors.right: parent.right
            spacing: 4
            Repeater {
                model: cmb.modelData
                delegate: Rectangle {
                    required property string modelData
                    height: 26; radius: 8
                    width: Math.max(26, kt.implicitWidth + 16)
                    color: Theme.bg0s
                    border.width: 1; border.color: Theme.bg3
                    Text {
                        id: kt
                        anchors.centerIn: parent
                        text: modelData
                        color: Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                    }
                }
            }
        }
    }
}
