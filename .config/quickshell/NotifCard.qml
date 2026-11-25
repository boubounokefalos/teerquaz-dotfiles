import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications

// One notification. popup: true -> times out (paused on hover) with a progress
// line; false -> compact entry in the quick-settings history.
Rectangle {
    id: card
    required property var notif
    property bool popup: false

    readonly property bool urgent: notif && notif.urgency === NotificationUrgency.Critical
    readonly property int timeoutMs: !notif ? Config.notifTimeout * 1000
        : urgent ? 0
        : notif.expireTimeout > 0 ? notif.expireTimeout : Config.notifTimeout * 1000
    readonly property var buttons: notif ? notif.actions.filter(a => a.identifier !== "default" && a.text) : []

    implicitHeight: content.implicitHeight + 28
    radius: Theme.radiusPanel
    color: popup ? Theme.bg0s : (hover.hovered ? Theme.bg2 : Theme.bg1)
    border.width: popup || urgent ? 1 : 0
    border.color: urgent ? Theme.red : Theme.bg2
    clip: true
    Behavior on color { ColorAnimation { duration: Theme.durFast } }

    HoverHandler { id: hover }
    // click on the card: default action + dismiss (buttons below take their own clicks)
    MouseArea { anchors.fill: parent; z: -1; onClicked: if (card.notif) Notifs.activate(card.notif) }

    // ---- timeout ----
    property real remaining: 1
    NumberAnimation on remaining {
        id: life
        running: card.popup && card.timeoutMs > 0
        paused: hover.hovered
        from: 1; to: 0
        duration: card.timeoutMs
        onFinished: if (card.notif) Notifs.timeout(card.notif)
    }
    Rectangle {
        visible: card.popup && card.timeoutMs > 0
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: card.radius / 2 }
        height: 3
        radius: 1.5
        width: (parent.width - card.radius) * card.remaining
        color: Theme.blue
        opacity: 0.8
    }

    Column {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8

        // header: icon, app, time, close
        Row {
            width: parent.width
            spacing: 8
            Image {
                id: appIcon
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                sourceSize: Qt.size(36, 36)
                source: card.notif ? Notifs.iconFor(card.notif) : ""
                visible: status === Image.Ready
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !appIcon.visible
                text: "notifications"; color: Theme.blue
                font { family: Theme.fontIcons; pixelSize: 18 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.notif ? (card.notif.appName || "Notification") : ""
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                readonly property string a: card.notif ? (Notifs.tick, Notifs.age(card.notif.id)) : ""
                visible: a.length > 0
                text: "· " + a
                color: Theme.bg3
                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
            }
        }

        Row {
            width: parent.width
            spacing: 12
            Column {
                width: parent.width - (img.visible ? img.width + 12 : 0)
                spacing: 2
                Text {
                    width: parent.width
                    text: card.notif ? card.notif.summary : ""
                    color: Theme.fg0
                    elide: Text.ElideRight
                    font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: card.notif ? card.notif.body : ""
                    textFormat: Text.StyledText
                    color: Theme.fg1
                    wrapMode: Text.Wrap
                    maximumLineCount: card.popup ? 4 : 2
                    elide: Text.ElideRight
                    linkColor: Theme.blue
                    onLinkActivated: (url) => Qt.openUrlExternally(url)
                    font { family: Theme.fontUi; pixelSize: 13 }
                }
            }
            Item {
                id: img
                visible: card.notif && card.notif.image && imgSrc.status === Image.Ready
                width: 52; height: 52
                Image {
                    id: imgSrc
                    anchors.fill: parent
                    source: card.notif ? card.notif.image : ""
                    sourceSize: Qt.size(104, 104)
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                Rectangle { id: imgMask; anchors.fill: parent; radius: 10; visible: false; layer.enabled: true }
                MultiEffect { anchors.fill: parent; source: imgSrc; maskEnabled: true; maskSource: imgMask }
            }
        }

        // action buttons
        Row {
            visible: card.buttons.length > 0
            width: parent.width
            spacing: 6
            Repeater {
                model: card.buttons
                delegate: Rectangle {
                    required property var modelData
                    width: (parent.width - (card.buttons.length - 1) * 6) / card.buttons.length
                    height: 32; radius: 16
                    color: ah.hovered ? Theme.blueDim : Theme.bg2
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData.text
                        color: ah.hovered ? Theme.textOnBlue : Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                    }
                    HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                    MouseArea { anchors.fill: parent; onClicked: { modelData.invoke(); if (card.notif && !card.notif.resident) card.notif.dismiss(); } }
                }
            }
        }
    }

    // close button (on hover)
    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: 10 }
        width: 26; height: 26; radius: 13
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
        color: xh.hovered ? Theme.red : Theme.bg2
        Text { anchors.centerIn: parent; text: "close"; color: xh.hovered ? Theme.bg0 : Theme.fg1; font { family: Theme.fontIcons; pixelSize: 16 } }
        HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: if (card.notif) card.notif.dismiss() }
    }
}
