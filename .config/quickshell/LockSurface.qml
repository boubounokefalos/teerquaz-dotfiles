import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris

// What the lock screen shows on each monitor.
Item {
    id: surface
    required property var ctx

    // ---------- background: blurred, darkened wallpaper ----------
    Image {
        id: wall
        anchors.fill: parent
        source: Theme.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(surface.width / 2, surface.height / 2)  // blur hides the lower res
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: -0.15
        autoPaddingEnabled: false
    }
    Rectangle {
        anchors.fill: parent
        color: Theme.bg0
        opacity: 0.5
    }

    // ---------- content ----------
    Item {
        id: content
        anchors.fill: parent
        opacity: 0
        scale: 1.04

        states: [
            State { name: "shown"; when: surface.ready && !surface.ctx.unlocking
                PropertyChanges { target: content; opacity: 1; scale: 1 } },
            State { name: "leaving"; when: surface.ctx.unlocking
                PropertyChanges { target: content; opacity: 0; scale: 0.97 } }
        ]
        transitions: Transition {
            NumberAnimation { properties: "opacity,scale"; duration: Theme.durSlow; easing.type: Theme.easeEmph }
        }

        SystemClock { id: clock; precision: SystemClock.Seconds }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.16
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, Config.clock24 ? "HH:mm" : "h:mm")
                color: Theme.fg0
                font { family: Theme.fontDisplay; pixelSize: 132; weight: Font.Bold }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                color: Theme.fg1
                font { family: Theme.fontUi; pixelSize: 24; weight: Font.DemiBold }
            }
        }

        // ---------- now playing (any MPRIS player) + the Music player's lyric line ----------
        Column {
            id: media
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.37
            spacing: 14
            readonly property var player: {
                const ps = Mpris.players.values;
                for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
                for (let i = 0; i < ps.length; i++) if (ps[i].trackTitle) return ps[i];
                return null;
            }
            visible: player !== null && (player.trackTitle || "") !== ""
            // the Music player's own mpv: show its cleaned-up names instead of the raw tags
            readonly property bool ours: player !== null && player.dbusName.indexOf("mpv.Music") >= 0 && ShellState.musicTrack !== null
            Timer {   // MPRIS position is not pushed
                interval: 1000; repeat: true
                running: media.visible && media.player.isPlaying
                onTriggered: media.player.positionChanged()
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 460; height: 96
                radius: Theme.radiusPanel
                color: Qt.rgba(Theme.bg0s.r, Theme.bg0s.g, Theme.bg0s.b, 0.78)

                Image {
                    id: mArt
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 12 }
                    width: height
                    source: media.player ? media.player.trackArtUrl : ""
                    sourceSize: Qt.size(144, 144)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Rectangle { id: mArtMask; anchors.fill: mArt; radius: Theme.radius; visible: false; layer.enabled: true }
                MultiEffect { anchors.fill: mArt; source: mArt; maskEnabled: true; maskSource: mArtMask; visible: mArt.status === Image.Ready }
                Rectangle {
                    anchors.fill: mArt; radius: Theme.radius; color: Theme.bg2
                    visible: mArt.status !== Image.Ready
                    Text { anchors.centerIn: parent; text: "music_note"; color: Theme.fg4; font { family: Theme.fontIcons; pixelSize: 30 } }
                }

                Column {
                    anchors { left: mArt.right; leftMargin: 14; right: mCtl.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: media.ours ? ShellState.musicTrack.title : media.player ? media.player.trackTitle : ""
                        color: Theme.fg0
                        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: media.ours ? ShellState.musicTrack.artist : media.player ? (media.player.trackArtist || media.player.identity) : ""
                        color: Theme.fg4
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Rectangle {
                        width: parent.width; height: 4; radius: 2
                        color: Theme.bg2
                        visible: media.player !== null && media.player.lengthSupported && media.player.length > 0
                        Rectangle {
                            height: parent.height; radius: 2
                            color: Theme.yellowDim
                            width: media.player && media.player.length > 0 ? parent.width * Math.min(1, media.player.position / media.player.length) : 0
                            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                        }
                    }
                }

                Row {
                    id: mCtl
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Repeater {
                        model: [
                            { icon: "skip_previous", act: () => media.player.previous(), ok: () => media.player && media.player.canGoPrevious },
                            { icon: media.player && media.player.isPlaying ? "pause" : "play_arrow", act: () => media.player.togglePlaying(), ok: () => media.player && media.player.canTogglePlaying, big: true },
                            { icon: "skip_next", act: () => media.player.next(), ok: () => media.player && media.player.canGoNext }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: modelData.big ? 44 : 34; height: width; radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.big ? Theme.blueDim : (mh.hovered ? Theme.bg2 : Theme.clear(Theme.bg2))
                            opacity: modelData.ok() ? 1 : 0.4
                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                color: modelData.big ? Theme.textOnBlue : Theme.fg1
                                font { family: Theme.fontIcons; pixelSize: modelData.big ? 26 : 22 }
                            }
                            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { if (modelData.ok()) modelData.act(); input.forceActiveFocus(); } }
                        }
                    }
                }
            }

            // line being sung (Music player only)
            Text {
                id: lockLyric
                anchors.horizontalCenter: parent.horizontalCenter
                width: 640
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                text: media.ours ? ShellState.musicLyric : ""
                visible: text !== ""
                color: Theme.fg0
                style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.35)
                font { family: Theme.fontUi; pixelSize: 22; weight: Font.ExtraBold }
                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { target: lockLyric; property: "opacity"; to: 0; duration: 120 }
                        PropertyAction {}
                        NumberAnimation { target: lockLyric; property: "opacity"; to: 1; duration: 200 }
                    }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.56
            spacing: 18

            // avatar
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 104; height: 104
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.bg2
                    border.color: Theme.yellowDim
                    border.width: 3
                }
                Image {
                    id: avatar
                    anchors.fill: parent
                    anchors.margins: 4
                    source: "file:///var/lib/AccountsService/icons/" + Quickshell.env("USER")
                    sourceSize: Qt.size(200, 200)
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                Rectangle {
                    id: avatarMask
                    anchors.fill: avatar
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: avatar
                    source: avatar
                    maskEnabled: true
                    maskSource: avatarMask
                    visible: avatar.status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: "person"
                    color: Theme.fg4
                    font { family: Theme.fontIcons; pixelSize: 52 }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Quickshell.env("USER")
                color: Theme.fg1
                font { family: Theme.fontUi; pixelSize: 18; weight: Font.Bold }
            }

            // password pill
            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                // same field style as Settings' controls: 12px corners, solid bg1
                width: 340; height: 48
                radius: Theme.radius
                color: Theme.bg1
                border.width: 2
                border.color: surface.ctx.status !== "" ? Theme.red
                            : surface.ctx.busy ? Theme.blue
                            : input.activeFocus ? Theme.yellowDim : Theme.bg3
                Behavior on border.color { ColorAnimation { duration: Theme.durMed } }

                transform: Translate { id: shake }

                Text {
                    anchors.centerIn: parent
                    visible: surface.ctx.password.length === 0
                    text: surface.ctx.busy ? "Checking…" : "Password"
                    color: Theme.fg4
                    font { family: Theme.fontUi; pixelSize: 16 }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Repeater {
                        model: Math.min(surface.ctx.password.length, 24)
                        delegate: Rectangle {
                            width: 11; height: 11; radius: 5.5
                            color: surface.ctx.busy ? Theme.blue : Theme.fg1
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Easing.OutBack } }
                        }
                    }
                }

                // invisible field that actually receives the keys
                TextInput {
                    id: input
                    anchors.fill: parent
                    opacity: 0
                    focus: true
                    echoMode: TextInput.Password
                    enabled: !surface.ctx.busy && !surface.ctx.unlocking
                    onTextChanged: {
                        if (surface.ctx.password !== text) surface.ctx.password = text;
                        if (text.length > 0) surface.ctx.status = "";
                    }
                    onAccepted: surface.ctx.tryUnlock()
                    Keys.onEscapePressed: { text = ""; }
                    Component.onCompleted: forceActiveFocus()
                }
                Connections {
                    target: surface.ctx
                    function onPasswordChanged() {
                        if (input.text !== surface.ctx.password) input.text = surface.ctx.password;
                    }
                    function onFailCountChanged() { shakeAnim.restart(); input.forceActiveFocus(); }
                }

                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: shake; property: "x"; to: -14; duration: 50 }
                    NumberAnimation { target: shake; property: "x"; to: 12; duration: 70 }
                    NumberAnimation { target: shake; property: "x"; to: -8; duration: 70 }
                    NumberAnimation { target: shake; property: "x"; to: 5; duration: 60 }
                    NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: surface.ctx.status
                color: Theme.red
                opacity: text.length ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
            }

            // tries left before faillock locks the account (after a mistake)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: surface.ctx.failCount > 0 && surface.ctx.triesLeft > 0
                         && surface.ctx.triesLeft < surface.ctx.faillockDeny
                readonly property string lockFor: surface.ctx.faillockUnlockMin === 1 ? "1 minute" : surface.ctx.faillockUnlockMin + " minutes"
                text: (surface.ctx.triesLeft === 1 ? "1 try left" : surface.ctx.triesLeft + " tries left")
                      + " before the account is locked for " + lockFor
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }

            // keyboard layout + Caps Lock
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                Row {
                    spacing: 6
                    visible: surface.ctx.layoutName.length > 0
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "keyboard"; color: Theme.blue; font { family: Theme.fontIcons; pixelSize: 18 } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: surface.ctx.layoutName; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                }
                Row {
                    spacing: 6
                    visible: surface.ctx.capsLock
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "keyboard_capslock"; color: Theme.blue; font { family: Theme.fontIcons; pixelSize: 18 } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Caps Lock is on"; color: Theme.fg1; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                }
            }
        }
    }

    property bool ready: false
    Component.onCompleted: Qt.callLater(() => surface.ready = true)

    // clicking anywhere gives the field focus back
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: input.forceActiveFocus()
    }
}
