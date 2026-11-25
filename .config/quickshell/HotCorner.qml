import QtQuick
import Quickshell
import Quickshell.Wayland

// Top-left hot corner: pushing the pointer into it opens the overview.
PanelWindow {
    id: hc
    anchors { top: true; left: true }
    implicitWidth: 2
    implicitHeight: 2
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-hotcorner"

    property real last: 0
    HoverHandler {
        onHoveredChanged: {
            if (!hovered || !Config.hotCorner) return;
            const now = Date.now();
            if (now - hc.last < 800) return;     // don't re-trigger while the pointer sits there
            hc.last = now;
            ShellState.toggleOverview();
        }
    }
}
