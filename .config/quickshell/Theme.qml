pragma Singleton
import QtQuick
import Quickshell

// Shared look: slate turquoise palette (same as the Teerquaz GTK theme), fonts, motion.
// Role names are historical (yellow = focus/selection, blue = switched on); only the values matter.
Singleton {
    readonly property color bg0:   "#181c1f"
    readonly property color bg0s:  "#1e2327"
    readonly property color bg1:   "#242b30"
    readonly property color bg2:   "#2f383e"
    readonly property color bg3:   "#3e4a51"
    readonly property color fg0:   "#f0f4f6"
    readonly property color fg1:   "#dce4e8"
    readonly property color fg4:   "#8b9aa2"
    readonly property color red:    "#e76f51"
    readonly property color green:  "#2ec4b6"
    readonly property color yellow: "#64dfdf"
    readonly property color yellowDim: "#2ec4b6"
    readonly property color blue:   "#2ec4b6"
    // Accents: yellow (teal) = you are here (selection, focus) and levels (sliders,
    // progress); blue (turquoise) = switched on (tiles, toggles), confirm buttons, info.
    // Orange = warning, red only for danger. Text on a blue fill is light, on yellow dark.
    readonly property color blueDim: "#1b8a84"
    readonly property color textOnBlue:  "#f0f4f6"
    readonly property color aqua:   "#2ec4b6"
    readonly property color orange: "#e9c46a"

    readonly property string fontDisplay: "Comfortaa"
    readonly property string fontUi:      "Nunito"
    readonly property string fontIcons:   "Material Symbols Rounded"

    readonly property int barHeight: 38
    // corner radius scale (uniformity rule):
    //   radiusPanel  floating panels & menus (quick settings, notifications, Alt+Tab, menus)
    //   radius       controls, cards, thumbnails, selection pills
    //   radiusItem   rows inside menus and lists
    //   buttons, toggles and chips are fully rounded (height / 2)
    readonly property int radiusPanel: 16
    readonly property int radius: 12
    readonly property int radiusItem: 10

    // Motion: one set of durations / curves for the whole shell
    readonly property int durFast: 140
    readonly property int durMed:  240
    readonly property int durSlow: 380
    readonly property var easeOut: Easing.OutCubic
    readonly property var easeEmph: Easing.OutExpo

    readonly property string wallpaper: Config.wallpaper

    // Same colour, fully transparent. Fade hover colours to this instead of
    // "transparent" (= transparent *black*), or the fade shows a dark ghost.
    function clear(c) { return Qt.rgba(c.r, c.g, c.b, 0); }
}
