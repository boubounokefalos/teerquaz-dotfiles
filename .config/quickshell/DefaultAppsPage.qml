import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → Default apps. Uses the standard XDG tools (xdg-mime,
// ~/.config/xdg-terminals.list), so every toolkit and desktop agrees.
ColumnLayout {
    id: page
    spacing: 14

    // category -> MIME types it covers (the first one is used to read the current default)
    readonly property var categories: [
        { key: "web",      label: "Web browser",  icon: "public",      mimes: ["x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"] },
        { key: "mail",     label: "Email",        icon: "mail",        mimes: ["x-scheme-handler/mailto"] },
        { key: "files",    label: "Files",        icon: "folder",      mimes: ["inode/directory"] },
        { key: "terminal", label: "Terminal",     icon: "terminal",    mimes: [] },
        { key: "text",     label: "Text editor",  icon: "description", mimes: ["text/plain", "text/markdown", "application/x-shellscript"] },
        { key: "images",   label: "Images",       icon: "image",       mimes: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/tiff", "image/svg+xml", "image/avif"] },
        { key: "video",    label: "Video",        icon: "movie",       mimes: ["video/x-matroska", "video/mp4", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg", "video/x-flv"] },
        { key: "music",    label: "Music",        icon: "music_note",  mimes: ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/x-wav"] },
        { key: "pdf",      label: "PDF",          icon: "picture_as_pdf", mimes: ["application/pdf"] },
        { key: "archive",  label: "Archives",     icon: "folder_zip",  mimes: ["application/zip", "application/x-tar", "application/x-compressed-tar", "application/x-7z-compressed", "application/vnd.rar", "application/x-xz-compressed-tar"] }
    ]

    property var apps: []          // [{ id, name, mimes: [...], terminal: bool }]
    property var current: ({})     // category key -> desktop id

    function load() { scan.running = true; }

    Process {
        id: scan
        // desktop files (user ones override system ones), then the current defaults
        command: ["sh", "-c", `
            seen=" "
            for d in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
                for f in "$d"/*.desktop; do
                    [ -f "$f" ] || continue
                    id=$(basename "$f")
                    case "$seen" in *" $id "*) continue;; esac
                    seen="$seen$id "
                    awk -v id="$id" -F= '
                        /^\\[/ { main = ($0 == "[Desktop Entry]") }
                        main && $1 == "Name" && !name { name = substr($0, 6) }
                        main && $1 == "MimeType" { mime = substr($0, 10) }
                        main && $1 == "Categories" { cat = substr($0, 12) }
                        main && $1 == "Hidden" && $2 == "true" { hidden = 1 }
                        END { if (!hidden) printf "A\\t%s\\t%s\\t%s\\t%s\\n", id, name, mime, cat }
                    ' "$f"
                done
            done
            for m in ${page.categories.filter(c => c.mimes.length).map(c => c.key + "=" + c.mimes[0]).join(" ")}; do
                printf 'D\\t%s\\t%s\\n' "\${m%%=*}" "$(xdg-mime query default "\${m#*=}")"
            done
            printf 'D\\tterminal\\t%s\\n' "$(grep -v '^#' "\${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list" 2>/dev/null | head -1)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const apps = [], cur = {};
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "A" && p[2]) {
                        apps.push({ id: p[1], name: p[2],
                                    mimes: (p[3] || "").split(";").filter(x => x),
                                    terminal: (p[4] || "").split(";").indexOf("TerminalEmulator") >= 0 });
                    } else if (p[0] === "D") cur[p[1]] = p[2] || "";
                }
                page.apps = apps;
                page.current = cur;
            }
        }
    }

    function candidates(cat) {
        let list;
        if (cat.key === "terminal") list = apps.filter(a => a.terminal);
        else list = apps.filter(a => cat.mimes.some(m => a.mimes.indexOf(m) >= 0));
        // make duplicate names distinguishable
        const count = {};
        for (const a of list) count[a.name] = (count[a.name] || 0) + 1;
        return list.map(a => ({ id: a.id, label: count[a.name] > 1 ? a.name + " (" + a.id.replace(/\.desktop$/, "") + ")" : a.name }))
                   .sort((a, b) => a.label.localeCompare(b.label));
    }

    function setDefault(cat, id) {
        if (cat.key === "terminal") {
            Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list"', "sh", id]);
        } else {
            // only the types this app actually declares
            const app = apps.find(a => a.id === id);
            const mimes = cat.mimes.filter(m => !app || app.mimes.length === 0 || app.mimes.indexOf(m) >= 0);
            Quickshell.execDetached(["xdg-mime", "default", id].concat(mimes.length ? mimes : cat.mimes));
        }
        const c = Object.assign({}, current); c[cat.key] = id; current = c;
    }

    SectionTitle { text: "Default apps" }
    Text {
        Layout.fillWidth: true
        text: "Which app opens links, folders and files. Only apps that say they can open that kind of file are listed."
        color: Theme.fg4
        wrapMode: Text.WordWrap
        font { family: Theme.fontUi; pixelSize: 12 }
    }

    Repeater {
        model: page.categories
        delegate: SettingRow {
            id: row
            required property var modelData
            readonly property var opts: page.candidates(modelData)
            label: modelData.label
            hint: opts.length ? "" : "No installed app handles this"
            Dropdown {
                model: row.opts.map(o => o.label)
                current: { const o = row.opts.find(o => o.id === page.current[row.modelData.key]); return o ? o.label : (page.current[row.modelData.key] || ""); }
                onPicked: (v) => { const o = row.opts.find(o => o.label === v); if (o) page.setDefault(row.modelData, o.id); }
            }
        }
    }

    SectionTitle { text: "Removable drives"; Layout.topMargin: 14 }
    SettingRow {
        label: "Mount drives when plugged in"
        hint: "USB sticks and SD cards get ready to use with a notification (Open / Eject); off: open them from the drive icon in the bar"
        Toggle { checked: Config.autoMount; onToggled: (v) => Config.autoMount = v }
    }
}
