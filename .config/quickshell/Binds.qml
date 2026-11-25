pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Every Hyprland key binding, read live from `hyprctl binds -j` and grouped by
// the bind's description ("Group: what it does", set in ~/.config/hypr/hyprland.lua).
// Used by Settings → Shortcuts and the shortcuts popup (ShortcutsHelp.qml).
Singleton {
    id: root

    property var groups: []          // [{ name, rows: [{ text, combos: [[keys…]] }] }]
    readonly property var order: ["Shell", "Apps", "Windows", "Workspaces", "Screenshots", "Media", "Session"]

    function load() { read.running = true; }
    Process {
        id: read
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { root.build(JSON.parse(text)); } catch (e) {} } }
    }

    function mods(mask) {
        const out = [];
        if (mask & 64) out.push("Super");
        if (mask & 4) out.push("Ctrl");
        if (mask & 8) out.push("Alt");
        if (mask & 1) out.push("Shift");
        return out;
    }
    function keyName(k) {
        const map = {
            "Super_L": "", "Return": "Enter", "grave": "`", "slash": "/", "Page_Down": "Page Down", "Page_Up": "Page Up",
            "Print": "Print Screen", "mouse:272": "Left drag", "mouse:273": "Right drag",
            "mouse_down": "Scroll down", "mouse_up": "Scroll up", "left": "←", "right": "→", "up": "↑", "down": "↓",
            "Escape": "Esc", "XF86PowerOff": "Power button"
        };
        if (k in map) return map[k];
        if (k.startsWith("XF86")) return k.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2") + " key";
        return k.length === 1 ? k.toUpperCase() : k;
    }
    function combo(b) {
        const c = mods(b.modmask);
        const k = keyName(b.key);
        if (k) c.push(k);
        else if (b.release) c[c.length - 1] += " (tap)";
        return c;
    }

    function build(binds) {
        const byGroup = {};
        for (const b of binds) {
            const d = b.description || "";
            const m = /^([^:]+):\s*(.*)$/.exec(d);
            const g = m ? m[1] : "Other";
            let text = m ? m[2] : (d || b.dispatcher.replace(/^HL\.Dispatcher\((.*)\)$/, "$1"));
            // "Go to workspace 3" … collapse numbered rows into one
            const num = /^(.*?)(\d+)$/.exec(text);
            const keyText = num ? num[1] + "#" : text;
            const grp = byGroup[g] = byGroup[g] || { name: g, rows: [], index: {} };
            let row = grp.index[keyText];
            if (!row) { row = grp.index[keyText] = { text: text, nums: [], combos: [] }; grp.rows.push(row); }
            if (num) row.nums.push(parseInt(num[2]));
            row.combos.push(combo(b));
        }
        const out = [];
        const names = Object.keys(byGroup).sort((a, b) => {
            const ia = order.indexOf(a), ib = order.indexOf(b);
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b);
        });
        for (const n of names) {
            const rows = byGroup[n].rows.map(r => {
                if (r.nums.length > 2) {
                    const lo = Math.min(...r.nums), hi = Math.max(...r.nums);
                    const first = r.combos[0].slice(0, -1);
                    return { text: r.text.replace(/\d+$/, lo + "–" + hi),
                             combos: [first.concat([r.combos[0][r.combos[0].length - 1] + " … " + r.combos[r.combos.length - 1][r.combos[0].length - 1]])] };
                }
                return { text: r.text, combos: r.combos };
            });
            out.push({ name: n, rows: rows });
        }
        groups = out;
    }

    // search: matches the description or the keys
    function matches(row, query) {
        if (!query) return true;
        return (row.text + " " + row.combos.map(c => c.join(" ")).join(" ")).toLowerCase().indexOf(query) >= 0;
    }
}
