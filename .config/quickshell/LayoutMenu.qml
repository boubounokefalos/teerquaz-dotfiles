import QtQuick
import Quickshell
import Quickshell.Io

// Menu under the bar's keyboard-layout label: the configured layouts
// (radio = active, click switches), then Keyboard settings.
// Same panel look as TrayMenu / NetMenu / DrivesMenu.
DropMenu {
    id: pop
    implicitWidth: 260
    cardHeight: col.implicitHeight + 12

    property var layouts: []      // [{ code, variant, name }]
    property int active: 0
    property var names: ({})      // "us" -> "English (US)", from evdev.lst

    function openAt(win, x, y) {
        place(win, x);
        devices.running = true;
        show();
    }
    function close() { hide(); }
    function pick(i) {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(i)]);
        pop.active = i;
        close();
    }

    Process {
        command: ["sh", "-c", "sed -n '/^! layout/,/^! variant/p' /usr/share/X11/xkb/rules/evdev.lst"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const n = {};
                for (const line of text.split("\n")) {
                    const m = line.match(/^\s+(\S+)\s+(.+)$/);
                    if (m) n[m[1]] = m[2].trim();
                }
                pop.names = n;
            }
        }
    }

    Process {
        id: devices
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards;
                    const k = kbs.find(x => x.main) || kbs[0];
                    if (!k) return;
                    const codes = k.layout.split(",");
                    const vars = (k.variant || "").split(",");
                    pop.layouts = codes.map((c, i) => ({
                        code: c.trim(),
                        variant: (vars[i] || "").trim(),
                        name: pop.names[c.trim()] || c.trim().toUpperCase()
                    }));
                    pop.active = k.active_layout_index;
                } catch (e) { console.warn("layout menu:", e); }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.82)
        border.width: 1
        border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)

        Column {
            id: col
            x: 6; y: 6
            width: pop.width - 12

            Repeater {
                model: pop.layouts
                delegate: TrayMenuRow {
                    required property var modelData
                    required property int index
                    label: modelData.name + (modelData.variant ? " (" + modelData.variant + ")" : "")
                    iconName: index === pop.active ? "radio_button_checked" : "radio_button_unchecked"
                    onActivated: pop.pick(index)
                }
            }

            Text {
                x: 10
                height: 26
                verticalAlignment: Text.AlignVCenter
                text: "Alt+Shift switches layouts"
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
            }

            Item { width: 1; height: 4 }
            Rectangle { x: 8; width: parent.width - 16; height: 1; color: Theme.bg2 }
            Item { width: 1; height: 6 }

            TrayMenuRow {
                label: "Keyboard settings"
                iconName: "keyboard"
                onActivated: { pop.close(); ShellState.openSettingsPage(7); }
            }
        }
    }
}
