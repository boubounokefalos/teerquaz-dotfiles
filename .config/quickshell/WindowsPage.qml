import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → Windows: gaps, animations, snapping, edge resizing, dimming
// (Hyprland options: applied live with `hyprctl eval`, saved to
// ~/.config/hypr/windows.lua), which workspaces tile (gnome-like.lua state),
// and the shell's overview triggers (Config).
ColumnLayout {
    id: page
    spacing: 14

    readonly property string path: Quickshell.env("HOME") + "/.config/hypr/windows.lua"
    readonly property string tiledPath: Quickshell.env("HOME") + "/.local/state/hypr/tiled-workspaces.json"

    // Lua path -> value
    property var v: ({})
    property var tiled: []
    readonly property var keys: [
        "general.gaps_in", "general.gaps_out", "general.resize_on_border", "general.snap.enabled",
        "decoration.dim_inactive", "animations.enabled"
    ]

    function load() {
        read.command = ["sh", "-c", keys.map(k => "hyprctl getoption -j " + k.replace(/\./g, ":") + " | tr -d '\\n'; echo").join("; ")
            + "; echo; cat " + JSON.stringify(tiledPath) + " 2>/dev/null"];
        read.running = true;
    }
    Process {
        id: read
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const out = {};
                for (let i = 0; i < page.keys.length; i++) {
                    try {
                        const o = JSON.parse(lines[i]);
                        let val = "int" in o ? o.int : "float" in o ? o.float : "bool" in o ? o.bool : "css" in o ? parseInt(o.css) : o.str;
                        out[page.keys[i]] = val;
                    } catch (e) {}
                }
                page.v = out;
                const m = /"tiled"\s*:\s*\[([^\]]*)\]/.exec(lines.slice(page.keys.length).join("\n"));
                page.tiled = m ? m[1].split(",").map(x => parseInt(x)).filter(x => !isNaN(x)) : [];
            }
        }
    }

    // ---------- writing ----------
    function lua(x) {
        if (typeof x === "boolean") return x ? "true" : "false";
        if (typeof x === "number") return String(Math.round(x * 1000) / 1000);
        return '"' + String(x).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }
    // { "a.b": 1, "a.c.d": 2 } -> "a = { b = 1, c = { d = 2 } }"
    function nest(flat) {
        const root = {};
        for (const k in flat) {
            const parts = k.split(".");
            let o = root;
            for (let i = 0; i < parts.length - 1; i++) o = o[parts[i]] = o[parts[i]] || {};
            o[parts[parts.length - 1]] = flat[k];
        }
        return root;
    }
    function serialize(o, indent) {
        const pad = "    ".repeat(indent);
        const parts = [];
        for (const k in o) {
            const val = o[k];
            if (val !== null && typeof val === "object") parts.push(pad + k + " = {\n" + serialize(val, indent + 1) + "\n" + pad + "},");
            else parts.push(pad + k + " = " + lua(val) + ",");
        }
        return parts.join("\n");
    }
    function inline(o) {
        const parts = [];
        for (const k in o) parts.push(k + " = " + (typeof o[k] === "object" ? inline(o[k]) : lua(o[k])));
        return "{ " + parts.join(", ") + " }";
    }
    function generate() {
        const flat = {};
        for (const k of keys) if (k in v) flat[k] = v[k];
        return "-- Window look and behaviour. Written by Shell Settings → Windows\n"
             + "-- (edits made here by hand are kept until the next change there).\n"
             + "hl.config({\n" + serialize(nest(flat), 1) + "\n})\n";
    }
    FileView { id: file; path: page.path; blockLoading: true }
    Timer { id: writeLater; interval: 400; onTriggered: file.setText(page.generate()) }

    function set(changes) {
        const nv = {};
        for (const k in v) nv[k] = v[k];
        for (const k in changes) nv[k] = changes[k];
        v = nv;
        Quickshell.execDetached(["hyprctl", "eval", "hl.config(" + inline(nest(changes)) + ")"]);
        writeLater.restart();
    }

    function setTiled(ws, on) {
        tiled = on ? tiled.concat([ws]) : tiled.filter(x => x !== ws);
        Quickshell.execDetached(["hyprctl", "eval",
            'local g = package.loaded["gnome-like"]; if g then g.set_workspace_tiling(' + ws + ', ' + (on ? "true" : "false") + ', true) end']);
    }

    // ===== Windows =====
    SectionTitle { text: "Windows" }

    SettingRow {
        label: "Space between windows"; hint: "On tiled workspaces"
        Stepper {
            value: page.v["general.gaps_in"] ?? 5; min: 0; max: 30; step: 1; suffix: " px"; textWidth: 60
            onChanged: (x) => page.set({ "general.gaps_in": x })
        }
    }
    SettingRow {
        label: "Space at the screen edges"
        Stepper {
            value: page.v["general.gaps_out"] ?? 10; min: 0; max: 60; step: 2; suffix: " px"; textWidth: 60
            onChanged: (x) => page.set({ "general.gaps_out": x })
        }
    }
    SettingRow {
        label: "Snap floating windows"; hint: "Windows stick to screen edges and to each other while dragged"
        Toggle { checked: !!page.v["general.snap.enabled"]; onToggled: (x) => page.set({ "general.snap.enabled": x }) }
    }
    SettingRow {
        label: "Resize from window edges"; hint: "Drag the border around a window"
        Toggle { checked: !!page.v["general.resize_on_border"]; onToggled: (x) => page.set({ "general.resize_on_border": x }) }
    }
    SettingRow {
        label: "Dim windows in the background"
        Toggle { checked: !!page.v["decoration.dim_inactive"]; onToggled: (x) => page.set({ "decoration.dim_inactive": x }) }
    }
    SettingRow {
        label: "Animations"; hint: "Windows and workspaces slide and pop; off makes everything instant"
        Toggle { checked: page.v["animations.enabled"] !== false; onToggled: (x) => page.set({ "animations.enabled": x }) }
    }

    // ===== Tiling =====
    SectionTitle { text: "Tiling"; Layout.topMargin: 14 }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Windows float on most workspaces, like GNOME. Pick the workspaces that arrange their windows side by side instead (Super + T switches the current one)."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: 10
            delegate: Rectangle {
                id: chip
                required property int index
                readonly property int ws: index + 1
                readonly property bool on: page.tiled.indexOf(ws) >= 0
                width: 92; height: 40; radius: 20
                color: on ? Theme.blueDim : (ch.hovered ? Theme.bg2 : Theme.bg1)
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.on ? "dashboard" : "filter_none"
                        color: chip.on ? Theme.textOnBlue : Theme.fg4
                        font { family: Theme.fontIcons; pixelSize: 18 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.ws
                        color: chip.on ? Theme.textOnBlue : Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                    }
                }
                HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: page.setTiled(chip.ws, !chip.on) }
            }
        }
    }

    // ===== Overview =====
    SectionTitle { text: "Overview"; Layout.topMargin: 14 }

    SettingRow {
        label: "Tap Super to open the overview"
        Toggle { checked: Config.superOverview; onToggled: (x) => Config.superOverview = x }
    }
    SettingRow {
        label: "Hot corner"; hint: "Push the pointer into the top-left corner to open the overview"
        Toggle { checked: Config.hotCorner; onToggled: (x) => Config.hotCorner = x }
    }
}
