import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit

// The session's polkit agent: "an app wants to do something as admin" asks
// for the password here, in the shell's look (replaces hyprpolkitagent).
// Shows the keyboard layout + Caps Lock, like the lock screen, because a
// password typed on the Greek layout never matches.
PanelWindow {
    id: win

    readonly property var flow: agent.flow
    readonly property bool open: agent.isActive && flow !== null

    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-panel-polkit"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: dim }

    PolkitAgent { id: agent }

    property string layout: ""
    property bool caps: false
    property bool busy: false

    onOpenChanged: {
        if (open) {
            pw.text = ""; busy = false;
            visible = true;
            kb.running = true; kbPoll.start();
            pw.focusInput();
        } else {
            kbPoll.stop();
            hideTimer.restart();
        }
    }
    Timer { id: hideTimer; interval: Theme.durMed; onTriggered: if (!win.open) win.visible = false }

    // a new password round (wrong password → asked again)
    Connections {
        target: win.flow
        ignoreUnknownSignals: true
        function onIsResponseRequiredChanged() {
            if (win.flow.isResponseRequired) { win.busy = false; pw.text = ""; pw.focusInput(); }
        }
        function onAuthenticationFailed() { win.busy = false; pw.text = ""; }
    }

    function submit() {
        if (!flow || !flow.isResponseRequired || busy) return;
        busy = true;
        flow.submit(pw.text);
    }
    function cancel() { if (flow) flow.cancelAuthenticationRequest(); }

    // keyboard layout + Caps Lock of the main keyboard
    Process {
        id: kb
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const k = JSON.parse(text).keyboards.find(x => x.main) || {};
                    win.layout = k.active_keymap || "";
                    win.caps = !!k.capsLock;
                } catch (e) {}
            }
        }
    }
    Timer { id: kbPoll; interval: 500; repeat: true; onTriggered: kb.running = true }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Theme.bg0
        opacity: win.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
        height: body.implicitHeight + 48
        radius: Theme.radiusPanel
        color: Theme.bg0s
        border.width: 1
        border.color: Theme.bg2
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
        Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }

        Column {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56; height: 56; radius: 28
                color: Theme.blueDim
                Text {
                    anchors.centerIn: parent
                    text: "admin_panel_settings"
                    color: Theme.textOnBlue
                    font { family: Theme.fontIcons; pixelSize: 30 }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Authentication required"
                color: Theme.fg0
                font { family: Theme.fontDisplay; pixelSize: 20; weight: Font.Bold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: win.flow ? win.flow.message : ""
                color: Theme.fg1
                font { family: Theme.fontUi; pixelSize: 14 }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: win.flow ? win.flow.actionId : ""
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 11 }
            }

            TextBox {
                id: pw
                width: parent.width
                implicitHeight: 48
                password: !(win.flow && win.flow.responseVisible)
                placeholder: win.flow && win.flow.inputPrompt ? win.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                invalid: !!(win.flow && win.flow.supplementaryIsError && win.flow.supplementaryMessage)
                enabled: !win.busy
                onAccepted: win.submit()
                Keys.onEscapePressed: win.cancel()
            }

            // layout / Caps Lock / errors
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14
                Row {
                    spacing: 4
                    visible: win.layout !== ""
                    Text { text: "keyboard"; color: Theme.blue; font { family: Theme.fontIcons; pixelSize: 16 } }
                    Text { text: win.layout; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                }
                Row {
                    spacing: 4
                    visible: win.caps
                    Text { text: "keyboard_capslock"; color: Theme.blue; font { family: Theme.fontIcons; pixelSize: 16 } }
                    Text { text: "Caps Lock is on"; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                }
            }
            Text {
                visible: text.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: win.flow ? win.flow.supplementaryMessage : ""
                color: win.flow && win.flow.supplementaryIsError ? Theme.red : Theme.fg4
                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
            }

            Row {
                anchors.right: parent.right
                spacing: 8
                PillButton { text: "Cancel"; onClicked: win.cancel() }
                PillButton { text: win.busy ? "Checking…" : "Authenticate"; primary: true; onClicked: win.submit() }
            }
        }
    }
}
