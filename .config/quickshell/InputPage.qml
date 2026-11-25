import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → Keyboard & mouse. Reads the live values with `hyprctl getoption`,
// applies a change at once with `hyprctl eval` (only the changed key), and
// writes them all to ~/.config/hypr/input.lua (required by hyprland.lua).
ColumnLayout {
    id: page
    spacing: 14

    readonly property string path: Quickshell.env("HOME") + "/.config/hypr/input.lua"

    // current values (Lua key -> value); touchpad keys are "touchpad.<key>"
    property var v: ({})
    property bool loaded: false
    property bool hasTouchpad: false

    // xkb names from evdev.lst
    property var layoutNames: ({})        // "us" -> "English (US)"
    property var layoutCodes: []          // sorted by description
    property var variants: ({})           // "gr" -> [{ code, desc }]

    readonly property var layouts: (v.kb_layout || "us").split(",")
    readonly property var layoutVariants: {
        const vs = (v.kb_variant || "").split(",");
        return layouts.map((_, i) => vs[i] || "");
    }
    readonly property var options: (v.kb_options || "").split(",").filter(o => o)

    readonly property var keys: [
        "kb_layout", "kb_variant", "kb_options", "repeat_rate", "repeat_delay", "numlock_by_default",
        "follow_mouse", "sensitivity", "accel_profile", "natural_scroll", "scroll_factor", "left_handed",
        "touchpad.natural_scroll", "touchpad.tap_to_click", "touchpad.disable_while_typing", "touchpad.scroll_factor"
    ]
    // hyprctl getoption spells two of them differently
    function optName(k) { return "input:" + k.replace(".", ":").replace("tap_to_click", "tap-to-click"); }

    function load() {
        read.command = ["sh", "-c", page.keys.map(k => "hyprctl getoption -j " + optName(k) + " | tr -d '\\n'; echo").join("; ")
            + "; grep -qi touchpad /proc/bus/input/devices && echo TOUCHPAD"];
        read.running = true;
        if (!page.layoutCodes.length) xkb.running = true;
    }
    Process {
        id: read
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                let tp = false;
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i] === "TOUCHPAD") { tp = true; continue; }
                    if (!lines[i].trim() || i >= page.keys.length) continue;
                    try {
                        const o = JSON.parse(lines[i]);
                        let val = "int" in o ? o.int : "float" in o ? o.float : "bool" in o ? o.bool : o.str;
                        if (val === "[[EMPTY]]") val = "";
                        out[page.keys[i]] = val;
                    } catch (e) {}
                }
                if (!out.accel_profile) out.accel_profile = "adaptive";
                page.v = out;
                page.hasTouchpad = tp;
                page.loaded = true;
            }
        }
    }
    Process {
        id: xkb
        command: ["sh", "-c", "sed -n '/^! layout/,/^! option/p' /usr/share/X11/xkb/rules/evdev.lst"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = {}, vars = {};
                let sec = "";
                for (const line of text.split("\n")) {
                    if (line.startsWith("! ")) { sec = line.slice(2).trim(); continue; }
                    const m = /^\s+(\S+)\s+(.*)$/.exec(line);
                    if (!m) continue;
                    if (sec === "layout") names[m[1]] = m[2];
                    else if (sec === "variant") {
                        const vm = /^(\S+):\s*(.*)$/.exec(m[2]);
                        if (vm) (vars[vm[1]] = vars[vm[1]] || []).push({ code: m[1], desc: vm[2] });
                    }
                }
                page.layoutNames = names;
                page.variants = vars;
                page.layoutCodes = Object.keys(names).sort((a, b) => names[a].localeCompare(names[b]));
            }
        }
    }

    // ---------- writing ----------
    function lua(x) {
        if (typeof x === "boolean") return x ? "true" : "false";
        if (typeof x === "number") return String(Math.round(x * 1000) / 1000);
        return '"' + String(x).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }
    function generate() {
        const top = [], tp = [];
        for (const k of keys) {
            if (!(k in v)) continue;
            if (k.startsWith("touchpad.")) tp.push("            " + k.slice(9) + " = " + lua(v[k]) + ",");
            else top.push("        " + k + " = " + lua(v[k]) + ",");
        }
        return "-- Keyboard, mouse and touchpad. Written by Shell Settings → Keyboard & mouse\n"
             + "-- (edits made here by hand are kept until the next change there).\n"
             + "hl.config({\n    input = {\n" + top.join("\n") + "\n        touchpad = {\n" + tp.join("\n")
             + "\n        },\n    },\n})\n";
    }
    FileView { id: file; path: page.path; blockLoading: true }

    // set one or more keys: update the live compositor + the file
    function set(changes) {
        const nv = {};
        for (const k in v) nv[k] = v[k];
        const top = [], tp = [];
        for (const k in changes) {
            nv[k] = changes[k];
            if (k.startsWith("touchpad.")) tp.push(k.slice(9) + " = " + lua(changes[k]));
            else top.push(k + " = " + lua(changes[k]));
        }
        v = nv;
        if (tp.length) top.push("touchpad = { " + tp.join(", ") + " }");
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { " + top.join(", ") + " } })"]);
        writeLater.restart();
    }
    Timer { id: writeLater; interval: 400; onTriggered: file.setText(page.generate()) }

    function setLayouts(codes, vars) {
        const allEmpty = vars.every(x => !x);
        set({ kb_layout: codes.join(","), kb_variant: allEmpty ? "" : vars.join(",") });
    }
    function moveLayout(i, d) {
        const c = layouts.slice(), w = layoutVariants.slice(), j = i + d;
        if (j < 0 || j >= c.length) return;
        [c[i], c[j]] = [c[j], c[i]]; [w[i], w[j]] = [w[j], w[i]];
        setLayouts(c, w);
    }
    function removeLayout(i) {
        const c = layouts.slice(), w = layoutVariants.slice();
        c.splice(i, 1); w.splice(i, 1);
        if (c.length) setLayouts(c, w);
    }
    function addLayout(code) {
        if (layouts.indexOf(code) >= 0) return;
        setLayouts(layouts.concat([code]), layoutVariants.concat([""]));
    }
    function setVariant(i, code) {
        const w = layoutVariants.slice(); w[i] = code;
        setLayouts(layouts, w);
    }

    // one xkb option out of a group (prefix match), "" = none of them
    function optionIn(group) { return options.find(o => group.some(g => g.value && o === g.value)) || ""; }
    function setOption(group, value) {
        const rest = options.filter(o => !group.some(g => g.value && o === g.value));
        if (value) rest.push(value);
        set({ kb_options: rest.join(",") });
    }
    readonly property var switchKeys: [
        { label: "Alt + Shift",        value: "grp:alt_shift_toggle" },
        { label: "Ctrl + Shift",       value: "grp:ctrl_shift_toggle" },
        { label: "Super + Space",      value: "grp:win_space_toggle" },
        { label: "Caps Lock",          value: "grp:caps_toggle" },
        { label: "Shift + Caps Lock",  value: "grp:shift_caps_toggle" },
        { label: "Both Shift keys",    value: "grp:shifts_toggle" },
        { label: "Right Alt",          value: "grp:toggle" },
        { label: "None",               value: "" }
    ]
    readonly property var capsKeys: [
        { label: "Caps Lock",  value: "" },
        { label: "Escape",     value: "caps:escape" },
        { label: "Ctrl",       value: "ctrl:nocaps" },
        { label: "Backspace",  value: "caps:backspace" },
        { label: "Off",        value: "caps:none" }
    ]
    readonly property var composeKeys: [
        { label: "None",        value: "" },
        { label: "Right Alt",   value: "compose:ralt" },
        { label: "Right Ctrl",  value: "compose:rctrl" },
        { label: "Menu",        value: "compose:menu" },
        { label: "Caps Lock",   value: "compose:caps" }
    ]
    function labelOf(group) { const cur = optionIn(group); const g = group.find(x => x.value === cur); return g ? g.label : group[0].label; }
    function valueOf(group, label) { const g = group.find(x => x.label === label); return g ? g.value : ""; }

    // ===================== Keyboard =====================
    SectionTitle { text: "Keyboard layouts" }

    Repeater {
        model: page.layouts
        delegate: Rectangle {
            id: lr
            required property string modelData
            required property int index
            readonly property var vlist: page.variants[modelData] || []
            Layout.fillWidth: true
            implicitHeight: 60
            radius: Theme.radius
            color: Theme.bg1

            Rectangle {
                id: num
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                width: 30; height: 30; radius: 15
                color: lr.index === 0 ? Theme.yellowDim : Theme.bg2
                Text {
                    anchors.centerIn: parent
                    text: lr.index + 1
                    color: lr.index === 0 ? Theme.bg0 : Theme.fg1
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                }
            }
            Column {
                anchors { left: num.right; leftMargin: 12; right: ctl.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: page.layoutNames[lr.modelData] || lr.modelData
                    color: Theme.fg1
                    font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                }
                Text {
                    text: lr.modelData + (page.layoutVariants[lr.index] ? " · " + page.layoutVariants[lr.index] : "") + (lr.index === 0 ? " · the lock screen types with this one" : "")
                    color: Theme.fg4
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
            }
            Row {
                id: ctl
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 4
                Dropdown {
                    visible: lr.vlist.length > 0
                    implicitWidth: 230
                    model: ["Standard"].concat(lr.vlist.map(x => x.desc))
                    current: { const c = page.layoutVariants[lr.index]; const f = lr.vlist.find(x => x.code === c); return f ? f.desc : "Standard"; }
                    onPicked: (d) => { const f = lr.vlist.find(x => x.desc === d); page.setVariant(lr.index, f ? f.code : ""); }
                }
                RoundIcon { size: 36; anchors.verticalCenter: parent.verticalCenter; icon: "arrow_upward"; enabled: lr.index > 0; onClicked: page.moveLayout(lr.index, -1) }
                RoundIcon { size: 36; anchors.verticalCenter: parent.verticalCenter; icon: "arrow_downward"; enabled: lr.index < page.layouts.length - 1; onClicked: page.moveLayout(lr.index, 1) }
                RoundIcon { size: 36; anchors.verticalCenter: parent.verticalCenter; icon: "close"; enabled: page.layouts.length > 1; onClicked: page.removeLayout(lr.index) }
            }
        }
    }

    SettingRow {
        label: "Add a layout"
        Dropdown {
            model: page.layoutCodes.filter(c => page.layouts.indexOf(c) < 0).map(c => page.layoutNames[c])
            current: "Choose…"
            searchable: true
            onPicked: (d) => { const c = page.layoutCodes.find(x => page.layoutNames[x] === d); if (c) page.addLayout(c); }
        }
    }
    SettingRow {
        label: "Switch layouts with"; hint: "Alt + Shift can also fire while pressing Alt + Shift + Tab"
        Dropdown {
            model: page.switchKeys.map(x => x.label)
            current: page.labelOf(page.switchKeys)
            onPicked: (l) => page.setOption(page.switchKeys, page.valueOf(page.switchKeys, l))
        }
    }

    SectionTitle { text: "Typing"; Layout.topMargin: 14 }

    SettingRow {
        label: "Repeat delay"; hint: "How long to hold a key before it repeats"
        Stepper {
            value: page.v.repeat_delay || 600; min: 150; max: 1500; step: 50; suffix: " ms"; textWidth: 70
            onChanged: (x) => page.set({ repeat_delay: x })
        }
    }
    SettingRow {
        label: "Repeat speed"; hint: "Characters per second while a key is held"
        Stepper {
            value: page.v.repeat_rate || 25; min: 5; max: 80; step: 5; suffix: " /s"; textWidth: 70
            onChanged: (x) => page.set({ repeat_rate: x })
        }
    }
    SettingRow {
        label: "Try it"
        TextBox { placeholder: "Type here to test the repeat and layout" }
    }
    SettingRow {
        label: "Caps Lock key acts as"
        Dropdown {
            model: page.capsKeys.map(x => x.label)
            current: page.labelOf(page.capsKeys)
            onPicked: (l) => page.setOption(page.capsKeys, page.valueOf(page.capsKeys, l))
        }
    }
    SettingRow {
        label: "Compose key"; hint: "Type special characters: Compose, then e.g. ' e → é"
        Dropdown {
            model: page.composeKeys.map(x => x.label)
            current: page.labelOf(page.composeKeys)
            onPicked: (l) => page.setOption(page.composeKeys, page.valueOf(page.composeKeys, l))
        }
    }
    SettingRow {
        label: "Num Lock on at login"
        Toggle { checked: !!page.v.numlock_by_default; onToggled: (x) => page.set({ numlock_by_default: x }) }
    }

    // ===================== Mouse =====================
    SectionTitle { text: "Mouse"; Layout.topMargin: 14 }

    SettingRow {
        label: "Pointer speed"
        ValueSlider {
            from: -1; to: 1; step: 0.05; mark: 0
            value: page.v.sensitivity || 0
            valueText: (value > 0 ? "+" : "") + Math.round(value * 100)
            onMoved: (x) => page.set({ sensitivity: x })
        }
    }
    SettingRow {
        label: "Pointer acceleration"; hint: "Off moves the pointer the same distance at any speed (good for games)"
        Toggle { checked: page.v.accel_profile !== "flat"; onToggled: (x) => page.set({ accel_profile: x ? "adaptive" : "flat" }) }
    }
    SettingRow {
        label: "Scroll speed"
        ValueSlider {
            from: 0.2; to: 3; step: 0.1; mark: 1
            value: page.v.scroll_factor || 1
            valueText: value.toFixed(1) + "×"
            onMoved: (x) => page.set({ scroll_factor: x })
        }
    }
    SettingRow {
        label: "Natural scrolling"; hint: "Content follows the wheel, like on a phone"
        Toggle { checked: !!page.v.natural_scroll; onToggled: (x) => page.set({ natural_scroll: x }) }
    }
    SettingRow {
        label: "Left-handed"; hint: "Swap the left and right buttons"
        Toggle { checked: !!page.v.left_handed; onToggled: (x) => page.set({ left_handed: x }) }
    }
    SettingRow {
        label: "Focus follows the pointer"; hint: "Off: click a window to type in it"
        Toggle { checked: page.v.follow_mouse !== 0; onToggled: (x) => page.set({ follow_mouse: x ? 1 : 0 }) }
    }

    // ===================== Touchpad (laptops) =====================
    SectionTitle { visible: page.hasTouchpad; text: "Touchpad"; Layout.topMargin: 14 }

    SettingRow {
        visible: page.hasTouchpad
        label: "Tap to click"
        Toggle { checked: !!page.v["touchpad.tap_to_click"]; onToggled: (x) => page.set({ "touchpad.tap_to_click": x }) }
    }
    SettingRow {
        visible: page.hasTouchpad
        label: "Natural scrolling"
        Toggle { checked: !!page.v["touchpad.natural_scroll"]; onToggled: (x) => page.set({ "touchpad.natural_scroll": x }) }
    }
    SettingRow {
        visible: page.hasTouchpad
        label: "Off while typing"
        Toggle { checked: !!page.v["touchpad.disable_while_typing"]; onToggled: (x) => page.set({ "touchpad.disable_while_typing": x }) }
    }
    SettingRow {
        visible: page.hasTouchpad
        label: "Scroll speed"
        ValueSlider {
            from: 0.2; to: 3; step: 0.1; mark: 1
            value: page.v["touchpad.scroll_factor"] || 1
            valueText: value.toFixed(1) + "×"
            onMoved: (x) => page.set({ "touchpad.scroll_factor": x })
        }
    }
}
