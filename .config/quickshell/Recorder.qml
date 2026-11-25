pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen recording with gpu-screen-recorder (NVENC on the GPU, so it costs
// almost nothing). Records the screen in use, or a dragged area, with the
// desktop sound to ~/Videos/Screencasts. The bar shows a red pill with the
// time while recording; click it (or the shortcut again) to stop.
//   qs ipc call recorder toggle | area | stop
Singleton {
    id: root

    property bool available: false
    readonly property bool recording: proc.running
    property string file: ""
    property real startedAt: 0
    property int elapsed: 0            // seconds
    readonly property string dir: Quickshell.env("HOME") + "/Videos/Screencasts"

    function osd(icon, text) { Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", icon, text]); }
    function clock(s) { return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }

    function start(area) {
        if (recording) return;
        if (!available) { wantStart = area ? 1 : 0; check.running = true; return; }
        if (prep.running) { console.log("recorder: already picking"); return; }
        console.log("recorder: start", area ? "area" : "screen");
        if (area) osd("select", "Drag a box around what to record · Esc cancels");
        prep.area = area;
        prep.running = true;
    }
    function stop() { if (recording) proc.signal(2); }      // SIGINT: finish the file
    function toggle() { recording ? stop() : start(false); }

    // which screen (or which area), and the file name. slurp gets /dev/null as
    // stdin: with a pipe there (Quickshell's) it waits for boxes on it and never shows.
    Process {
        id: prep
        property bool area: false
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.log("recorder: pick stderr", text.trim()) }
        onExited: (code) => console.log("recorder: pick exited", code)
        command: ["sh", "-c", (area ? "g=$(slurp -d -f '%wx%h+%x+%y' < /dev/null) || exit 1; echo \"region $g\"; "
                                     : "hyprctl activeworkspace -j | sed -n 's/.*\"monitor\": \"\\([^\"]*\\)\".*/screen \\1/p'; ")
                              + "mkdir -p '" + root.dir + "'"]
        stdout: StdioCollector {
            onStreamFinished: {
                console.log("recorder: picked", JSON.stringify(text.trim()));
                const m = /^(region|screen) (\S+)/.exec(text.trim());
                if (!m) { root.osd("videocam_off", "Recording cancelled"); return; }
                // a click without dragging gives an empty area
                const sz = /^(\d+)x(\d+)/.exec(m[2]);
                if (m[1] === "region" && sz && (parseInt(sz[1]) < 16 || parseInt(sz[2]) < 16)) {
                    root.osd("videocam_off", "Area too small — drag a box to record");
                    return;
                }
                root.file = root.dir + "/" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
                proc.command = ["gpu-screen-recorder"]
                    .concat(m[1] === "region" ? ["-w", "region", "-region", m[2]] : ["-w", m[2]])
                    .concat(["-f", "60", "-a", "default_output", "-c", "mp4", "-q", "high",
                            // NVENC fails with nvidia-580xx + current FFmpeg (API 13.0 vs 13.1): CPU (x264) until that lines up again
                            "-fallback-cpu-encoding", "yes", "-o", root.file]);
                proc.running = true;
            }
        }
    }

    Process {
        id: proc
        onRunningChanged: {
            if (running) {
                root.startedAt = Date.now(); root.elapsed = 0;
                Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "radio_button_checked", "Recording — click the red pill to stop"]);
            } else if (root.file) {
                Quickshell.execDetached([Quickshell.shellDir + "/scripts/recording-done.sh", root.file]);
                root.file = "";
            }
        }
        stderr: StdioCollector { id: errOut }
        onExited: (code) => {
            console.log("recorder: gsr exited", code, "after", root.elapsed, "s;", errOut.text.trim().split("\n").filter(l => /error/i.test(l)).slice(-2).join(" | "));
            if (code !== 0 && root.elapsed < 2)
                Quickshell.execDetached(["notify-send", "-a", "Screen recording", "-i", "dialog-error",
                    "Recording failed", errOut.text.trim().split("\n").slice(-2).join("\n")]);
        }
    }
    Timer {
        interval: 1000; repeat: true; running: root.recording
        onTriggered: root.elapsed = Math.round((Date.now() - root.startedAt) / 1000)
    }

    // (checked again on use, so installing it later just works)
    property int wantStart: -1           // -1 none, 0 screen, 1 area
    Timer { interval: 30000; repeat: true; running: !root.available; triggeredOnStart: true; onTriggered: check.running = true }
    Process {
        id: check
        command: ["sh", "-c", "command -v gpu-screen-recorder"]
        onExited: (code) => {
            root.available = code === 0;
            if (root.wantStart < 0) return;
            const area = root.wantStart === 1;
            root.wantStart = -1;
            if (root.available) root.start(area);
            else Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "videocam_off", "Screen recording needs gpu-screen-recorder"]);
        }
    }

    IpcHandler {
        target: "recorder"
        function toggle(): void { console.log("recorder: ipc toggle"); root.toggle(); }
        function area(): void { console.log("recorder: ipc area"); root.recording ? root.stop() : root.start(true); }
        function stop(): void { root.stop(); }
    }
}
