import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → Displays. Writes ~/.config/hypr/monitors.lua and reloads Hyprland.
// After Apply the change must be confirmed within 15 s, or it reverts.
ColumnLayout {
    id: dp
    spacing: 14

    property var monitors: []          // from `hyprctl monitors all -j` (real screens only)
    property var pending: ({})         // name -> { res, rate, scale, transform, vrr }
    property string previous: ""       // monitors.lua before Apply (for revert)
    property int countdown: 0

    readonly property string path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
    readonly property var scales: ["1", "1.25", "1.333333", "1.5", "1.6", "1.75", "2"]
    readonly property var rotations: ["Normal", "90°", "180°", "270°"]

    function load() { proc.running = true; }

    Process {
        id: proc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    dp.monitors = JSON.parse(text).filter(m => !m.name.startsWith("Unknown"));
                } catch (e) { dp.monitors = []; }
            }
        }
    }

    FileView { id: monFile; path: dp.path; blockLoading: true }

    // ---------- helpers ----------
    function modes(m) {
        return (m.availableModes || []).map(s => {
            const r = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
            return r ? { w: +r[1], h: +r[2], rate: r[3] } : null;
        }).filter(x => x);
    }
    function resolutions(m) {
        const seen = {}, out = [];
        for (const x of modes(m).sort((a, b) => b.w * b.h - a.w * a.h)) {
            const k = x.w + "x" + x.h;
            if (!seen[k]) { seen[k] = 1; out.push(k); }
        }
        return out;
    }
    function rates(m, res) {
        return modes(m).filter(x => x.w + "x" + x.h === res)
                       .map(x => x.rate).sort((a, b) => parseFloat(b) - parseFloat(a));
    }
    function cur(m) {
        const p = pending[m.name] || {};
        const res = p.res || (m.width + "x" + m.height);
        let rate = p.rate || m.refreshRate.toFixed(2);
        const rs = rates(m, res);
        if (rs.length && rs.indexOf(rate) < 0) rate = rs[0];
        return {
            res: res, rate: rate,
            scale: p.scale !== undefined ? p.scale : String(+m.scale.toFixed(6)),
            transform: p.transform !== undefined ? p.transform : m.transform,
            vrr: p.vrr !== undefined ? p.vrr : !!m.vrr
        };
    }
    function setP(m, key, val) {
        const all = Object.assign({}, pending);
        const p = Object.assign({}, all[m.name] || {});
        p[key] = val;
        if (key === "res") delete p.rate;          // pick the best rate for the new size
        all[m.name] = p;
        pending = all;
    }
    readonly property bool changed: {
        for (const m of monitors) {
            const c = cur(m);
            if (c.res !== m.width + "x" + m.height || c.rate !== m.refreshRate.toFixed(2)
                || parseFloat(c.scale) !== +m.scale.toFixed(6) || c.transform !== m.transform || c.vrr !== !!m.vrr)
                return true;
        }
        return false;
    }

    function generate() {
        const lines = ["-- Monitor rules. Written by Shell Settings → Displays (you can also edit by hand)."];
        for (const m of monitors) {
            const c = cur(m);
            lines.push('hl.monitor({ output = "' + m.name + '", mode = "' + c.res + "@" + c.rate +
                '", position = "' + m.x + "x" + m.y + '", scale = ' + c.scale +
                ', transform = ' + c.transform + ', vrr = ' + (c.vrr ? 1 : 0) + ' })');
        }
        lines.push('-- card0 "Unknown-1" is the leftover boot framebuffer, not a real screen');
        lines.push('hl.monitor({ output = "Unknown-1", disabled = true })');
        lines.push('hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })');
        return lines.join("\n") + "\n";
    }

    function apply() {
        monFile.reload();
        previous = monFile.text();
        monFile.setText(generate());
        Quickshell.execDetached(["hyprctl", "reload"]);
        countdown = 15;
        tick.restart();
        reloadLater.restart();
    }
    function keep() {
        countdown = 0; tick.stop(); previous = ""; pending = ({});
        load();
    }
    function revert() {
        countdown = 0; tick.stop();
        if (previous) monFile.setText(previous);
        previous = ""; pending = ({});
        Quickshell.execDetached(["hyprctl", "reload"]);
        reloadLater.restart();
        Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "desktop_windows", "Display settings reverted"]);
    }
    Timer { id: tick; interval: 1000; repeat: true; onTriggered: { dp.countdown--; if (dp.countdown <= 0) dp.revert(); } }
    Timer { id: reloadLater; interval: 900; onTriggered: dp.load() }

    // ---------- UI ----------
    SectionTitle { text: "Displays" }

    Repeater {
        model: dp.monitors
        delegate: ColumnLayout {
            id: mon
            required property var modelData
            readonly property var c: dp.cur(modelData)
            Layout.fillWidth: true
            spacing: 14

            // preview
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                readonly property var wh: mon.c.res.split("x").map(Number)
                readonly property bool turned: mon.c.transform % 2 === 1
                width: (turned ? wh[1] / wh[0] : wh[0] / wh[1]) * height
                height: 150
                Behavior on width { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
                radius: 12
                color: Theme.bg1
                border.width: 2; border.color: Theme.yellowDim
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (mon.modelData.make || "") + " " + (mon.modelData.model || mon.modelData.name)
                        color: Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: mon.modelData.name + " · " + mon.c.res + " @ " + Math.round(parseFloat(mon.c.rate)) + " Hz"
                        color: Theme.fg4
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                    }
                }
            }

            SettingRow {
                label: "Resolution"
                Dropdown { model: dp.resolutions(mon.modelData); current: mon.c.res; onPicked: (v) => dp.setP(mon.modelData, "res", v) }
            }
            SettingRow {
                label: "Refresh rate"
                Dropdown {
                    model: dp.rates(mon.modelData, mon.c.res).map(r => r + " Hz")
                    current: mon.c.rate + " Hz"
                    onPicked: (v) => dp.setP(mon.modelData, "rate", v.replace(" Hz", ""))
                }
            }
            SettingRow {
                label: "Scale"; hint: "Makes everything bigger; fractional scales can look slightly soft in some apps"
                Dropdown {
                    model: dp.scales.map(s => Math.round(parseFloat(s) * 100) + " %")
                    current: Math.round(parseFloat(mon.c.scale) * 100) + " %"
                    onPicked: (v) => dp.setP(mon.modelData, "scale", dp.scales.find(s => Math.round(parseFloat(s) * 100) + " %" === v))
                }
            }
            SettingRow {
                label: "Rotation"
                Dropdown { model: dp.rotations; current: dp.rotations[mon.c.transform] || "Normal"; onPicked: (v) => dp.setP(mon.modelData, "transform", dp.rotations.indexOf(v)) }
            }
            SettingRow {
                visible: !!mon.modelData.vrrCapable || mon.modelData.hardwareDetails !== undefined
                label: "Adaptive sync (VRR)"; hint: "Smoother games and video when the monitor supports it"
                Toggle { checked: mon.c.vrr; onToggled: (v) => dp.setP(mon.modelData, "vrr", v) }
            }
        }
    }

    // ===== Night light (applies at once, no Apply needed) =====
    SectionTitle { text: "Night light"; Layout.topMargin: 14 }
    Text {
        visible: !NightLight.available
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Needs hyprsunset (sudo pacman -S hyprsunset)."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    SettingRow {
        visible: NightLight.available
        label: "Night light"; hint: "Warmer colours that are easier on the eyes in the evening"
        Dropdown {
            readonly property var modes: [{ l: "Off", v: "off" }, { l: "Always on", v: "on" }, { l: "Scheduled", v: "schedule" }]
            model: modes.map(m => m.l)
            current: (modes.find(m => m.v === Config.nightLight) || modes[0]).l
            onPicked: (l) => Config.nightLight = (modes.find(m => m.l === l) || modes[0]).v
        }
    }
    SettingRow {
        visible: NightLight.available && Config.nightLight === "schedule"
        label: "From"; hint: NightLight.active ? "On now" : "Off now"
        Row {
            spacing: 8
            readonly property var times: Array.from({ length: 48 }, (_, i) => String(Math.floor(i / 2)).padStart(2, "0") + ":" + (i % 2 ? "30" : "00"))
            Dropdown { implicitWidth: 140; model: parent.times; current: Config.nightFrom; onPicked: (v) => Config.nightFrom = v }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "to"; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold } }
            Dropdown { implicitWidth: 140; model: parent.times; current: Config.nightTo; onPicked: (v) => Config.nightTo = v }
        }
    }
    SettingRow {
        visible: NightLight.available && Config.nightLight !== "off"
        label: "Warmth"
        ValueSlider {
            from: 2500; to: 6000; step: 100
            value: 8500 - Config.nightTemp          // right = warmer
            valueText: Config.nightTemp + " K"
            onMoved: (x) => Config.nightTemp = Math.round(8500 - x)
        }
    }

    // apply / confirm bar
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 10
        implicitHeight: 64
        radius: 16
        color: dp.countdown > 0 ? Qt.rgba(Theme.orange.r, Theme.orange.g, Theme.orange.b, 0.18) : Theme.bg1
        visible: dp.changed || dp.countdown > 0

        Text {
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter; right: buttons.left; rightMargin: 12 }
            text: dp.countdown > 0 ? "Keep these display settings? Reverting in " + dp.countdown + " s"
                                   : "Display settings changed"
            elide: Text.ElideRight
            color: Theme.fg1
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
        }
        Row {
            id: buttons
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 8
            PillButton { visible: dp.countdown > 0; text: "Revert"; onClicked: dp.revert() }
            PillButton { visible: dp.countdown > 0; text: "Keep"; primary: true; onClicked: dp.keep() }
            PillButton { visible: dp.countdown === 0; text: "Reset"; onClicked: dp.pending = ({}) }
            PillButton { visible: dp.countdown === 0; text: "Apply"; primary: true; onClicked: dp.apply() }
        }
    }
}
