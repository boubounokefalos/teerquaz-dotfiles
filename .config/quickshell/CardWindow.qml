import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// One window inside a workspace card: a small picture at the window's scaled
// position, with a block + app icon until it arrives. Taken once, not live:
// on NVIDIA every live frame leaks a few file handles until qs hits its limit
// and the desktop freezes (2026-11-23).
Item {
    id: cw
    required property var win            // { real: {x,y,w,h}, cls, top }
    required property real sx
    required property real sy

    x: win.real.x * sx; y: win.real.y * sy
    width: Math.max(6, win.real.w * sx); height: Math.max(6, win.real.h * sy)

    ScreencopyView {
        id: cap
        anchors.fill: parent
        captureSource: cw.win.top ? cw.win.top.wayland : null
        live: false
        visible: false
    }
    Rectangle { id: mask; anchors.fill: parent; radius: 4; visible: false; layer.enabled: true }
    MultiEffect {
        anchors.fill: parent
        source: cap
        visible: cap.hasContent
        maskEnabled: true
        maskSource: mask
        shadowEnabled: true
        shadowBlur: 0.3
        shadowOpacity: 0.5
        shadowVerticalOffset: 1
    }

    // fallback until there is a frame (or if capture fails)
    Rectangle {
        anchors.fill: parent
        visible: !cap.hasContent
        radius: 4
        color: Qt.rgba(Theme.bg1.r, Theme.bg1.g, Theme.bg1.b, 0.92)
        border.width: 1; border.color: Theme.bg3
        Image {
            anchors.centerIn: parent
            width: Math.min(20, parent.width - 4, parent.height - 4); height: width
            visible: width >= 8
            sourceSize: Qt.size(40, 40)
            source: {
                const e = DesktopEntries.heuristicLookup(cw.win.cls);
                return Quickshell.iconPath(e && e.icon ? e.icon : cw.win.cls, "application-x-executable");
            }
        }
    }
}
