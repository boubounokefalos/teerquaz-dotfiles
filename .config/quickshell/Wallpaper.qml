import QtQuick
import Quickshell
import Quickshell.Wayland

// Desktop background. Changing Theme.wallpaper crossfades to the new image.
PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "shell-wallpaper"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.bg0

    property bool frontIsA: true

    // right-click on the desktop opens the desktop menu
    DesktopMenu { id: deskMenu; screen: root.screen }
    MouseArea {
        anchors.fill: parent
        z: 2
        acceptedButtons: Qt.RightButton
        onPressed: (m) => deskMenu.open(m.x, m.y)
    }

    function show(path) {
        const next = frontIsA ? b : a;
        next.source = path;     // fades in once loaded (see onStatusChanged)
    }
    Component.onCompleted: { a.source = Theme.wallpaper; }
    Connections {
        target: Theme
        function onWallpaperChanged() { root.show(Theme.wallpaper); }
    }

    // the old image stays opaque underneath until the new one has faded in
    Timer {
        id: hideOld
        property var target: null
        interval: 750
        onTriggered: if (target) { target.opacity = 0; target.source = ""; }
    }


    Image {
        id: a

        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(root.width, root.height)   // decode at screen size only
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
        z: root.frontIsA ? 1 : 0
        onStatusChanged: if (status === Image.Ready) {
            root.frontIsA = true; opacity = 1; hideOld.target = b; hideOld.restart();
        }
    }
    Image {
        id: b

        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(root.width, root.height)   // decode at screen size only
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
        z: root.frontIsA ? 0 : 1
        onStatusChanged: if (status === Image.Ready) {
            root.frontIsA = false; opacity = 1; hideOld.target = a; hideOld.restart();
        }
    }
}
