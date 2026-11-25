import QtQuick
import QtQml
import Quickshell
import Quickshell.Wayland

// Idle timeout in minutes (0 = off) that survives changing the time.
//
// Quickshell bug (seen in 0.3.2): when an IdleMonitor's timeout changes after it was
// created, it recreates its Wayland notification but `isIdle` never updates
// again, so the handler never runs. That happens at every shell start
// (settings.json loads after the default) and when the time is changed in
// Settings. A fresh IdleMonitor is built for every new value instead.
Instantiator {
    id: timer

    property int minutes: 0
    signal idle()
    signal resumed()

    model: minutes > 0 ? [minutes] : []
    delegate: IdleMonitor {
        required property int modelData
        timeout: modelData * 60
        // video/game idle inhibitors (mpv, browsers playing fullscreen) are respected
        respectInhibitors: true
        onIsIdleChanged: isIdle ? timer.idle() : timer.resumed()
    }
}
