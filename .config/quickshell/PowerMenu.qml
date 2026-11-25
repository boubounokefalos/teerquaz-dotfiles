import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Full-screen power menu over a blurred desktop.
//   qs ipc call power toggle
PanelWindow {
    id: menu
    required property var lock

    property bool open: false
    property int current: 0
    property int armed: -1          // index waiting for a confirming second press

    readonly property var actions: [
        { icon: "lock",               label: "Lock",      id: "lock",     confirm: false },
        { icon: "bedtime",            label: "Suspend",   id: "suspend",  confirm: false },
        { icon: "logout",             label: "Log out",   id: "logout",   confirm: true  },
        { icon: "restart_alt",        label: "Restart",   id: "reboot",   confirm: true  },
        { icon: "power_settings_new", label: "Shut down", id: "poweroff", confirm: true  }
    ]

    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-panel-power"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // ask the compositor to blur everything behind the dim layer
    BackgroundEffect.blurRegion: Region { item: dim }

    function show() {
        current = 0; armed = -1;
        visible = true; open = true;
        keys.forceActiveFocus();
    }
    function hide() {
        open = false; armed = -1;
        hideTimer.restart();
    }
    function toggle() { open ? hide() : show(); }

    // hardware power button (XF86PowerOff), as set in Settings → Power & idle
    function button() {
        switch (Config.powerButton) {
        case "suspend":  if (Config.lockOnSuspend) menu.lock.lock(); suspendTimer.restart(); break;
        case "lock":     menu.lock.lock(); break;
        case "poweroff": Quickshell.execDetached(["systemctl", "poweroff"]); break;
        case "nothing":  break;
        default:         if (!menu.lock.isLocked) menu.toggle(); break;
        }
    }

    function activate(i) {
        const a = actions[i];
        if (a.confirm && armed !== i) {
            armed = i; current = i;
            disarmTimer.restart();
            return;
        }
        hide();
        switch (a.id) {
        case "lock":     menu.lock.lock(); break;
        case "suspend":  if (Config.lockOnSuspend) menu.lock.lock(); suspendTimer.restart(); break;
        case "logout":   Quickshell.execDetached([Quickshell.shellDir + "/scripts/logout.sh"]); break;
        case "reboot":   Quickshell.execDetached(["systemctl", "reboot"]); break;
        case "poweroff": Quickshell.execDetached(["systemctl", "poweroff"]); break;
        }
    }

    Timer { id: hideTimer;    interval: Theme.durMed; onTriggered: if (!menu.open) menu.visible = false }
    Timer { id: disarmTimer;  interval: 3000;         onTriggered: menu.armed = -1 }
    Timer { id: suspendTimer; interval: 700;          onTriggered: Quickshell.execDetached(["systemctl", "suspend"]) }

    IpcHandler {
        target: "power"
        function toggle(): void { menu.toggle(); }
        function button(): void { menu.button(); }
    }
    Connections {
        target: ShellState
        function onTogglePowerMenu() { menu.toggle(); }
    }

    // dim layer (Hyprland blurs what's behind it)
    Rectangle {
        id: dim
        anchors.fill: parent
        color: Theme.bg0
        opacity: menu.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
        MouseArea { anchors.fill: parent; onClicked: menu.hide() }
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { menu.hide(); e.accepted = true; }
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) {
                menu.current = (menu.current + menu.actions.length - 1) % menu.actions.length; menu.armed = -1; e.accepted = true;
            } else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) {
                menu.current = (menu.current + 1) % menu.actions.length; menu.armed = -1; e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                menu.activate(menu.current); e.accepted = true;
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 22

            Repeater {
                model: menu.actions
                delegate: Item {
                    id: btn
                    required property var modelData
                    required property int index
                    readonly property bool selected: menu.current === index
                    readonly property bool isArmed: menu.armed === index
                    width: 148; height: 172

                    // staggered entrance
                    opacity: 0
                    transform: Translate { id: lift; y: 24 }
                    states: State {
                        name: "in"; when: menu.open
                        PropertyChanges { target: btn; opacity: 1 }
                        PropertyChanges { target: lift; y: 0 }
                    }
                    transitions: [
                        Transition { to: "in"
                            SequentialAnimation {
                                PauseAnimation { duration: btn.index * 40 }
                                ParallelAnimation {
                                    NumberAnimation { target: btn;  property: "opacity"; duration: Theme.durMed; easing.type: Theme.easeOut }
                                    NumberAnimation { target: lift; property: "y"; duration: Theme.durSlow; easing.type: Easing.OutBack }
                                }
                            }
                        },
                        Transition { from: "in"
                            NumberAnimation { properties: "opacity,y"; duration: Theme.durFast; easing.type: Theme.easeOut }
                        }
                    ]

                    Rectangle {
                        id: card
                        width: 148; height: 148
                        radius: Theme.radiusPanel
                        color: btn.isArmed ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.22)
                             : (btn.selected || hover.hovered) ? Theme.bg2 : Qt.rgba(Theme.bg1.r, Theme.bg1.g, Theme.bg1.b, 0.9)
                        border.width: 2
                        border.color: btn.isArmed ? Theme.red : btn.selected ? Theme.yellowDim : Theme.clear(Theme.yellowDim)
                        scale: tap.pressed ? 0.94 : (hover.hovered || btn.selected ? 1.04 : 1)
                        Behavior on scale        { NumberAnimation { duration: Theme.durMed; easing.type: Easing.OutBack } }
                        Behavior on color        { ColorAnimation  { duration: Theme.durFast } }
                        Behavior on border.color { ColorAnimation  { duration: Theme.durFast } }

                        Text {
                            anchors.centerIn: parent
                            text: btn.modelData.icon
                            color: btn.isArmed ? Theme.red : (btn.selected || hover.hovered) ? Theme.yellow : Theme.fg1
                            font { family: Theme.fontIcons; pixelSize: 56 }
                            Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        }

                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) menu.current = btn.index }
                        TapHandler { id: tap; onTapped: menu.activate(btn.index) }
                    }

                    Text {
                        anchors { top: card.bottom; topMargin: 10; horizontalCenter: card.horizontalCenter }
                        text: btn.isArmed ? "Press again" : btn.modelData.label
                        color: btn.isArmed ? Theme.red : Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                    }
                }
            }
        }
    }
}
