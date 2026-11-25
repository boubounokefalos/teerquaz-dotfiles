pragma Singleton
import QtQuick
import Quickshell

// Shared state and cross-component signals.
Singleton {
    signal togglePowerMenu()
    signal toggleQuickSettings()
    signal openSettings()
    signal openSettingsPage(int page)
    signal toggleOverview()
    signal toggleDatePanel()
    signal toggleMusicMini()            // bar song pill → Music.qml

    property bool quickSettingsOpen: false  // OSD stays quiet while QS sliders are visible
    property bool datePanelOpen: false      // notification popups wait while the list is open
    property bool keepAwake: false      // idle inhibitor (bar holds it)
    property bool doNotDisturb: false   // mako "do-not-disturb" mode
    property bool locked: false         // session lock is up (Lock.qml)
    property string musicLyric: ""      // line being sung in the Music player (Music.qml), for the lock screen
    property bool musicPlaying: false
    property var musicTrack: null       // { title, artist } of the Music player's song (cleaner than its tags)
}
