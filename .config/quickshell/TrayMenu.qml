import QtQuick
import Quickshell
import Quickshell.Widgets

// Tray icon menu drawn by the shell (instead of Qt's own menu widget), styled
// like Settings' dropdowns and the GTK context menus: rounded #1e2327 panel,
// Nunito, yellow rounded highlight. Submenus open in place with a back row.
DropMenu {
    id: pop
    implicitWidth: Math.max(220, Math.min(380, col.implicitWidth + 12))
    cardHeight: col.implicitHeight + 12

    property var stack: []              // menu handles, root first
    readonly property var current: stack.length ? stack[stack.length - 1] : null

    // open(menuHandle, barWindow, x, y) — x/y in the bar window's coordinates
    function openAt(menu, win, x, y) {
        stack = [menu];
        place(win, x);
        show();
    }
    function close() { hide(); }


    QsMenuOpener { id: opener; menu: pop.current }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.82)
        border.width: 1
        border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)

        Column {
            id: col
            x: 6; y: 6
            width: pop.width - 12

            // back row inside submenus
            TrayMenuRow {
                visible: pop.stack.length > 1
                label: "Back"
                iconName: "chevron_left"
                onActivated: { const s = pop.stack.slice(); s.pop(); pop.stack = s; }
            }
            Rectangle {
                visible: pop.stack.length > 1
                width: parent.width; height: 13; color: "transparent"
                Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.bg2 }
            }

            Repeater {
                model: opener.children
                delegate: Loader {
                    id: entryLoader
                    required property var modelData
                    width: col.width
                    sourceComponent: modelData.isSeparator ? sep : row
                    Component {
                        id: sep
                        Item {
                            height: 13
                            Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.bg2 }
                        }
                    }
                    Component {
                        id: row
                        TrayMenuRow {
                            entry: entryLoader.modelData
                            onActivated: {
                                const e = entryLoader.modelData;
                                if (e.hasChildren) { const s = pop.stack.slice(); s.push(e); pop.stack = s; }
                                else { e.triggered(); pop.close(); }
                            }
                        }
                    }
                }
            }
        }
    }
}
