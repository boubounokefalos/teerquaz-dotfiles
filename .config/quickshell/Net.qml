pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// NetworkManager state for the bar icon, its menu and Settings → Network.
// Everything goes through nmcli; `nmcli monitor` triggers a re-read on any change.
Singleton {
    id: net

    property var devices: []        // [{ name, type, state, connection, uuid }] (no loopback/bridges)
    property var profiles: []       // [{ name, uuid, type, device, autoconnect, active }]
    property string connectivity: "unknown"   // full | limited | portal | none | unknown
    property bool networking: true
    property bool wifiEnabled: false
    property var wifiList: []       // [{ ssid, signal, security, inUse }]
    property var details: ({})      // primary device: mac, ip4, gateway, dns, ip6, speed
    property string lastError: ""

    // device the icon is about: first connected one, else the first one we have
    readonly property var primary: {
        for (const d of devices) if (d.state === "connected") return d;
        for (const d of devices) if (d.state.startsWith("connecting")) return d;
        return devices.length ? devices[0] : null;
    }
    readonly property bool hasWifi: devices.some(d => d.type === "wifi")
    readonly property bool connected: primary !== null && primary.state === "connected"
    readonly property bool connecting: primary !== null && primary.state.startsWith("connecting")
    readonly property bool isWifi: primary !== null && primary.type === "wifi"
    readonly property int wifiSignal: {
        for (const w of wifiList) if (w.inUse) return w.signal;
        return 0;
    }
    readonly property string icon: {
        if (!networking || !primary) return "signal_disconnected";
        if (isWifi) {
            if (!connected) return connecting ? "network_wifi_1_bar" : "signal_wifi_off";
            if (connectivity !== "full") return "signal_wifi_statusbar_not_connected";
            return wifiSignal > 75 ? "signal_wifi_4_bar" : wifiSignal > 50 ? "network_wifi_3_bar"
                 : wifiSignal > 25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
        }
        return connected || connecting ? "lan" : "signal_disconnected";
    }
    readonly property string statusText: {
        if (!networking) return "Networking off";
        if (!primary) return "No network device";
        if (connecting) return "Connecting…";
        if (!connected) return "Disconnected";
        if (connectivity === "portal") return "Sign-in needed";
        if (connectivity === "limited" || connectivity === "none") return "No internet";
        return "Connected";
    }
    readonly property string title: primary && primary.connection ? primary.connection
                                  : (primary ? (primary.type === "wifi" ? "Wi-Fi" : "Wired") : "Network")

    // ---------- reading ----------
    // split a terse nmcli line on unescaped ':' and unescape \: and \\
    function fields(line) {
        const out = []; let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function refresh() { if (!reader.running) reader.running = true; else again = true; }
    property bool again: false

    Process {
        id: reader
        command: ["sh", "-c", `
            nmcli -t networking | sed 's/^/G\\t/'
            nmcli -t networking connectivity | sed 's/^/N\\t/'
            nmcli -t radio wifi | sed 's/^/R\\t/'
            nmcli -t -f DEVICE,TYPE,STATE,CONNECTION,CON-UUID dev | sed 's/^/D\\t/'
            nmcli -t -f NAME,UUID,TYPE,DEVICE,AUTOCONNECT,ACTIVE con show | sed 's/^/C\\t/'
            dev=$(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: '($2=="ethernet"||$2=="wifi") && $3=="connected" {print $1; exit}')
            [ -n "$dev" ] || dev=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2=="ethernet"||$2=="wifi" {print $1; exit}')
            [ -n "$dev" ] && nmcli -t -f GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,CAPABILITIES.SPEED dev show "$dev" | sed 's/^/I\\t/'
            nmcli -t -f TYPE dev | grep -qx wifi && nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no | sed 's/^/W\\t/'
            true
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const devs = [], profs = [], wl = [], det = { ip4: [], dns: [], ip6: [] };
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const tag = line.slice(0, tab), rest = line.slice(tab + 1);
                    if (tag === "G") net.networking = rest === "enabled";
                    else if (tag === "N") net.connectivity = rest;
                    else if (tag === "R") net.wifiEnabled = rest === "enabled";
                    else if (tag === "D") {
                        const f = net.fields(rest);
                        if (f[1] !== "ethernet" && f[1] !== "wifi") continue;
                        devs.push({ name: f[0], type: f[1], state: f[2], connection: f[3] || "", uuid: f[4] || "" });
                    } else if (tag === "C") {
                        const f = net.fields(rest);
                        if (f[2] === "loopback") continue;
                        profs.push({ name: f[0], uuid: f[1], type: f[2], device: f[3] || "", autoconnect: f[4] === "yes", active: f[5] === "yes" });
                    } else if (tag === "I") {
                        const f = net.fields(rest), k = f[0], v = f.slice(1).join(":");
                        if (!v || v === "--") continue;
                        if (k === "GENERAL.HWADDR") det.mac = v;
                        else if (k.startsWith("IP4.ADDRESS")) det.ip4.push(v);
                        else if (k === "IP4.GATEWAY") det.gateway = v;
                        else if (k.startsWith("IP4.DNS")) det.dns.push(v);
                        else if (k.startsWith("IP6.ADDRESS")) det.ip6.push(v);
                        else if (k === "CAPABILITIES.SPEED") det.speed = v;
                    } else if (tag === "W") {
                        const f = net.fields(rest);
                        if (!f[1]) continue;   // hidden network
                        // same SSID from several access points: keep the strongest / the one in use
                        const w = { ssid: f[1], signal: parseInt(f[2]) || 0, security: f[3] && f[3] !== "--" ? f[3] : "", inUse: f[0] === "*" };
                        const i = wl.findIndex(x => x.ssid === w.ssid);
                        if (i < 0) wl.push(w);
                        else if (w.inUse || (!wl[i].inUse && w.signal > wl[i].signal)) wl[i] = w;
                    }
                }
                net.devices = devs;
                net.profiles = profs;
                net.details = det;
                net.wifiList = wl.sort((a, b) => (b.inUse - a.inUse) || (b.signal - a.signal));
            }
        }
        onExited: if (net.again) { net.again = false; running = true; }
    }

    // any NetworkManager change -> re-read (debounced)
    Process {
        id: monitor
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: debounce.restart() }
        onExited: restartMonitor.start()
    }
    Timer { id: restartMonitor; interval: 3000; onTriggered: monitor.running = true }
    Timer { id: debounce; interval: 300; onTriggered: net.refresh() }
    // connectivity is re-checked by NM every few minutes without a monitor line
    Timer { interval: 60000; repeat: true; running: true; onTriggered: net.refresh() }
    Component.onCompleted: refresh()

    // ---------- traffic (only while something shows it) ----------
    property int rateUsers: 0
    property real rxRate: 0     // bytes / s
    property real txRate: 0
    property real lastRx: -1
    property real lastTx: -1
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: net.rateUsers > 0 && net.primary !== null
        onRunningChanged: if (!running) { net.lastRx = -1; net.rxRate = 0; net.txRate = 0; }
        onTriggered: if (!stats.running) {
            stats.command = ["cat", "/sys/class/net/" + net.primary.name + "/statistics/rx_bytes",
                                    "/sys/class/net/" + net.primary.name + "/statistics/tx_bytes"];
            stats.running = true;
        }
    }
    Process {
        id: stats
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("\n").map(Number);
                if (p.length < 2) return;
                if (net.lastRx >= 0) { net.rxRate = Math.max(0, p[0] - net.lastRx); net.txRate = Math.max(0, p[1] - net.lastTx); }
                net.lastRx = p[0]; net.lastTx = p[1];
            }
        }
    }
    function rate(b) {
        if (b < 1024) return Math.round(b) + " B/s";
        if (b < 1024 * 1024) return (b / 1024).toFixed(b < 10240 ? 1 : 0) + " KB/s";
        return (b / 1048576).toFixed(1) + " MB/s";
    }

    // ---------- actions ----------
    // queue of nmcli commands; stderr of a failing one ends up in lastError
    property var queue: []
    function run(args) { queue = queue.concat([args]); if (!actor.running) next(); }
    function next() {
        if (!queue.length) return;
        actor.command = queue[0];
        queue = queue.slice(1);
        actor.running = true;
    }
    Process {
        id: actor
        stderr: StdioCollector { id: actorErr }
        onExited: (code) => {
            if (code !== 0) {
                net.lastError = actorErr.text.trim().replace(/^Error:\s*/, "") || ("nmcli failed (" + code + ")");
                Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "error", "Network: " + net.lastError.split("\n")[0]]);
            }
            net.refresh();
            net.next();
        }
    }

    function connectDevice(dev)    { lastError = ""; run(["nmcli", "device", "connect", dev]); }
    function disconnectDevice(dev) { lastError = ""; run(["nmcli", "device", "disconnect", dev]); }
    function up(uuid)              { lastError = ""; run(["nmcli", "connection", "up", "uuid", uuid]); }
    function down(uuid)            { lastError = ""; run(["nmcli", "connection", "down", "uuid", uuid]); }
    function setNetworking(on)     { lastError = ""; run(["nmcli", "networking", on ? "on" : "off"]); }
    function setWifi(on)           { lastError = ""; run(["nmcli", "radio", "wifi", on ? "on" : "off"]); }
    function rescan()              { run(["nmcli", "device", "wifi", "rescan"]); }
    function connectWifi(ssid, password) {
        lastError = "";
        const known = profiles.find(p => p.type === "802-11-wireless" && p.name === ssid);
        if (known && !password) run(["nmcli", "connection", "up", "uuid", known.uuid]);
        else run(password ? ["nmcli", "device", "wifi", "connect", ssid, "password", password]
                          : ["nmcli", "device", "wifi", "connect", ssid]);
    }
    function forget(uuid)          { lastError = ""; run(["nmcli", "connection", "delete", "uuid", uuid]); }
    function setAutoconnect(uuid, on) { lastError = ""; run(["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", on ? "yes" : "no"]); }
    // ipv4: { method: "auto"|"manual", addresses, gateway, dns }  (dns space/comma separated)
    function setIpv4(uuid, v, reapply) {
        lastError = "";
        const dns = (v.dns || "").split(/[\s,]+/).filter(x => x).join(",");
        if (v.method === "manual")
            run(["nmcli", "connection", "modify", "uuid", uuid, "ipv4.method", "manual",
                 "ipv4.addresses", v.addresses, "ipv4.gateway", v.gateway || "", "ipv4.dns", dns]);
        else
            run(["nmcli", "connection", "modify", "uuid", uuid, "ipv4.method", "auto",
                 "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", dns]);
        if (reapply) run(["nmcli", "connection", "up", "uuid", uuid]);
    }
}
