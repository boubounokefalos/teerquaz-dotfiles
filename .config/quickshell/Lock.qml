import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Io

// Session lock (ext-session-lock) with PAM auth, plus idle handling.
//   qs ipc call lock lock
Scope {
    id: root

    property string password: ""
    property bool busy: false
    property bool unlocking: false
    property int failCount: 0
    property string status: ""
    // keyboard state shown on the lock screen
    property string layoutName: ""
    property bool capsLock: false
    property int savedLayout: -1       // layout index to restore after unlock
    property bool saveLayout: false
    property string pamError: ""       // last error PAM itself reported (faillock lockout, …)
    property int triesLeft: -1         // before faillock locks the account; -1 = unknown
    // limits from /etc/security/faillock.conf (pam_faillock defaults if unset)
    property int faillockDeny: 3
    property int faillockUnlockMin: 10
    FileView {
        path: "/etc/security/faillock.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = text();
            const deny = t.match(/^\s*deny\s*=\s*(\d+)/m);
            const unlock = t.match(/^\s*unlock_time\s*=\s*(\d+)/m);
            root.faillockDeny = deny ? parseInt(deny[1]) : 3;
            root.faillockUnlockMin = unlock ? Math.max(1, Math.round(parseInt(unlock[1]) / 60)) : 10;
        }
    }

    readonly property bool isLocked: sessionLock.locked
    Binding { target: ShellState; property: "locked"; value: sessionLock.locked }

    function lock() {
        if (sessionLock.locked) return;
        password = ""; status = ""; busy = false; unlocking = false; pamError = "";
        sessionLock.locked = true;
        // A password typed on the Greek layout never matches: remember the
        // layout and switch to the first one (us) while locked.
        saveLayout = true;
        kbRead.running = true;
        tally.running = true;
    }

    function restoreLayout() {
        if (savedLayout > 0)
            Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(savedLayout)]);
        savedLayout = -1;
    }

    // layout + Caps Lock of the main keyboard
    Process {
        id: kbRead
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const k = JSON.parse(text).keyboards.find(k => k.main);
                    if (!k) return;
                    root.capsLock = k.capsLock;
                    root.layoutName = k.active_keymap;
                    if (root.saveLayout) {
                        root.saveLayout = false;
                        root.savedLayout = k.active_layout_index;
                        if (k.active_layout_index !== 0) {
                            Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "0"]);
                            kbPoll.restart();
                        }
                    }
                } catch (e) {}
            }
        }
    }
    Timer {
        id: kbPoll
        interval: 500; repeat: true
        running: sessionLock.locked && !root.unlocking
        onTriggered: if (!kbRead.running) kbRead.running = true
    }

    // faillock tally: valid failures in the current window (readable as the user)
    Process {
        id: tally
        command: ["faillock"]
        stdout: StdioCollector {
            onStreamFinished: {
                const valid = text.split("\n").filter(l => /\sV\s*$/.test(l)).length;
                root.triesLeft = Math.max(0, root.faillockDeny - valid);
            }
        }
    }

    function tryUnlock() {
        if (busy || unlocking || password.length === 0) return;
        busy = true;
        status = "";
        pamError = "";
        if (!pam.start()) {
            busy = false;
            status = "Could not start authentication";
        }
    }

    PamContext {
        id: pam
        config: "login"
        onMessageChanged: if (messageIsError && message.length) root.pamError = message.trim()
        onResponseRequiredChanged: {
            if (responseRequired) respond(root.password);
        }
        onCompleted: (result) => {
            root.busy = false;
            if (result === PamResult.Success) {
                root.unlocking = true;      // surfaces fade out, then we unlock
                unlockTimer.restart();
            } else {
                root.password = "";
                // faillock's own text says when the account is locked and for how long
                root.status = root.pamError.length ? root.pamError.replace(/\s*\n\s*/g, " ")
                            : result === PamResult.MaxTries ? "Too many attempts, wait a moment" : "Wrong password";
                root.failCount++;
                tally.running = true;
            }
        }
        onError: (error) => {
            root.busy = false;
            root.password = "";
            root.status = "Authentication error";
            root.failCount++;
        }
    }

    Timer {
        id: unlockTimer
        interval: 320
        onTriggered: {
            sessionLock.locked = false;
            root.password = "";
            root.unlocking = false;
            root.restoreLayout();
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        WlSessionLockSurface {
            color: Theme.bg0
            LockSurface {
                anchors.fill: parent
                ctx: root
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
    }

    // Idle times come from Settings → Power & idle (minutes, 0 = never).
    // IdleTimer, not a bare IdleMonitor: see the Quickshell bug noted there.
    IdleTimer {
        minutes: Config.lockAfter
        onIdle: root.lock()
    }
    IdleTimer {
        minutes: Config.screenOffAfter
        onIdle: Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "disable" })'])
        onResumed: Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "enable" })'])
    }
    IdleTimer {
        minutes: Config.suspendAfter
        onIdle: Quickshell.execDetached(["systemctl", "suspend"])
    }

    // ---------- lock before sleep, whoever asks for it ----------
    // A delay inhibitor makes logind wait (up to InhibitDelayMaxSec) until the
    // lock surface is up, so the desktop never shows on wake.
    readonly property string inhibitScript: Quickshell.shellDir + "/scripts/hold-inhibit.sh"
    Process {
        id: sleepInhibit
        running: Config.lockOnSuspend
        command: [root.inhibitScript, "sleep", "delay", "Lock the screen before sleep"]
    }
    Process {
        id: sleepWatch
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("PrepareForSleep") < 0) return;
                if (line.indexOf("(true") >= 0) {
                    if (Config.lockOnSuspend) { root.lock(); releaseSleep.restart(); }
                } else {
                    releaseSleep.stop();
                    sleepInhibit.running = Config.lockOnSuspend;
                }
            }
        }
    }
    // give the lock surface a moment to be drawn, then let the system sleep
    Timer { id: releaseSleep; interval: 500; onTriggered: sleepInhibit.running = false }

    // ---------- power button ----------
    // logind would power off at once (HandlePowerKey=poweroff); block that while
    // the shell runs and do what Settings → Power & idle says (PowerMenu.button()).
    Process {
        running: true
        command: [root.inhibitScript, "handle-power-key", "block", "The shell handles the power button"]
    }
}
