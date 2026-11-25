import QtQuick
import Quickshell

// Base for the bar's menus (tray, network, drives, layout): the window starts
// exactly at the bar's bottom edge and clips, so the card slides down out from
// under the bar instead of flying in from above.
//   place(barWindow, x)  position under the bar (x in bar coordinates)
//   show() / hide()      animated open / close
// Children go inside the sliding card; set cardHeight.
PopupWindow {
    id: menu
    visible: false
    grabFocus: true
    color: "transparent"
    anchor.gravity: Edges.Bottom

    property real gap: 8                // space between bar and card when open
    property real cardHeight: 100
    property bool shown: false
    default property alias content: card.data

    implicitHeight: cardHeight + gap

    // Frosted like Quick Settings / calendar: cards are 82 % bg0 and Hyprland
    // blurs them (hyprland.lua: shell-bar blur_popups + ignore_alpha) —
    // Hyprland ignores BackgroundEffect on popups.

    function place(win, x) {
        anchor.window = win;
        anchor.rect.x = x;
        anchor.rect.y = win.height - 1;  // gravity Bottom → window top = bar bottom
        anchor.rect.width = 1;
        anchor.rect.height = 1;
    }
    function show() { hideTimer.stop(); visible = true; shown = true; }
    function hide() { shown = false; hideTimer.restart(); }

    // dismissed by the compositor (click outside): reset for the next open
    onVisibleChanged: if (!visible) shown = false

    Timer { id: hideTimer; interval: Theme.durMed; onTriggered: if (!menu.shown) menu.visible = false }

    Item {
        anchors.fill: parent
        clip: true

        Item {
            id: card
            width: parent.width
            height: menu.cardHeight
            y: menu.shown ? menu.gap : -height - 1
            opacity: menu.shown ? 1 : 0
            Behavior on y { NumberAnimation { duration: menu.shown ? Theme.durSlow : Theme.durMed; easing.type: menu.shown ? Theme.easeEmph : Theme.easeOut } }
            Behavior on opacity { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
        }
    }
}
