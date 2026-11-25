import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → About: computer name (rename via hostnamectl + polkit), system
// and hardware summary, versions, "Copy system info".
ColumnLayout {
    id: page
    spacing: 14

    property var info: ({})

    function load() { read.running = true; }
    Process {
        id: read
        command: ["sh", "-c", `
            . /etc/os-release
            p() { printf '%s\\t%s\\n' "$1" "$2"; }
            p host "$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)"
            p os "$PRETTY_NAME"
            p logo "\${LOGO:-}"
            p kernel "$(uname -r)"
            p cpu "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//; s/(R)//g; s/(TM)//g; s/ CPU//; s/  */ /g')"
            p cores "$(nproc)"
            p gpu "$(lspci -mm 2>/dev/null | grep -E 'VGA|3D|Display' | sed -E 's/^[^"]*"[^"]*" "([^"]*)" "([^"]*)".*/\\1 \\2/' | sed 's/ Corporation//; s/\\[//; s/\\]//' | head -2 | paste -sd ';')"
            p mem "$(awk '/MemTotal/ { printf "%.1f GB", $2/1048576 }' /proc/meminfo)"
            p disk "$(df -h --output=used,size / | tail -1 | awk '{ print $1 " of " $2 " used" }')"
            p uptime "$(uptime -p | sed 's/^up //')"
            p hypr "$(hyprctl version -j 2>/dev/null | sed -n 's/.*"version": "\\([^"]*\\)".*/\\1/p' | head -1)"
            p qs "$(qs --version 2>/dev/null | awk '{ print $2 }')"
            p display "$(hyprctl monitors -j 2>/dev/null | sed -n 's/.*"width": \\([0-9]*\\).*/\\1/p;s/.*"height": \\([0-9]*\\).*/\\1/p;s/.*"refreshRate": \\([0-9.]*\\).*/\\1/p' | paste -sd ' ' | awk '{ for (i = 1; i + 2 <= NF; i += 3) printf "%s%sx%s @ %.0f Hz", (i > 1 ? ", " : ""), $i, $(i+1), $(i+2) }')"
            p pkgs "$(pacman -Qq 2>/dev/null | wc -l)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1);
                }
                page.info = o;
                name.text = o.host || "";
            }
        }
    }

    readonly property var rows: [
        { icon: "computer",       label: "Operating system", key: "os" },
        { icon: "memory",         label: "Processor",        key: "cpu", extra: "cores" },
        { icon: "developer_board", label: "Graphics",        key: "gpu" },
        { icon: "memory_alt",     label: "Memory",           key: "mem" },
        { icon: "hard_drive",     label: "Disk (system)",    key: "disk" },
        { icon: "desktop_windows", label: "Display",         key: "display" },
        { icon: "terminal",       label: "Kernel",           key: "kernel" },
        { icon: "deployed_code",  label: "Packages",         key: "pkgs" },
        { icon: "view_quilt",     label: "Hyprland",         key: "hypr" },
        { icon: "widgets",        label: "Quickshell",       key: "qs" },
        { icon: "schedule",       label: "Up for",           key: "uptime" }
    ]
    function value(r) {
        const v = info[r.key] || "—";
        if (r.key === "cpu" && info.cores) return v + " · " + info.cores + " threads";
        if (r.key === "gpu") return v.split(";").join(", ");
        return v;
    }
    function summary() {
        return ["Computer: " + (info.host || "")].concat(rows.map(r => r.label + ": " + value(r))).join("\n");
    }

    // ---------- header ----------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 140
        radius: Theme.radiusPanel
        color: Theme.bg1

        Image {
            id: logo
            anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
            width: 80; height: 80
            sourceSize: Qt.size(160, 160)
            source: page.info.logo ? Quickshell.iconPath(page.info.logo, true) : ""
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: logo
            visible: !logo.visible
            text: "computer"
            color: Theme.yellow
            font { family: Theme.fontIcons; pixelSize: 64 }
        }
        Column {
            anchors { left: logo.right; leftMargin: 24; right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
            spacing: 4
            Text {
                text: page.info.host || ""
                color: Theme.fg0
                font { family: Theme.fontDisplay; pixelSize: 28; weight: Font.Bold }
            }
            Text {
                text: page.info.os || ""
                color: Theme.fg4
                font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
            }
        }
    }

    SettingRow {
        Layout.topMargin: 6
        label: "Computer name"; hint: "How this PC shows up on the network. Asks for your password."
        Row {
            spacing: 8
            TextBox {
                id: name
                implicitWidth: 220
                invalid: name.text.length > 0 && !/^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(name.text)
                onAccepted: rename.clicked()
            }
            PillButton {
                id: rename
                text: "Rename"
                primary: true
                visible: name.text !== (page.info.host || "") && !name.invalid && name.text.length > 0
                onClicked: { setName.command = ["hostnamectl", "set-hostname", name.text]; setName.running = true; }
            }
        }
    }
    Process {
        id: setName
        onExited: (code) => {
            page.load();
            Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", code === 0 ? "computer" : "error",
                code === 0 ? "Computer renamed" : "Couldn't rename the computer"]);
        }
    }

    SectionTitle { text: "System"; Layout.topMargin: 14 }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: list.implicitHeight + 12
        radius: Theme.radius
        color: Theme.bg1
        Column {
            id: list
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            Repeater {
                model: page.rows
                delegate: Item {
                    id: r
                    required property var modelData
                    width: list.width; height: 44
                    Text {
                        id: ri
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: r.modelData.icon
                        color: Theme.fg4
                        font { family: Theme.fontIcons; pixelSize: 20 }
                    }
                    Text {
                        id: rl
                        anchors { left: ri.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 170
                        text: r.modelData.label
                        color: Theme.fg4
                        font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
                    }
                    Text {
                        anchors { left: rl.right; leftMargin: 8; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: page.value(r.modelData)
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        color: Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        PillButton {
            text: "Copy system info"
            onClicked: {
                Quickshell.execDetached(["wl-copy", page.summary()]);
                Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "content_copy", "System info copied"]);
            }
        }
    }
}
