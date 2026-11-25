pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Removable drives (USB sticks, SD cards, external disks) through udisks2:
// `udisksctl monitor` says when something changes, `lsblk -J` gives the list.
// A newly plugged drive is mounted (Config.autoMount) and announced with a
// notification (Open / Eject); the bar shows an icon + menu while any is in.
Singleton {
    id: root

    // [{ path, disk, name, size, fstype, mountpoint, model }]
    property var drives: []
    readonly property bool any: drives.length > 0
    property var known: ({})          // path -> true, seen at the last refresh
    property bool first: true
    property var pending: ({})        // path -> true, mounted by us, waiting to announce

    readonly property string scripts: Quickshell.shellDir + "/scripts"

    function refresh() { list.running = true; }

    function displayName(d) {
        if (d.label) return d.label;
        const m = (d.model || "").trim();
        return (m ? m : "Drive") + (d.size ? " (" + d.size + ")" : "");
    }

    function open(d) {
        if (d.mountpoint) { Quickshell.execDetached(["xdg-open", d.mountpoint]); return; }
        mountThen(d, true);
    }
    function eject(d) {
        Quickshell.execDetached([scripts + "/drive-eject.sh", d.disk, displayName(d)]);
        Qt.callLater(refresh);
    }
    // one eject per disk (a disk with several partitions is ejected once)
    function ejectAll() {
        const disks = [];
        for (const d of drives) if (disks.indexOf(d.disk) < 0) { disks.push(d.disk); eject(d); }
    }
    function ejectDisk(disk) {
        const d = drives.find(x => x.disk === disk);
        if (d) eject(d);
    }

    // mount, then announce (or open straight away)
    function mountThen(d, openAfter) {
        const p = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        p.command = ["udisksctl", "mount", "--no-user-interaction", "-b", d.path];
        p.exited.connect((code) => {
            p.destroy();
            if (code !== 0) {
                Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "error", "Couldn't open " + displayName(d)]);
                return;
            }
            if (openAfter) {
                const w = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
                w.command = ["sh", "-c", "xdg-open \"$(lsblk -no MOUNTPOINT " + JSON.stringify(d.path) + " | head -1)\""];
                w.exited.connect(() => w.destroy());
                w.running = true;
            } else {
                const pd = Object.assign({}, root.pending); pd[d.path] = true; root.pending = pd;
            }
            refresh();
        });
        p.running = true;
    }

    Process {
        id: list
        command: ["lsblk", "-J", "-o", "NAME,PATH,LABEL,SIZE,FSTYPE,MOUNTPOINT,HOTPLUG,MODEL,TYPE"]
        stdout: StdioCollector {
            onStreamFinished: {
                let tree;
                try { tree = JSON.parse(text).blockdevices || []; } catch (e) { return; }
                const out = [];
                for (const disk of tree) {
                    if (!disk.hotplug || disk.type !== "disk") continue;
                    const parts = (disk.children || []).filter(c => c.fstype && c.fstype !== "swap");
                    // a stick formatted without a partition table
                    if (!parts.length && disk.fstype && disk.fstype !== "swap") parts.push(disk);
                    for (const p of parts)
                        out.push({ path: p.path, disk: disk.path, label: p.label || "", size: p.size || "",
                                   fstype: p.fstype, mountpoint: p.mountpoint || "", model: disk.model || "" });
                }
                for (const d of out) d.name = root.displayName(d);

                const now = {};
                for (const d of out) {
                    now[d.path] = true;
                    if (root.first || root.known[d.path]) continue;
                    // newly plugged in
                    if (!d.mountpoint && Config.autoMount && d.fstype !== "crypto_LUKS") root.mountThen(d, false);
                    else if (!d.mountpoint) Quickshell.execDetached(["notify-send", "-a", "Drives", "-i", "drive-removable-media",
                                                                    d.name + " plugged in", "Open it from the drive icon in the bar."]);
                }
                // announce drives we just mounted, now that their mountpoint is known
                const pd = Object.assign({}, root.pending);
                for (const d of out) {
                    if (pd[d.path] && d.mountpoint) {
                        delete pd[d.path];
                        Quickshell.execDetached([root.scripts + "/drive-notify.sh", d.name, d.mountpoint, d.disk]);
                    }
                }
                root.pending = pd;
                root.known = now;
                root.first = false;
                root.drives = out;
            }
        }
    }

    // udisks events → re-read (debounced: one plug-in fires many)
    Process {
        running: true
        command: ["udisksctl", "monitor"]
        stdout: SplitParser { onRead: () => debounce.restart() }
    }
    Timer { id: debounce; interval: 600; onTriggered: root.refresh() }
    Component.onCompleted: refresh()

    //   qs ipc call drives refresh | ejectAll
    IpcHandler {
        target: "drives"
        function refresh(): void { root.refresh(); }
        function ejectAll(): void { root.ejectAll(); }
    }
}
