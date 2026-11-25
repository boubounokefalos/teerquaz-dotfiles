pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell settings stored in ~/.config/quickshell/settings.json.
// (GTK theme, fonts, icons and cursor live in dconf / gsettings instead,
//  which every toolkit reads without GNOME running.)
Singleton {
    id: cfg

    readonly property string defaultWallpaper:
        Quickshell.env("HOME") + "/Pictures/Wallpapers/teerquaz.png"
    readonly property var wallpaperDirs: [
        Quickshell.env("HOME") + "/Pictures/Wallpapers",
        Quickshell.env("HOME") + "/.local/share/backgrounds"
    ]

    property alias wallpaper: data.wallpaper
    property alias volumeSound: data.volumeSound
    property alias clock24: data.clock24
    // Settings → Power & idle (minutes, 0 = never)
    property alias lockAfter: data.lockAfter
    property alias screenOffAfter: data.screenOffAfter
    property alias suspendAfter: data.suspendAfter
    property alias lockOnSuspend: data.lockOnSuspend
    property alias powerButton: data.powerButton      // menu | suspend | lock | poweroff | nothing
    // Settings → Windows
    property alias hotCorner: data.hotCorner
    property alias superOverview: data.superOverview
    property alias autoMount: data.autoMount          // mount USB drives when plugged in
    // night light (NightLight.qml)
    property alias nightLight: data.nightLight        // off | on | schedule
    property alias nightTemp: data.nightTemp          // Kelvin
    property alias nightFrom: data.nightFrom          // "HH:MM"
    property alias nightTo: data.nightTo
    // Settings → Notifications
    property alias notifTimeout: data.notifTimeout    // seconds a popup stays when the app doesn't say
    property alias notifRules: data.notifRules        // { "App name": "silent" | "off" }  (missing = normal)
    property alias notifApps: data.notifApps          // app names seen so far (for the rules list)
    // Music player (Music.qml)
    property alias musicVolume: data.musicVolume      // 0..100, mpv volume
    property alias musicShuffle: data.musicShuffle
    property alias musicRepeat: data.musicRepeat      // off | all | one
    property alias musicSort: data.musicSort          // name | artist | title | added

    function setWallpaper(path) {
        data.wallpaper = path;
        // keep GNOME and anything else reading the GNOME key in sync
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.background", "picture-uri-dark", "file://" + path]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.background", "picture-uri", "file://" + path]);
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: (err) => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: data
            property string wallpaper: cfg.defaultWallpaper
            property bool volumeSound: true
            property bool clock24: true
            property int lockAfter: 5
            property int screenOffAfter: 10
            property int suspendAfter: 0
            property bool lockOnSuspend: true
            property string powerButton: "menu"
            property bool hotCorner: true
            property bool superOverview: true
            property bool autoMount: true
            property string nightLight: "off"
            property int nightTemp: 4000
            property string nightFrom: "20:00"
            property string nightTo: "07:00"
            property int notifTimeout: 6
            property var notifRules: ({})
            property var notifApps: []
            property int musicVolume: 70
            property bool musicShuffle: false
            property string musicRepeat: "all"
            property string musicSort: "name"
        }
    }
}
