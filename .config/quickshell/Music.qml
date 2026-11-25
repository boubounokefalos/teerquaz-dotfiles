import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Music player: the shell's own window for the music folder (xdg MUSIC dir,
// ~/Music). Playback runs in a background mpv (no window, own config) that this
// window drives over mpv's JSON IPC socket. mpv is started detached, so music
// keeps playing when the window is closed or the shell reloads; it shows up in
// the quick settings media card and answers media keys through mpv-mpris.
// While Hyprland floats the window it turns into a small mini player. The bar's
// song pill drops the same mini player down under the bar (like quick settings).
//   qs ipc call music open | toggle | lyrics | mini | drop | playFiles <paths, one per line> | playPause | next | previous
FloatingWindow {
    id: win
    visible: false
    title: "Music"
    color: Theme.bg0
    implicitWidth: mini ? miniW : 1000
    implicitHeight: mini ? miniH : 640
    minimumSize: mini ? Qt.size(400, 180) : Qt.size(780, 500)

    // ---------- floating = mini player ----------
    readonly property int miniW: 480
    readonly property int miniH: 196
    property string hyprAddr: ""      // without 0x
    property bool floating: false
    readonly property bool mini: floating
    property bool toCorner: false     // mini button: also park it bottom-right
    property bool wantMini: false     // asked for before the window had an address
    property bool wantFull: false     // drop-down's expand button: open the full (tiled) window
    function hypr(cmd) { Hyprland.dispatch(cmd.replace("WIN", '"address:0x' + hyprAddr + '"')); }
    Process {
        id: clientsProc
        command: ["sh", "-c", "hyprctl -j clients; echo; echo @@; hyprctl -j monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n@@\n");
                let cs = [], ms = [];
                try { cs = JSON.parse(parts[0]); ms = JSON.parse(parts[1]); } catch (e) { return; }
                const c = cs.find(x => x.class === "org.quickshell" && x.title === "Music" && x.mapped);
                if (!c) return;
                win.hyprAddr = c.address.replace(/^0x/, "");
                win.monitorInfo = ms.find(m => m.id === c.monitor) || null;
                if (win.wantMini && !c.floating) { win.wantMini = false; win.hypr("hl.dsp.window.float({ window = WIN, action = \"enable\" })"); return; }
                win.wantMini = false;
                if (win.wantFull && c.floating) { win.wantFull = false; win.goFull(); return; }
                win.wantFull = false;
                win.setFloating(c.floating, c.size);
            }
        }
    }
    property var monitorInfo: null
    function refreshClient() { if (visible && !clientsProc.running) clientsProc.running = true; }
    function setFloating(f, size) {
        const was = floating;
        floating = f;
        if (!f || (was && !toCorner)) return;
        if (size && size[0] === miniW && size[1] === miniH && !toCorner) return;
        Qt.callLater(fitMini);
    }
    function fitMini() {
        if (!hyprAddr) return;
        hypr("hl.dsp.window.resize({ window = WIN, x = " + miniW + ", y = " + miniH + " })");
        const m = monitorInfo;
        if (toCorner && m) {
            const sc = m.scale > 0 ? m.scale : 1, r = m.reserved || [0, 0, 0, 0], gap = 16;
            const x = m.x + m.width / sc - r[2] - gap - miniW;
            const y = m.y + m.height / sc - r[3] - gap - miniH;
            hypr("hl.dsp.window.move({ window = WIN, x = " + Math.round(x) + ", y = " + Math.round(y) + " })");
        } else {
            hypr("hl.dsp.window.center({ window = WIN })");
        }
        toCorner = false;
    }
    function goMini() {
        if (!visible) open();
        toCorner = true;
        if (!hyprAddr) { wantMini = true; return; }
        if (floating) fitMini();
        else hypr("hl.dsp.window.float({ window = WIN, action = \"enable\" })");
    }
    function toggleDrop() { drop.toggle(); }
    function openFull() {
        drop.hide();
        if (visible && floating) { goFull(); return; }
        if (!visible) { wantFull = true; open(); }
    }
    function goFull() { hypr("hl.dsp.window.float({ window = WIN, action = \"disable\" })"); }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "changefloatingmode") {
                const d = ev.data.split(",");
                if (d[0] === win.hyprAddr) win.setFloating(d[1] === "1", null);
                else if (!win.hyprAddr) win.refreshClient();
            } else if (ev.name === "openwindow" || ev.name === "movewindowv2") win.refreshClient();
        }
    }
    onVisibleChanged: if (visible) clientDelay.restart(); else { floating = false; hyprAddr = ""; }
    Timer { id: clientDelay; interval: 120; onTriggered: win.refreshClient() }

    // ---------- library ----------
    property var tracks: []           // [{ path, title, artist, album, duration, art, mtime }]
    property var byPath: ({})
    property bool scanning: false
    property string musicDir: ""
    property string query: ""
    property int tab: 0               // 0 library, 1 queue, 2 lyrics

    readonly property var sortKeys: ["name", "artist", "title", "added"]
    readonly property var sortLabels: ["File name", "Artist", "Title", "Recently added"]

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        let list = tracks.filter(t => !q || (t.title + "\n" + t.artist + "\n" + t.album).toLowerCase().indexOf(q) >= 0);
        const by = (a, b) => a.localeCompare(b, undefined, { sensitivity: "base" });
        if (Config.musicSort === "artist") list.sort((a, b) => by(a.artist, b.artist) || by(a.title, b.title));
        else if (Config.musicSort === "title") list.sort((a, b) => by(a.title, b.title));
        else if (Config.musicSort === "added") list.sort((a, b) => b.mtime - a.mtime);
        return list;
    }

    Process {
        id: scan
        command: ["sh", "-c", 'd=$(xdg-user-dir MUSIC 2>/dev/null); [ -n "$d" ] && [ "$d" != "$HOME" ] || d="$HOME/Music"; echo "$d"; exec python3 "$1" "$d"',
                  "sh", Quickshell.shellDir + "/scripts/music-scan.py"]
        onStarted: win.scanning = true
        stdout: StdioCollector {
            onStreamFinished: {
                win.scanning = false;
                const nl = text.indexOf("\n");
                win.musicDir = text.slice(0, nl);
                try {
                    const t = JSON.parse(text.slice(nl + 1));
                    const m = {};
                    for (const x of t) m[x.path] = x;
                    win.byPath = m;
                    win.tracks = t;
                } catch (e) { console.warn("music scan:", e); }
            }
        }
    }

    // ---------- mpv ----------
    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-music.sock"
    property bool paused: true
    property bool idle: true
    property real pos: 0
    property real dur: 0
    property string path: ""
    property real volume: Config.musicVolume
    property bool muted: false
    property var playlist: []         // [{ filename, current }]
    property var pending: []          // commands waiting for the socket
    readonly property var current: path ? (byPath[path] || outsideTrack(path)) : null
    // a file opened from outside the library: "Artist - Title.mp3" → artist + title
    function outsideTrack(p) {
        const stem = p.split("/").pop().replace(/\.[^.]+$/, "");
        const i = stem.indexOf(" - ");
        const left = i > 0 ? stem.slice(0, i).trim() : "";
        const num = /^\d+$/.test(left);
        return { path: p, title: i > 0 && !num ? stem.slice(i + 3).trim() : stem, artist: i > 0 && !num ? left : "", album: "", art: "", duration: 0 };
    }
    readonly property bool playing: !idle && !paused && path !== ""
    readonly property int queueIndex: { for (let i = 0; i < playlist.length; i++) if (playlist[i].current) return i; return -1; }

    function send(arr, reqId) {
        const o = { command: arr };
        if (reqId !== undefined) o.request_id = reqId;
        sock.write(JSON.stringify(o) + "\n");
        sock.flush();
    }
    function cmd(arr) {
        if (sock.connected) { send(arr); return; }
        pending = pending.concat([arr]);
        startMpv();
    }
    function startMpv() {
        if (retry.running) return;
        Quickshell.execDetached(["mpv", "--no-config", "--idle=yes", "--no-video", "--no-terminal",
            "--script=/etc/mpv/scripts/mpris.so", "--input-ipc-server=" + sockPath,
            "--volume=" + Config.musicVolume, "--title=Music", "--audio-client-name=Music"]);
        retry.tries = 0;
        retry.start();
    }
    function applyRepeat() {
        const r = Config.musicRepeat;
        cmd(["set_property", "loop-file", r === "one" ? "inf" : "no"]);
        cmd(["set_property", "loop-playlist", r === "all" ? "inf" : "no"]);
    }

    Socket {
        id: sock
        path: win.sockPath
        parser: SplitParser {
            onRead: (line) => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.request_id === 100 && m.error === "success") { win.pos = m.data; return; }
                if (m.event !== "property-change") return;
                const d = m.data;
                switch (m.name) {
                case "pause": win.paused = !!d; break;
                case "idle-active": win.idle = !!d; break;
                case "duration": win.dur = d || 0; break;
                case "path": win.path = d || ""; win.pos = 0; if (d) win.send(["get_property", "time-pos"], 100); break;
                case "volume": if (d !== undefined && d !== null) win.volume = d; break;
                case "mute": win.muted = !!d; break;
                case "playlist": win.playlist = d || []; break;
                case "time-pos": if (d !== null && d !== undefined) win.pos = d; break;
                }
            }
        }
        onConnectedChanged: {
            if (!connected) { win.idle = true; win.path = ""; win.playlist = []; return; }
            retry.stop();
            const props = ["pause", "idle-active", "duration", "path", "volume", "mute", "playlist"];
            for (let i = 0; i < props.length; i++) win.send(["observe_property", i + 1, props[i]]);
            win.applyRepeat();
            const p = win.pending; win.pending = [];
            for (const c of p) win.send(c);
            win.send(["get_property", "time-pos"], 100);
        }
        onError: connected = false
    }
    Timer {   // wait for a freshly started mpv to open its socket
        id: retry
        property int tries: 0
        interval: 150; repeat: true
        onTriggered: {
            if (sock.connected || ++tries > 40) { stop(); return; }
            sock.connected = false; sock.connected = true;
        }
    }
    Timer {   // time-pos is polled, not observed (it changes every audio frame)
        interval: win.tab === 2 ? 150 : 250; repeat: true
        running: (win.visible || drop.visible || ShellState.locked) && sock.connected && win.playing
        onTriggered: win.send(["get_property", "time-pos"], 100)
    }
    Timer {   // save volume once dragging stops
        id: saveVol
        interval: 600
        onTriggered: Config.musicVolume = Math.round(win.volume)
    }
    Component.onCompleted: { sock.connected = true; scan.running = true; }   // pick up an mpv that kept playing

    // ---------- lyrics ----------
    // scripts/music-lyrics.py: Song.lrc next to the file, then tags, then lrclib.net (cached).
    property var lyrics: null         // { synced: [[sec, line]], plain, source, instrumental, error? }
    property var lyrWant: null        // { key, args }
    readonly property bool lyricsLoading: lyrWant !== null && (lyrics === null || lyrics.key !== lyrWant.key)
    readonly property var synced: lyrics && lyrics.synced ? lyrics.synced : []
    readonly property int lyricLine: {
        const s = synced, p = pos + 0.25;      // a touch early, so the line is lit as it starts
        if (!s.length || p < s[0][0]) return -1;
        let lo = 0, hi = s.length - 1;
        while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (s[mid][0] <= p) lo = mid; else hi = mid - 1; }
        return lo;
    }
    onCurrentChanged: loadLyrics(false)
    readonly property string lyricText: lyricLine >= 0 && !lyricsLoading ? synced[lyricLine][1] : ""
    // for the lock screen
    Binding { target: ShellState; property: "musicLyric"; value: win.playing ? win.lyricText : "" }
    Binding { target: ShellState; property: "musicPlaying"; value: win.playing }
    Connections {
        target: ShellState
        function onToggleMusicMini() { drop.toggle(); }
    }
    Binding { target: ShellState; property: "musicTrack"; value: win.current && !win.idle ? { title: win.current.title, artist: win.current.artist } : null }
    function loadLyrics(refresh) {
        const c = current;
        if (!c) { lyrWant = null; lyrics = null; return; }
        const key = c.path + "\n" + c.artist + "\n" + c.title;
        if (!refresh && lyrWant && lyrWant.key === key) return;
        lyrWant = { key: key, args: [c.path, c.artist, c.title, c.album || "", String(c.duration || dur || 0)].concat(refresh ? ["--refresh"] : []) };
        if (!lyr.running) startLyrics();
    }
    function startLyrics() {
        lyr.forKey = lyrWant.key;
        lyr.command = ["python3", Quickshell.shellDir + "/scripts/music-lyrics.py"].concat(lyrWant.args);
        lyr.running = true;
    }
    Process {
        id: lyr
        property string forKey: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (!win.lyrWant || lyr.forKey !== win.lyrWant.key) return;
                try { const r = JSON.parse(text); r.key = lyr.forKey; win.lyrics = r; }
                catch (e) { win.lyrics = { key: lyr.forKey, synced: [], plain: "", source: "", error: "lyrics script failed" }; }
            }
        }
        onExited: if (win.lyrWant && win.lyrWant.key !== lyr.forKey) win.startLyrics()
    }

    // ---------- actions ----------
    function shuffled(a) {
        a = a.slice();
        for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); const t = a[i]; a[i] = a[j]; a[j] = t; }
        return a;
    }
    // Play `t`, with the rest of the visible list as the queue.
    function playFrom(t) {
        const list = shown.slice();
        let start = list.findIndex(x => x.path === t.path);
        let order = list;
        if (Config.musicShuffle) { order = [t].concat(shuffled(list.filter(x => x.path !== t.path))); start = 0; }
        cmd(["stop"]);
        for (const x of order) cmd(["loadfile", x.path, "append"]);
        cmd(["playlist-play-index", Math.max(0, start)]);
        cmd(["set_property", "pause", false]);
    }
    // Files opened from a file manager (scripts/music-open.sh). One song from the
    // library plays with the library as its queue; anything else becomes the queue.
    function playFiles(paths) {
        paths = paths.filter(p => p);
        if (!paths.length) return;
        if (paths.length === 1 && byPath[paths[0]]) {
            query = "";
            playFrom(byPath[paths[0]]);
        } else {
            cmd(["stop"]);
            for (const p of paths) cmd(["loadfile", p, "append"]);
            cmd(["playlist-play-index", 0]);
            cmd(["set_property", "pause", false]);
        }
        if (!visible && !drop.open) drop.show();
    }
    function playNext(t) { cmd(["loadfile", t.path, idle ? "append-play" : "insert-next"]); }
    function playPause() {
        if (idle || !path) { if (shown.length) playFrom(Config.musicShuffle ? shown[Math.floor(Math.random() * shown.length)] : shown[0]); }
        else cmd(["cycle", "pause"]);
    }
    function next() { cmd(["playlist-next"]); }
    function previous() { if (pos > 3) cmd(["seek", 0, "absolute"]); else cmd(["playlist-prev"]); }
    function seek(s) { pos = s; cmd(["seek", s, "absolute"]); }
    function setVolume(v) { volume = v; cmd(["set_property", "volume", v]); saveVol.restart(); }
    function toggleShuffle() {
        Config.musicShuffle = !Config.musicShuffle;
        if (!idle && playlist.length > 1) cmd([Config.musicShuffle ? "playlist-shuffle" : "playlist-unshuffle"]);
    }
    function cycleRepeat() {
        Config.musicRepeat = Config.musicRepeat === "off" ? "all" : Config.musicRepeat === "all" ? "one" : "off";
        if (sock.connected) applyRepeat();
    }

    function open() {
        visible = false;
        visible = true;
        scan.running = true;
        if (!sock.connected) sock.connected = true;
        root.forceActiveFocus();
    }
    IpcHandler {
        target: "music"
        function open(): void { win.open(); }
        function toggle(): void { if (win.visible) win.visible = false; else win.open(); }
        function lyrics(): void { win.open(); win.tab = 2; }
        function mini(): void { win.goMini(); }
        function drop(): void { win.toggleDrop(); }
        function playFiles(paths: string): void { win.playFiles(paths.split("\n")); }
        function playPause(): void { if (!win.tracks.length) scan.running = true; win.playPause(); }
        function next(): void { win.next(); }
        function previous(): void { win.previous(); }
    }

    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60;
        return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (ss < 10 ? "0" : "") + ss;
    }
    function fileUrl(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : ""; }

    // ---------- pieces ----------
    // Rounded cover with a note placeholder.
    component Cover: Item {
        id: cov
        property string src: ""
        property int r: Theme.radius
        property int px: 512
        Image {
            id: img
            anchors.fill: parent
            source: win.fileUrl(cov.src)
            sourceSize: Qt.size(cov.px, cov.px)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Rectangle { id: mask; anchors.fill: parent; radius: cov.r; visible: false; layer.enabled: true }
        MultiEffect { anchors.fill: parent; source: img; maskEnabled: true; maskSource: mask; visible: img.status === Image.Ready }
        Rectangle {
            anchors.fill: parent; radius: cov.r; color: Theme.bg2
            visible: img.status !== Image.Ready
            Text { anchors.centerIn: parent; text: "music_note"; color: Theme.fg4; font { family: Theme.fontIcons; pixelSize: Math.max(16, cov.height * 0.4) } }
        }
    }

    // Round icon button. lit = switched on (blue), primary = big blue play button.
    component CtlBtn: Rectangle {
        id: cb
        property string icon: ""
        property bool lit: false
        property bool primary: false
        property bool enabled_: true
        property int size: primary ? 60 : 44
        signal tapped()
        width: size; height: width; radius: width / 2
        opacity: enabled_ ? 1 : 0.4
        color: primary ? (h.hovered ? Qt.lighter(Theme.blueDim, 1.15) : Theme.blueDim)
             : lit ? Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, h.hovered ? 0.28 : 0.18)
             : (h.hovered ? Theme.bg2 : Theme.clear(Theme.bg2))
        scale: ma.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Behavior on scale { NumberAnimation { duration: Theme.durFast } }
        Text {
            anchors.centerIn: parent
            text: cb.icon
            color: cb.primary ? Theme.textOnBlue : cb.lit ? Theme.blue : Theme.fg1
            font { family: Theme.fontIcons; pixelSize: Math.round(cb.size * (cb.primary ? 0.53 : 0.55)) }
        }
        HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
        MouseArea { id: ma; anchors.fill: parent; onClicked: if (cb.enabled_) cb.tapped() }
    }

    // Three bouncing bars on the song that is playing.
    component Bars: Row {
        id: bars
        property bool running: false
        property color tint: Theme.bg0
        spacing: 2
        height: 14
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: 3; radius: 1.5
                anchors.bottom: parent.bottom
                color: bars.tint
                height: 4
                SequentialAnimation on height {
                    running: bars.running
                    loops: Animation.Infinite
                    NumberAnimation { to: 14; duration: 260 + index * 90; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 4; duration: 300 + index * 70; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // The cover, blurred, fading into `base`.
    component ArtBlur: Item {
        id: bd
        property color base: Theme.bg0
        property bool vertical: true
        Image {
            id: backImg
            anchors.fill: parent
            source: win.current ? win.fileUrl(win.current.art) : ""
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectCrop
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: backImg
            visible: backImg.status === Image.Ready
            blurEnabled: true; blur: 1.0; blurMax: 64
            saturation: 0.1
            opacity: 0.3
        }
        Rectangle {   // flat wash for the mini player
            anchors.fill: parent
            visible: !bd.vertical
            color: bd.base
            opacity: 0.55
        }
        Rectangle {
            anchors.fill: parent
            visible: bd.vertical
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(bd.base.r, bd.base.g, bd.base.b, 0.35) }
                GradientStop { position: 1.0; color: bd.base }
            }
        }
    }

    // Seek bar with elapsed / total time under it.
    component Seek: Column {
        id: sk
        property real dragVal: -1
        readonly property real frac: win.dur > 0 ? Math.min(1, (dragVal >= 0 ? dragVal : win.pos) / win.dur) : 0
        spacing: 2
        Item {
            id: seekTrack
            width: parent.width; height: 22
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: Theme.bg2 }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(6, parent.width * sk.frac); height: 6; radius: 3
                color: Theme.yellowDim
                visible: win.dur > 0
            }
            Rectangle {
                x: parent.width * sk.frac - width / 2
                anchors.verticalCenter: parent.verticalCenter
                visible: win.dur > 0
                width: seekMa.pressed || seekHover.hovered ? 16 : 0
                height: width; radius: width / 2
                color: Theme.fg0
                Behavior on width { NumberAnimation { duration: Theme.durFast } }
            }
            HoverHandler { id: seekHover; cursorShape: Qt.PointingHandCursor; enabled: win.dur > 0 }
            MouseArea {
                id: seekMa
                anchors { fill: parent; margins: -4 }
                enabled: win.dur > 0
                onPressed: (m) => sk.dragVal = Math.max(0, Math.min(1, (m.x - 4) / seekTrack.width)) * win.dur
                onPositionChanged: (m) => { if (pressed) sk.dragVal = Math.max(0, Math.min(1, (m.x - 4) / seekTrack.width)) * win.dur; }
                onReleased: { win.seek(sk.dragVal); sk.dragVal = -1; }
                onCanceled: sk.dragVal = -1
            }
        }
        Item {
            width: parent.width; height: 16
            Text { text: win.fmt(sk.dragVal >= 0 ? sk.dragVal : win.pos); color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold } }
            Text { anchors.right: parent.right; text: win.fmt(win.dur); color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold } }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool sel: false
        signal tapped()
        implicitWidth: cl.implicitWidth + 32; implicitHeight: 36; radius: 18
        color: sel ? Theme.yellowDim : (ch.hovered ? Theme.bg2 : Theme.bg1)
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Text { id: cl; anchors.centerIn: parent; text: chip.text; color: chip.sel ? Theme.bg0 : Theme.fg1; font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold } }
        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: chip.tapped() }
    }

    // Mini player body: the floating window's layout, and the bar's drop-down card.
    component MiniBody: Item {
        id: mb
        property bool inDrop: false
        clip: true

        ArtBlur { anchors.fill: parent; base: Theme.bg0; vertical: false; visible: !mb.inDrop }

        Cover {
            id: miniArt
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 16 }
            width: height
            src: win.current ? win.current.art : ""
            r: Theme.radius
            px: 256
        }

        ColumnLayout {
            anchors { left: miniArt.right; leftMargin: 16; right: parent.right; rightMargin: 16; top: parent.top; topMargin: 14; bottom: parent.bottom; bottomMargin: 10 }
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: win.current ? win.current.title : "Nothing playing"
                elide: Text.ElideRight
                color: Theme.fg0
                font { family: Theme.fontDisplay; pixelSize: 16; weight: Font.Bold }
            }
            Text {
                Layout.fillWidth: true; Layout.topMargin: 2
                text: win.current ? (win.current.artist || " ") : (win.tracks.length ? "Press play, or Space" : " ")
                elide: Text.ElideRight
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
            // the line being sung
            Text {
                id: miniLyric
                Layout.fillWidth: true; Layout.topMargin: 6
                Layout.preferredHeight: 38
                text: win.lyricText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                color: Theme.yellow
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { target: miniLyric; property: "opacity"; to: 0; duration: 90 }
                        PropertyAction {}
                        NumberAnimation { target: miniLyric; property: "opacity"; to: 1; duration: 160 }
                    }
                }
            }
            Item { Layout.fillHeight: true }
            Seek { Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 2
                spacing: 2
                CtlBtn { size: 36; icon: "skip_previous"; enabled_: !win.idle; onTapped: win.previous() }
                CtlBtn { size: 42; icon: win.playing ? "pause" : "play_arrow"; primary: true; enabled_: win.tracks.length > 0 || !win.idle; onTapped: win.playPause() }
                CtlBtn { size: 36; icon: "skip_next"; enabled_: !win.idle; onTapped: win.next() }
                Item { Layout.fillWidth: true }
                CtlBtn { size: 36; icon: "shuffle"; lit: Config.musicShuffle; onTapped: win.toggleShuffle() }
                CtlBtn { size: 36; icon: Config.musicRepeat === "one" ? "repeat_one" : "repeat"; lit: Config.musicRepeat !== "off"; onTapped: win.cycleRepeat() }
                CtlBtn { size: 36; icon: "open_in_full"; onTapped: mb.inDrop ? win.openFull() : win.goFull() }
            }
        }
    }

    // ---------- layout ----------
    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) { search.focusInput(); e.accepted = true; }
            else if (search.editing) {
                if (e.key === Qt.Key_Escape) { win.query = ""; root.forceActiveFocus(); e.accepted = true; }
            }
            else if (e.key === Qt.Key_Space) { win.playPause(); e.accepted = true; }
            else if (e.key === Qt.Key_Right && (e.modifiers & Qt.ControlModifier)) { win.next(); e.accepted = true; }
            else if (e.key === Qt.Key_Left && (e.modifiers & Qt.ControlModifier)) { win.previous(); e.accepted = true; }
            else if (e.key === Qt.Key_Right && win.dur > 0) { win.seek(Math.min(win.dur - 1, win.pos + 10)); e.accepted = true; }
            else if (e.key === Qt.Key_Left && win.dur > 0) { win.seek(Math.max(0, win.pos - 10)); e.accepted = true; }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0
            visible: !win.mini

            // ===== now playing =====
            Rectangle {
                id: side
                Layout.fillHeight: true
                Layout.preferredWidth: 340
                color: Theme.bg0s
                clip: true

                ArtBlur { anchors.fill: parent; base: Theme.bg0s }

                ColumnLayout {
                    anchors { fill: parent; margins: 28 }
                    spacing: 0

                    Cover {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width
                        src: win.current ? win.current.art : ""
                        r: Theme.radiusPanel
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.5; shadowVerticalOffset: 4 }
                    }

                    Text {
                        Layout.fillWidth: true; Layout.topMargin: 22
                        text: win.current ? win.current.title : "Nothing playing"
                        elide: Text.ElideRight
                        color: Theme.fg0
                        font { family: Theme.fontDisplay; pixelSize: 19; weight: Font.Bold }
                    }
                    Text {
                        Layout.fillWidth: true; Layout.topMargin: 4
                        text: win.current ? [win.current.artist, win.current.album].filter(x => x).join(" · ") || " "
                                          : (win.tracks.length ? "Pick a song, or press Space" : " ")
                        elide: Text.ElideRight
                        color: Theme.fg4
                        font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
                    }

                    Seek { Layout.fillWidth: true; Layout.topMargin: 18 }

                    // controls
                    Row {
                        Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 14
                        spacing: 8
                        CtlBtn { anchors.verticalCenter: parent.verticalCenter; icon: "shuffle"; lit: Config.musicShuffle; onTapped: win.toggleShuffle() }
                        CtlBtn { anchors.verticalCenter: parent.verticalCenter; icon: "skip_previous"; enabled_: !win.idle; onTapped: win.previous() }
                        CtlBtn { anchors.verticalCenter: parent.verticalCenter; icon: win.playing ? "pause" : "play_arrow"; primary: true; enabled_: win.tracks.length > 0 || !win.idle; onTapped: win.playPause() }
                        CtlBtn { anchors.verticalCenter: parent.verticalCenter; icon: "skip_next"; enabled_: !win.idle; onTapped: win.next() }
                        CtlBtn { anchors.verticalCenter: parent.verticalCenter; icon: Config.musicRepeat === "one" ? "repeat_one" : "repeat"; lit: Config.musicRepeat !== "off"; onTapped: win.cycleRepeat() }
                    }

                    Item { Layout.fillHeight: true; Layout.minimumHeight: 12 }

                    QsSlider {
                        Layout.fillWidth: true
                        value: win.volume / 100
                        muted: win.muted
                        icon: win.muted || win.volume === 0 ? "volume_off" : win.volume < 50 ? "volume_down" : "volume_up"
                        onMoved: (v) => win.setVolume(Math.round(v * 100))
                        onIconClicked: win.cmd(["cycle", "mute"])
                    }
                }
            }

            // ===== library / queue =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 24
                Layout.leftMargin: 28
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Chip { text: "Library"; sel: win.tab === 0; onTapped: win.tab = 0 }
                    Chip { text: win.playlist.length ? "Queue  " + win.playlist.length : "Queue"; sel: win.tab === 1; onTapped: win.tab = 1 }
                    Chip { text: "Lyrics"; sel: win.tab === 2; onTapped: win.tab = 2 }
                    Item { Layout.fillWidth: true }
                    TextBox {
                        id: search
                        visible: win.tab === 0
                        Layout.preferredWidth: 230
                        placeholder: "Search  (Ctrl+F)"
                        onTextChanged: win.query = text
                        Connections { target: win; function onQueryChanged() { if (search.text !== win.query) search.text = win.query; } }
                    }
                    Dropdown {
                        visible: win.tab === 0
                        Layout.preferredWidth: 170
                        model: win.sortLabels
                        current: win.sortLabels[Math.max(0, win.sortKeys.indexOf(Config.musicSort))]
                        onPicked: (v) => Config.musicSort = win.sortKeys[win.sortLabels.indexOf(v)]
                    }
                    PillButton {
                        visible: win.tab === 1 && win.playlist.length > 0
                        text: "Clear"
                        onClicked: { win.cmd(["stop"]); win.cmd(["playlist-clear"]); }
                    }
                    PillButton {
                        visible: win.tab === 2 && win.current !== null && win.lyrics !== null && win.lyrics.source !== "file" && win.lyrics.source !== "tags"
                        text: "Search again"
                        onClicked: win.loadLyrics(true)
                    }
                    CtlBtn {
                        size: 40
                        icon: "picture_in_picture_alt"
                        onTapped: win.goMini()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    leftPadding: 4
                    color: Theme.fg4
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                    text: {
                        if (win.tab === 2) {
                            const l = win.lyrics;
                            if (!win.current || win.lyricsLoading || !l || (!l.synced.length && !l.plain)) return "";
                            const from = l.source === "file" ? "from the .lrc file" : l.source === "tags" ? "from the song's tags" : "from " + l.source;
                            return (l.synced.length ? "Synced lyrics " : "Lyrics ") + from + (l.synced.length ? "  ·  click a line to jump there" : "");
                        }
                        if (win.tab === 1) return win.playlist.length ? (win.queueIndex >= 0 ? "Song " + (win.queueIndex + 1) + " of " + win.playlist.length : win.playlist.length + " songs") : "";
                        if (win.scanning && !win.tracks.length) return "Reading " + (win.musicDir || "the music folder") + "…";
                        const l = win.shown, n = l.length;
                        let s = 0; for (const t of l) s += t.duration;
                        const h = Math.floor(s / 3600), m = Math.round(s / 60) % 60;
                        return n + (n === 1 ? " song" : " songs") + " · " + (h ? h + " h " : "") + m + " min" + (win.query ? "  (matching “" + win.query + "”)" : "");
                    }
                }

                // library
                ListView {
                    id: libList
                    visible: win.tab === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.shown
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool cur: win.path === modelData.path && !win.idle
                        width: libList.width; height: 58; radius: Theme.radiusItem
                        color: cur ? Theme.yellowDim : (rh.hovered ? Theme.bg1 : Theme.clear(Theme.bg1))
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }

                        Cover {
                            id: rowArt
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 42; height: 42; r: 8; px: 84
                            src: row.modelData.art
                        }
                        Rectangle {
                            anchors.fill: rowArt; radius: 8
                            visible: row.cur
                            color: Qt.rgba(0, 0, 0, 0.45)
                            Bars { anchors.centerIn: parent; running: win.playing; tint: Theme.fg0 }
                        }
                        Column {
                            anchors { left: rowArt.right; leftMargin: 14; right: album.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: row.modelData.title
                                color: row.cur ? Theme.bg0 : Theme.fg1
                                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: row.modelData.artist || "Unknown artist"
                                color: row.cur ? Theme.bg0 : Theme.fg4
                                opacity: row.cur ? 0.75 : 1
                                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                            }
                        }
                        Text {
                            id: album
                            anchors { right: nextBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            width: libList.width > 560 ? Math.min(200, libList.width * 0.28) : 0
                            visible: width > 0
                            elide: Text.ElideRight
                            text: row.modelData.album
                            color: row.cur ? Theme.bg0 : Theme.fg4
                            opacity: row.cur ? 0.75 : 1
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                        }
                        Rectangle {
                            id: nextBtn
                            anchors { right: durText.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 34; height: 34; radius: 17
                            opacity: rh.hovered && !row.cur ? 1 : 0
                            visible: opacity > 0
                            color: nbh.hovered ? Theme.bg3 : Theme.clear(Theme.bg3)
                            Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                            Text { anchors.centerIn: parent; text: "queue_play_next"; color: Theme.fg1; font { family: Theme.fontIcons; pixelSize: 20 } }
                            HoverHandler { id: nbh; cursorShape: Qt.PointingHandCursor }
                        }
                        Text {
                            id: durText
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 44
                            horizontalAlignment: Text.AlignRight
                            text: win.fmt(row.modelData.duration)
                            color: row.cur ? Theme.bg0 : Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                        }
                        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: (m) => {
                                root.forceActiveFocus();
                                const p = mapToItem(nextBtn, m.x, m.y);
                                if (nextBtn.visible && nextBtn.contains(p)) win.playNext(row.modelData);
                                else if (row.cur) win.cmd(["cycle", "pause"]);
                                else win.playFrom(row.modelData);
                            }
                        }
                    }

                    // empty library
                    Column {
                        anchors.centerIn: parent
                        visible: !win.scanning && win.tracks.length === 0
                        spacing: 12
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "library_music"; color: Theme.bg3; font { family: Theme.fontIcons; pixelSize: 64 } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No music in " + (win.musicDir || "~/Music") + " yet"; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                        PillButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Open the folder"
                            onClicked: Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", win.musicDir || Quickshell.env("HOME") + "/Music"])
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: win.tracks.length > 0 && win.shown.length === 0
                        text: "No songs match “" + win.query + "”"
                        color: Theme.fg4
                        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                    }
                }

                // queue
                ListView {
                    id: queueList
                    visible: win.tab === 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.playlist
                    delegate: Rectangle {
                        id: qrow
                        required property var modelData
                        required property int index
                        readonly property var t: win.byPath[modelData.filename] || ({ title: modelData.filename.split("/").pop(), artist: "", art: "", duration: 0 })
                        readonly property bool cur: !!modelData.current
                        readonly property bool played: win.queueIndex >= 0 && index < win.queueIndex
                        width: queueList.width; height: 58; radius: Theme.radiusItem
                        color: cur ? Theme.yellowDim : (qh.hovered ? Theme.bg1 : Theme.clear(Theme.bg1))
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Text {
                            id: num
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 26; horizontalAlignment: Text.AlignRight
                            text: qrow.index + 1
                            color: qrow.cur ? Theme.bg0 : Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                        }
                        Cover {
                            id: qArt
                            anchors { left: num.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            width: 42; height: 42; r: 8; px: 84
                            src: qrow.t.art
                            opacity: qrow.played ? 0.5 : 1
                        }
                        Rectangle {
                            anchors.fill: qArt; radius: 8
                            visible: qrow.cur
                            color: Qt.rgba(0, 0, 0, 0.45)
                            Bars { anchors.centerIn: parent; running: win.playing; tint: Theme.fg0 }
                        }
                        Column {
                            anchors { left: qArt.right; leftMargin: 14; right: rmBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            opacity: qrow.played ? 0.55 : 1
                            Text { width: parent.width; elide: Text.ElideRight; text: qrow.t.title; color: qrow.cur ? Theme.bg0 : Theme.fg1; font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold } }
                            Text { width: parent.width; elide: Text.ElideRight; text: qrow.t.artist || "Unknown artist"; color: qrow.cur ? Theme.bg0 : Theme.fg4; opacity: qrow.cur ? 0.75 : 1; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
                        }
                        Rectangle {
                            id: rmBtn
                            anchors { right: qDur.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 34; height: 34; radius: 17
                            opacity: qh.hovered && !qrow.cur ? 1 : 0
                            visible: opacity > 0
                            color: rbh.hovered ? Theme.bg3 : Theme.clear(Theme.bg3)
                            Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                            Text { anchors.centerIn: parent; text: "close"; color: Theme.fg1; font { family: Theme.fontIcons; pixelSize: 20 } }
                            HoverHandler { id: rbh; cursorShape: Qt.PointingHandCursor }
                        }
                        Text {
                            id: qDur
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 44; horizontalAlignment: Text.AlignRight
                            text: win.fmt(qrow.t.duration)
                            color: qrow.cur ? Theme.bg0 : Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.Bold }
                        }
                        HoverHandler { id: qh; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: (m) => {
                                root.forceActiveFocus();
                                const p = mapToItem(rmBtn, m.x, m.y);
                                if (rmBtn.visible && rmBtn.contains(p)) win.cmd(["playlist-remove", qrow.index]);
                                else if (qrow.cur) win.cmd(["cycle", "pause"]);
                                else { win.cmd(["playlist-play-index", qrow.index]); win.cmd(["set_property", "pause", false]); }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        visible: win.playlist.length === 0
                        spacing: 12
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "queue_music"; color: Theme.bg3; font { family: Theme.fontIcons; pixelSize: 64 } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "The queue is empty"; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Play a song from the library and the rest follow it here."; color: Theme.fg4; font { family: Theme.fontUi; pixelSize: 12 } }
                    }
                }

                // lyrics
                Item {
                    id: lyricsPane
                    visible: win.tab === 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // synced: the line being sung stays a third of the way down
                    ListView {
                        id: lyrList
                        anchors.fill: parent
                        visible: win.synced.length > 0 && !win.lyricsLoading
                        model: win.synced
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        // scrolled by hand: stop following for a few seconds
                        property bool follow: true
                        Timer { id: followAgain; interval: 4000; onTriggered: lyrList.follow = true }
                        onMovementStarted: { follow = false; followAgain.stop(); }
                        onMovementEnded: followAgain.restart()
                        readonly property int line: win.lyricLine
                        onLineChanged: if (follow) center()
                        onVisibleChanged: if (visible) Qt.callLater(() => center(true))
                        onCountChanged: Qt.callLater(() => center(true))
                        function center(now) {
                            const i = Math.max(0, line);
                            const it = itemAtIndex(i);
                            if (!it) { positionViewAtIndex(i, ListView.Center); return; }
                            const target = Math.max(originY, Math.min(it.y - height * 0.33 + it.height / 2, originY + contentHeight - height));
                            scrollAnim.stop();
                            if (now) contentY = target;
                            else { scrollAnim.to = target; scrollAnim.start(); }
                        }
                        NumberAnimation { id: scrollAnim; target: lyrList; property: "contentY"; duration: 450; easing.type: Theme.easeOut }
                        header: Item { width: 1; height: lyrList.height * 0.33 }
                        footer: Item { width: 1; height: lyrList.height * 0.6 }
                        delegate: Item {
                            id: ll
                            required property var modelData
                            required property int index
                            readonly property bool now: index === win.lyricLine
                            readonly property bool past: index < win.lyricLine
                            width: lyrList.width
                            height: lt.implicitHeight + 10
                            Text {
                                id: lt
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 4; rightMargin: 24 }
                                text: ll.modelData[1] || "♪"
                                wrapMode: Text.WordWrap
                                color: ll.now ? Theme.fg0 : lh.hovered ? Theme.fg1 : Theme.fg4
                                opacity: ll.now ? 1 : ll.past ? 0.45 : 0.8
                                scale: ll.now ? 1 : 0.94
                                transformOrigin: Item.Left
                                font { family: Theme.fontUi; pixelSize: 24; weight: Font.ExtraBold }
                                Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
                                Behavior on scale { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }
                                Behavior on color { ColorAnimation { duration: Theme.durMed } }
                            }
                            HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root.forceActiveFocus(); win.seek(ll.modelData[0]); lyrList.follow = true; if (win.paused) win.cmd(["set_property", "pause", false]); }
                            }
                        }
                    }

                    // plain lyrics
                    Flickable {
                        anchors.fill: parent
                        visible: win.synced.length === 0 && !win.lyricsLoading && win.lyrics !== null && win.lyrics.plain !== ""
                        contentHeight: plainText.implicitHeight + 40
                        boundsBehavior: Flickable.StopAtBounds
                        Text {
                            id: plainText
                            width: parent.width - 24
                            x: 4; y: 8
                            text: win.lyrics ? win.lyrics.plain : ""
                            wrapMode: Text.WordWrap
                            lineHeight: 1.35
                            color: Theme.fg1
                            font { family: Theme.fontUi; pixelSize: 18; weight: Font.Bold }
                        }
                    }

                    // nothing to show
                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 40, 420)
                        visible: !lyrList.visible && !(win.lyrics && win.lyrics.plain && !win.lyricsLoading)
                        spacing: 12
                        readonly property var l: win.lyrics
                        readonly property string state_: !win.current ? "idle"
                            : win.lyricsLoading ? "loading"
                            : l && l.error ? "error"
                            : l && l.instrumental ? "instrumental" : "none"
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ({ idle: "lyrics", loading: "hourglass_top", error: "cloud_off", instrumental: "piano", none: "speaker_notes_off" })[parent.state_]
                            color: Theme.bg3
                            font { family: Theme.fontIcons; pixelSize: 64 }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ({ idle: "Play a song to see its lyrics", loading: "Looking for lyrics…", error: "Couldn't reach lrclib.net",
                                     instrumental: "This one is instrumental", none: "No lyrics found for this song" })[parent.state_]
                            color: Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: parent.state_ === "none" || parent.state_ === "error"
                            text: parent.state_ === "error" ? "Check the connection, then press Search again."
                                : "Put a .lrc file with the same name next to the song and it will be used instead."
                            color: Theme.fg4
                            font { family: Theme.fontUi; pixelSize: 12 }
                        }
                    }
                }
            }
        }

        // ===== mini player (while floating) =====
        MiniBody { anchors.fill: parent; visible: win.mini }
    }

    // ---------- drop-down mini player (bar song pill) ----------
    // Same look and motion as quick settings: slides out from under the bar, top right.
    PanelWindow {
        id: drop
        property bool open: false
        property real dropY: open ? 0 : -(dcard.height + 10)
        Behavior on dropY { NumberAnimation { duration: drop.open ? Theme.durSlow : Theme.durMed; easing.type: drop.open ? Theme.easeEmph : Theme.easeOut } }

        visible: false
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell-panel-music"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        BackgroundEffect.blurRegion: Region { item: dblur; radius: dcard.radius }

        function show() {
            if (ShellState.quickSettingsOpen) ShellState.toggleQuickSettings();
            visible = true; open = true; dkeys.forceActiveFocus();
        }
        function hide() { open = false; dhide.restart(); }
        function toggle() { open ? hide() : show(); }
        Timer { id: dhide; interval: Theme.durMed; onTriggered: if (!drop.open) drop.visible = false }
        Connections {
            target: ShellState
            function onQuickSettingsOpenChanged() { if (ShellState.quickSettingsOpen && drop.open) drop.hide(); }
            function onDatePanelOpenChanged() { if (ShellState.datePanelOpen && drop.open) drop.hide(); }
        }

        MouseArea { anchors.fill: parent; onClicked: drop.hide() }

        Item {
            anchors { fill: parent; topMargin: Theme.barHeight }
            clip: true

            Item {
                id: dblur
                anchors.right: dcard.right
                width: dcard.width
                y: Math.max(0, dcard.y + drop.dropY)
                height: Math.max(0, dcard.y + drop.dropY + dcard.height - y)
                opacity: 0
            }
            Rectangle {
                id: dcard
                anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                width: win.miniW
                height: win.miniH
                radius: Theme.radiusPanel
                color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.82)
                border.width: 1
                border.color: Qt.rgba(Theme.fg1.r, Theme.fg1.g, Theme.fg1.b, 0.08)
                opacity: drop.open ? 1 : 0
                transform: Translate { y: drop.dropY }
                Behavior on opacity { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeOut } }

                MouseArea { anchors.fill: parent }   // clicks on the card don't close it

                FocusScope {
                    id: dkeys
                    anchors.fill: parent
                    focus: true
                    Keys.onEscapePressed: drop.hide()
                    Keys.onSpacePressed: win.playPause()
                    MiniBody { anchors.fill: parent; inDrop: true }
                }
            }
        }
    }
}
