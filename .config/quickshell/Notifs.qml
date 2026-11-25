pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Io

// Notification server (replaces mako). Everything received stays in the
// history (quick settings) until dismissed; popups are a separate, short list.
Singleton {
    id: root

    readonly property var history: server.trackedNotifications.values.slice().reverse()
    readonly property int count: server.trackedNotifications.values.length
    property alias popups: popupModel
    property var arrived: ({})          // id -> Date received

    ListModel { id: popupModel }

    function iconFor(n) {
        const icon = n.appIcon || "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.indexOf("://") >= 0) return icon;
        if (icon) return Quickshell.iconPath(icon, true);
        return n.desktopEntry ? Quickshell.iconPath(n.desktopEntry, true) : "";
    }

    function age(id) {
        const t = arrived[id];
        if (!t) return "";
        const m = Math.floor((Date.now() - t) / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + " min ago";
        const h = Math.floor(m / 60);
        return h < 24 ? h + " h ago" : Qt.formatDateTime(t, "d MMM");
    }

    function find(id) {
        const list = server.trackedNotifications.values;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return null;
    }

    function dropPopup(id) {
        for (let i = 0; i < popupModel.count; i++)
            if (popupModel.get(i).nid === id) { popupModel.remove(i); return; }
    }

    // popup timed out: hide it, keep it in the history (unless transient)
    function timeout(n) {
        dropPopup(n.id);
        if (n.transient) n.expire();
    }

    function activate(n) {
        const acts = n.actions;
        for (let i = 0; i < acts.length; i++)
            if (acts[i].identifier === "default") { acts[i].invoke(); break; }
        n.dismiss();
    }

    function clearAll() {
        const list = server.trackedNotifications.values.slice();
        for (const n of list) n.dismiss();
        popupModel.clear();
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            // per-app rule from Settings → Notifications
            const app = n.appName || "";
            if (app && Config.notifApps.indexOf(app) < 0)
                Config.notifApps = Config.notifApps.concat([app]).sort((a, b) => a.localeCompare(b));
            const rule = Config.notifRules[app] || "";
            if (rule === "off" && !n.lastGeneration) { n.dismiss(); return; }

            n.tracked = true;
            const a = Object.assign({}, root.arrived); a[n.id] = Date.now(); root.arrived = a;
            n.closed.connect(() => root.dropPopup(n.id));

            // carried over from before a shell reload: back into the history only
            if (n.lastGeneration) return;

            const urgent = n.urgency === NotificationUrgency.Critical;
            if (ShellState.doNotDisturb && !urgent) return;
            if (rule === "silent" && !urgent) return;      // history only
            root.dropPopup(n.id);                 // a replaced notification moves to the top
            popupModel.insert(0, { nid: n.id });
            while (popupModel.count > 5) popupModel.remove(popupModel.count - 1);
        }
    }

    //   qs ipc call notifications clear | dnd
    IpcHandler {
        target: "notifications"
        function clear(): void { root.clearAll(); }
        function dnd(): void { ShellState.doNotDisturb = !ShellState.doNotDisturb; }
    }

    // refresh "n min ago" labels
    property int tick: 0
    Timer { interval: 30000; repeat: true; running: true; onTriggered: root.tick++ }
}
