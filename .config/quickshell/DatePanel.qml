import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// GNOME-style date menu, dropping down under the clock: notification history
// on the left, a month calendar on the right.
//   qs ipc call datepanel toggle
PanelWindow {
    id: dp

    property bool open: false
    // card offset: 0 open, fully hidden under the bar closed
    property real drop: open ? 0 : -(card.height + 10)
    Behavior on drop { NumberAnimation { duration: dp.open ? Theme.durSlow : Theme.durMed; easing.type: dp.open ? Theme.easeEmph : Theme.easeOut } }
    onOpenChanged: ShellState.datePanelOpen = open

    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-panel-date"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: blurArea; radius: card.radius }

    function show() {
        today = new Date();
        shownYear = today.getFullYear();
        shownMonth = today.getMonth();
        visible = true; open = true;
        keys.forceActiveFocus();
    }
    function hide() { open = false; hideTimer.restart(); }
    function toggle() { open ? hide() : show(); }

    Timer { id: hideTimer; interval: Theme.durMed; onTriggered: if (!dp.open) dp.visible = false }

    IpcHandler {
        target: "datepanel"
        function toggle(): void { dp.toggle(); }
    }
    Connections {
        target: ShellState
        function onToggleDatePanel() { dp.toggle(); }
        // only one of quick settings / date menu at a time
        function onQuickSettingsOpenChanged() { if (ShellState.quickSettingsOpen && dp.open) dp.hide(); }
    }

    // ---------- calendar data ----------
    property var today: new Date()
    property int shownYear: today.getFullYear()
    property int shownMonth: today.getMonth()          // 0-11
    function stepMonth(d) {
        let m = shownMonth + d, y = shownYear;
        while (m < 0) { m += 12; y--; }
        while (m > 11) { m -= 12; y++; }
        shownMonth = m; shownYear = y;
    }
    function goToday() { today = new Date(); shownYear = today.getFullYear(); shownMonth = today.getMonth(); }
    readonly property bool atThisMonth: shownYear === today.getFullYear() && shownMonth === today.getMonth()

    // 6 weeks, Monday first
    readonly property var days: {
        const first = new Date(shownYear, shownMonth, 1);
        const lead = (first.getDay() + 6) % 7;              // Monday = 0
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(shownYear, shownMonth, 1 - lead + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === shownMonth,
                isToday: d.toDateString() === today.toDateString(),
                weekend: d.getDay() === 0 || d.getDay() === 6
            });
        }
        return out;
    }
    // the date changes while the panel is open past midnight
    Timer { interval: 60000; repeat: true; running: dp.open; onTriggered: dp.today = new Date() }

    // ---------- click outside closes ----------
    MouseArea { anchors.fill: parent; onClicked: dp.hide() }

    // clipped at the bar's bottom edge: the card slides out from under the bar
    Item {
        id: dropClip
        anchors { fill: parent; topMargin: Theme.barHeight }
        clip: true

        Item {
            id: blurArea
            // visible part of the card only, so no empty blur shows while it slides
            x: card.x; width: card.width
            y: Math.max(0, card.y + dp.drop)
            height: Math.max(0, card.y + dp.drop + card.height - y)
            opacity: 0
        }
        Rectangle {
            id: card
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 8 }
            width: 780
            height: Math.max(cal.implicitHeight, 300) + 40
            radius: Theme.radiusPanel
            color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.82)
            border.width: 1
            border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)
            clip: true

            opacity: dp.open ? 1 : 0
            transform: Translate { y: dp.drop }
            Behavior on opacity { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }

            MouseArea { anchors.fill: parent }   // clicks inside don't close it

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: dp.hide()
                Keys.onLeftPressed: dp.stepMonth(-1)
                Keys.onRightPressed: dp.stepMonth(1)
                Keys.onPressed: (e) => { if (e.key === Qt.Key_Home) { dp.goToday(); e.accepted = true; } }

                RowLayout {
                    anchors { fill: parent; margins: 20 }
                    spacing: 20

                    // ---------------- notifications ----------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: Notifs.count > 0
                            contentHeight: histCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            Column {
                                id: histCol
                                width: parent.width
                                spacing: 8
                                Repeater {
                                    model: Notifs.history
                                    delegate: NotifCard {
                                        required property var modelData
                                        width: histCol.width
                                        notif: modelData
                                        popup: false
                                    }
                                }
                            }
                        }
                        // empty state
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: Notifs.count === 0
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "notifications"
                                    color: Theme.bg3
                                    font { family: Theme.fontIcons; pixelSize: 56 }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No notifications"
                                    color: Theme.fg4
                                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                                }
                            }
                        }
                        // footer: Do Not Disturb + Clear
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text {
                                text: "Do Not Disturb"
                                color: Theme.fg1
                                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                            }
                            Toggle {
                                checked: ShellState.doNotDisturb
                                onToggled: (v) => ShellState.doNotDisturb = v
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                visible: Notifs.count > 0
                                implicitWidth: clearTxt.implicitWidth + 28; implicitHeight: 32; radius: 16
                                color: clh.hovered ? Theme.bg2 : Theme.bg1
                                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                Text { id: clearTxt; anchors.centerIn: parent; text: "Clear"; color: Theme.fg1; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold } }
                                HoverHandler { id: clh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: Notifs.clearAll() }
                            }
                        }
                    }

                    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.bg2 }

                    // ---------------- calendar ----------------
                    Column {
                        id: cal
                        Layout.alignment: Qt.AlignTop
                        spacing: 14
                        readonly property int cell: 42

                        // today, big
                        Column {
                            spacing: 2
                            Text {
                                text: Qt.formatDate(dp.today, "dddd")
                                color: Theme.fg4
                                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                            }
                            Text {
                                text: Qt.formatDate(dp.today, "d MMMM yyyy")
                                color: Theme.fg0
                                font { family: Theme.fontDisplay; pixelSize: 20; weight: Font.Bold }
                            }
                        }

                        // month header: ‹ Month Year ›
                        Item {
                            width: cal.cell * 7
                            height: 36
                            RoundIcon {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                icon: "chevron_left"
                                onClicked: dp.stepMonth(-1)
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: monthTxt.implicitWidth + 28; height: 32; radius: 16
                                color: mh.hovered && !dp.atThisMonth ? Theme.bg2 : Theme.clear(Theme.bg2)
                                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                Text {
                                    id: monthTxt
                                    anchors.centerIn: parent
                                    text: Qt.formatDate(new Date(dp.shownYear, dp.shownMonth, 1), "MMMM yyyy")
                                    color: Theme.fg1
                                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.ExtraBold }
                                }
                                // back to this month
                                HoverHandler { id: mh; cursorShape: dp.atThisMonth ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: dp.goToday() }
                            }
                            RoundIcon {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                icon: "chevron_right"
                                onClicked: dp.stepMonth(1)
                            }
                        }

                        // weekday names, Monday first
                        Row {
                            Repeater {
                                model: 7
                                delegate: Text {
                                    required property int index
                                    width: cal.cell
                                    horizontalAlignment: Text.AlignHCenter
                                    // 2 Nov 2026 is a Monday
                                    text: Qt.formatDate(new Date(2026, 10, 2 + index), "ddd")
                                    color: Theme.fg4
                                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                                }
                            }
                        }

                        // days
                        Grid {
                            columns: 7
                            WheelHandler {
                                onWheel: (e) => dp.stepMonth(e.angleDelta.y > 0 ? -1 : 1)
                            }
                            Repeater {
                                model: dp.days
                                delegate: Item {
                                    required property var modelData
                                    width: cal.cell; height: cal.cell - 4
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 36; height: 36; radius: 18
                                        color: parent.modelData.isToday ? Theme.yellowDim : Theme.clear(Theme.bg2)
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.day
                                        color: parent.modelData.isToday ? Theme.bg0
                                             : !parent.modelData.inMonth ? Theme.bg3
                                             : parent.modelData.weekend ? Theme.fg4 : Theme.fg1
                                        font { family: Theme.fontUi; pixelSize: 14; weight: parent.modelData.isToday ? Font.ExtraBold : Font.Bold }
                                    }
                                }
                            }
                        }

                        // jump back to today when looking at another month
                        Item {
                            width: cal.cell * 7; height: 32
                            PillButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: !dp.atThisMonth
                                implicitHeight: 32
                                text: "Today"
                                onClicked: dp.goToday()
                            }
                        }
                    }
                }
            }
        }
    }
}
