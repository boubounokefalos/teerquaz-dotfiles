import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings → Shortcuts: every Hyprland key binding, read live from
// `hyprctl binds -j`. Names come from the bind's description
// ("Group: what it does", set in ~/.config/hypr/hyprland.lua).
ColumnLayout {
    id: page
    spacing: 14

    // data lives in Binds.qml (shared with the shortcuts popup)
    readonly property var groups: Binds.groups
    function load() { Binds.load(); }

    readonly property string query: search.text.trim().toLowerCase()
    function matches(row) { return Binds.matches(row, query); }

    SettingRow {
        label: "Keyboard shortcuts"
        hint: "Set in ~/.config/hypr/hyprland.lua"
        TextBox { id: search; placeholder: "Search shortcuts" }
    }

    Repeater {
        model: page.groups
        delegate: ColumnLayout {
            id: grp
            required property var modelData
            readonly property var rows: modelData.rows.filter(r => page.matches(r))
            visible: rows.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 6

            SectionTitle { text: grp.modelData.name }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: list.implicitHeight + 12
                radius: Theme.radius
                color: Theme.bg1

                Column {
                    id: list
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                    Repeater {
                        model: grp.rows
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: list.width
                            height: Math.max(44, keys.implicitHeight + 12)
                            radius: Theme.radiusItem
                            color: rh.hovered ? Theme.bg2 : Theme.clear(Theme.bg2)
                            HoverHandler { id: rh }
                            Text {
                                anchors { left: parent.left; leftMargin: 12; right: keys.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: row.modelData.text
                                elide: Text.ElideRight
                                color: Theme.fg1
                                font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
                            }
                            KeyCaps {
                                id: keys
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                combos: row.modelData.combos
                            }
                        }
                    }
                }
            }
        }
    }
    Text {
        visible: page.groups.length > 0 && page.query.length > 0 && !page.groups.some(g => g.rows.some(r => page.matches(r)))
        text: "No shortcut matches “" + search.text + "”."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }
}
