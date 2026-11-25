import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// One window in the overview: a live capture that animates between the
// window's real place on screen and its slot in the overview grid.
Item {
    id: thumb
    required property var win          // { address, title, cls, top, real: {x,y,w,h}, slot: {x,y,w,h} }
    required property bool expanded
    property bool selected: false
    signal activated()
    signal closeRequested()
    signal droppedOn(var target)

    readonly property var r: expanded ? win.slot : win.real
    // While dragging, the offset goes into x/y itself: Qt's Drag only tracks
    // real position changes, not transforms, so DropAreas would never see it.
    x: r.x + (dragH.active ? dragH.activeTranslation.x : 0)
    y: r.y + (dragH.active ? dragH.activeTranslation.y : 0)
    width: r.w; height: r.h
    z: dragH.active ? 100 : (hover.hovered ? 2 : 1)

    Behavior on x      { enabled: !dragH.active; NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEmph } }
    Behavior on y      { enabled: !dragH.active; NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEmph } }
    Behavior on width  { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEmph } }
    Behavior on height { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEmph } }

    // drag support (drop on a workspace card)
    Drag.active: dragH.active
    Drag.keys: ["window"]
    // The drop point is where the window was grabbed (it stays under the
    // pointer), not the thumbnail's centre, which can be far below it.
    property point grab: Qt.point(width / 2, height / 2)
    Drag.hotSpot.x: grab.x
    Drag.hotSpot.y: grab.y
    scale: hover.hovered && thumb.expanded && !dragH.active ? 1.02 : 1
    Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Easing.OutBack } }
    // while dragging, shrink around the grab point so it stays under the pointer
    transform: Scale {
        origin.x: thumb.grab.x; origin.y: thumb.grab.y
        xScale: dragH.active ? 0.45 : 1; yScale: xScale
        Behavior on xScale { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
    }

    // remember the card under the pointer while dragging; by the time the
    // handler reports release, Drag.target has already been cleared
    property var lastTarget: null
    Drag.onTargetChanged: if (dragH.active) lastTarget = Drag.target

    DragHandler {
        id: dragH
        target: null
        enabled: thumb.expanded
        onActiveChanged: {
            if (active) { thumb.grab = centroid.pressPosition; thumb.lastTarget = null; return; }
            const t = thumb.lastTarget;
            thumb.lastTarget = null;
            if (t) thumb.droppedOn(t);
        }
    }

    // picture of the window, rounded. Taken once, not live: on NVIDIA every
    // live frame leaks a few file handles until qs hits its limit and the
    // desktop freezes (2026-11-23).
    ScreencopyView {
        id: cap
        anchors.fill: parent
        captureSource: thumb.win.top ? thumb.win.top.wayland : null
        live: false
        visible: false
    }
    Rectangle { id: mask; anchors.fill: parent; radius: Theme.radius; visible: false; layer.enabled: true }
    MultiEffect {
        anchors.fill: parent
        source: cap
        maskEnabled: true
        maskSource: mask
        shadowEnabled: thumb.expanded
        shadowBlur: 0.6
        shadowOpacity: 0.5
        shadowVerticalOffset: 6
    }
    // placeholder until the first frame arrives
    Rectangle {
        anchors.fill: parent; radius: Theme.radius
        visible: !cap.hasContent
        color: Theme.bg1
    }

    Rectangle {
        anchors.fill: parent; radius: Theme.radius
        color: "transparent"
        border.width: thumb.selected || hover.hovered ? 3 : 0
        border.color: Theme.yellow
        opacity: thumb.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
    }

    // app icon badge + title
    Column {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: -22 }
        spacing: 6
        opacity: thumb.expanded && !dragH.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44; height: 44; radius: 12
            color: Theme.bg0
            border.width: 1; border.color: Theme.bg2
            Image {
                anchors.centerIn: parent
                width: 30; height: 30
                sourceSize: Qt.size(60, 60)
                source: {
                    const e = DesktopEntries.heuristicLookup(thumb.win.cls);
                    return Quickshell.iconPath(e && e.icon ? e.icon : thumb.win.cls, "application-x-executable");
                }
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: hover.hovered || thumb.selected
            width: Math.min(titleText.implicitWidth + 20, Math.max(thumb.width, 220))
            height: 26; radius: 13
            color: Theme.bg0
            Text {
                id: titleText
                anchors.centerIn: parent
                width: parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: thumb.win.title
                color: Theme.fg1
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
            }
        }
    }

    // close button
    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: -10 }
        width: 32; height: 32; radius: 16
        visible: thumb.expanded && !dragH.active
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
        color: ch.hovered ? Theme.red : Theme.bg2
        Text { anchors.centerIn: parent; text: "close"; color: ch.hovered ? Theme.bg0 : Theme.fg1; font { family: Theme.fontIcons; pixelSize: 18 } }
        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
        TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: thumb.closeRequested() }
    }

    HoverHandler { id: hover; enabled: thumb.expanded; cursorShape: Qt.PointingHandCursor }
    // WithinBounds grabs the press (the DragHandler may still take it over),
    // so the overview's click-to-close background never sees it
    TapHandler {
        gesturePolicy: TapHandler.WithinBounds
        enabled: thumb.expanded
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onTapped: (pt, button) => button === Qt.MiddleButton ? thumb.closeRequested() : thumb.activated()
    }
}
