import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// GNOME-style overview: live window grid, workspace strip, app search.
//   qs ipc call overview toggle | apps
PanelWindow {
    id: ov
    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-overview"
    // (no keyboard while fuzzel runs on top: it must keep the keyboard or it quits)
    WlrLayershell.keyboardFocus: open && !kbRelease && !fuzzel.running ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Hyprland ignores focus requests while this layer holds the keyboard and,
    // when it lets go, refocuses the last focused window — on whatever
    // workspace that was. So switching workspaces here briefly drops the
    // keyboard and focuses a window on the new workspace (see switchWs).
    property bool kbRelease: false

    property bool open: false          // drives every animation
    property bool appsMode: false      // Super+A: show the app grid straight away
    property int viewWs: 1
    property int selected: -1
    property var clients: []           // raw `hyprctl clients -j`
    property var mon: ({ x: 0, y: 0, width: 2560, height: 1440 })

    // ---------- open / close ----------
    function show(apps) {
        kbRelease = false;
        if (open) { if (apps) { appsMode = true; search.forceActiveFocus(); } return; }
        appsMode = !!apps;
        search.text = "";
        selected = -1;
        loader.running = true;          // fetch windows, then animate in
    }
    function hide(then) {
        if (!open) return;
        open = false;
        afterClose = then || null;
        closeTimer.restart();
    }
    function toggle(apps) { open ? hide() : show(apps); }

    property var afterClose: null
    Timer {
        id: closeTimer
        interval: Theme.durSlow
        onTriggered: {
            ov.visible = false;
            if (ov.afterClose) { const f = ov.afterClose; ov.afterClose = null; f(); }
        }
    }

    Connections {
        target: ShellState
        function onToggleOverview() { ov.toggle(false); }
    }
    IpcHandler {
        target: "overview"
        function toggle(): void { ov.toggle(false); }
        // Super tap (Hyprland bind): off in Settings → Windows turns it into nothing
        function superTap(): void { if (Config.superOverview || ov.open) ov.toggle(false); }
        function apps(): void { ov.open ? ov.hide() : ov.show(true); }
        // Super+R: fuzzel quits when it loses the keyboard, and the overview
        // takes it back on the first pointer move, so close the overview first
        // Super+R: over the overview fuzzel runs on top and the overview stays;
        // a click outside fuzzel closes only fuzzel (see fuzzelShield)
        function launcher(): void {
            if (!ov.open) { Quickshell.execDetached(["fuzzel"]); return; }
            if (fuzzel.running) fuzzel.signal(15);
            else { fuzzel.launched = false; fuzzel.running = true; }
        }
        // from scripts/fuzzel-launch.sh: an app was started → show it
        function fuzzelLaunched(app: string): void {
            ov.expectLaunch([app.split("/").pop()]);
            fuzzel.launched = true;
            if (!fuzzel.running) ov.hide();
        }
    }

    Process {
        id: loader
        command: ["sh", "-c", "hyprctl clients -j; echo @@@; hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("@@@");
                try {
                    ov.clients = JSON.parse(parts[0]);
                    const mons = JSON.parse(parts[1]);
                    const m = mons.find(m => m.focused) || mons[0];
                    ov.mon = { x: m.x, y: m.y, width: m.width / m.scale, height: m.height / m.scale };
                    ov.viewWs = m.activeWorkspace.id;
                } catch (e) { console.warn("overview:", e); }
                ov.visible = true;
                Qt.callLater(() => { ov.open = true; search.forceActiveFocus(); });
            }
        }
    }
    function refresh() { loader.running = true; }

    function dispatch(cmd) { Hyprland.dispatch(cmd); }
    // Focus without Hyprland warping the pointer to the window's centre:
    // cursor.no_warps is switched on for this one call only.
    function dispatchNoWarp(cmd) {
        dispatch('function() hl.config({ cursor = { no_warps = true } }); hl.dispatch(' + cmd
                 + '); hl.config({ cursor = { no_warps = false } }) end');
    }
    function focusWindow(w) {
        hide(() => ov.dispatchNoWarp('hl.dsp.focus({ window = "address:' + w.address + '" })'));
    }
    function closeWindow(w) {
        dispatch('hl.dsp.window.close({ window = "address:' + w.address + '" })');
        dropTimer.restart();
    }
    function moveWindow(w, wsId) {
        dispatch('hl.dsp.window.move({ window = "address:' + w.address + '", workspace = ' + wsId + ', follow = false })');
        dropTimer.restart();
    }
    function switchWs(id) {
        // focusing the workspace's most recent window switches to it AND makes
        // it the window Hyprland returns to when the overview closes
        const w = windowsOn(id)[0];
        switchTimer.cmd = w ? 'hl.dsp.focus({ window = "address:' + w.address + '" })'
                            : 'hl.dsp.focus({ workspace = ' + id + ' })';
        viewWs = id;
        selected = -1;
        kbRelease = true;
        switchTimer.restart();
    }
    // focus dispatches are ignored until ~60 ms after the layer drops the keyboard
    Timer {
        id: switchTimer
        property string cmd
        interval: 80
        onTriggered: {
            ov.dispatchNoWarp(cmd);   // the pointer stays on the card
            ov.kbRelease = false;
            search.forceActiveFocus();
            dropTimer.restart();
        }
    }
    Timer { id: dropTimer; interval: 120; onTriggered: ov.refresh() }

    // fuzzel opened from the overview (Super+R)
    Process {
        id: fuzzel
        property bool launched: false
        command: ["fuzzel", "--launch-prefix=" + Quickshell.shellDir + "/scripts/fuzzel-launch.sh"]
        onExited: {
            if (launched) ov.hide();
            else if (ov.open) search.forceActiveFocus();   // cancelled: back to the overview
        }
    }

    // ---------- data ----------
    function topFor(addr) {
        const ts = Hyprland.toplevels.values;
        for (let i = 0; i < ts.length; i++) {
            const a = ts[i].address;
            if (a === addr || "0x" + a === addr) return ts[i];
        }
        return null;
    }

    function windowsOn(id) {
        return clients
            .filter(c => c.workspace && c.workspace.id === id && c.mapped && !c.hidden)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
    }

    // windows of the viewed workspace with their real rect and grid slot
    readonly property rect gridArea: Qt.rect(80, 230, width - 160, height - 230 - 90)
    readonly property var windows: {
        const list = windowsOn(viewWs);
        const slots = layout(list, gridArea);
        return list.map((c, i) => ({
            address: c.address, title: c.title, cls: c.class,
            top: topFor(c.address),
            real: { x: c.at[0] - mon.x, y: c.at[1] - mon.y, w: c.size[0], h: c.size[1] },
            slot: slots[i]
        }));
    }

    // Pick the column count that gives the windows the most area, keep
    // aspect ratios, never upscale, centre each row.
    function layout(list, area) {
        const n = list.length, gap = 48;
        if (!n) return [];
        let best = null;
        for (let cols = 1; cols <= n; cols++) {
            const rows = Math.ceil(n / cols);
            const cw = (area.width - gap * (cols - 1)) / cols;
            const ch = (area.height - gap * (rows - 1)) / rows;
            let total = 0;
            const sizes = list.map(c => {
                const s = Math.min(cw / c.size[0], ch / c.size[1], 1);
                total += c.size[0] * s * c.size[1] * s;
                return { w: c.size[0] * s, h: c.size[1] * s };
            });
            if (!best || total > best.total) best = { cols, rows, ch, sizes, total };
        }
        const out = [];
        const rowH = best.ch;
        const usedH = best.rows * rowH + (best.rows - 1) * gap;
        let y0 = area.y + (area.height - usedH) / 2;
        for (let r = 0; r < best.rows; r++) {
            const row = best.sizes.slice(r * best.cols, (r + 1) * best.cols);
            const rowW = row.reduce((s, z) => s + z.w, 0) + gap * (row.length - 1);
            let x = area.x + (area.width - rowW) / 2;
            for (const z of row) {
                out.push({ x: x, y: y0 + (rowH - z.h) / 2, w: z.w, h: z.h });
                x += z.w + gap;
            }
            y0 += rowH + gap;
        }
        return out;
    }

    readonly property var workspaceIds: {
        let max = viewWs;
        for (const c of clients) if (c.workspace && c.workspace.id > max && c.workspace.id <= 10) max = c.workspace.id;
        const ids = [];
        for (let i = 1; i <= Math.min(10, max + 1); i++) ids.push(i);
        return ids;
    }

    // ---------- app search ----------
    readonly property string query: search.text.trim().toLowerCase()
    readonly property bool searching: query.length > 0 || appsMode
    readonly property var apps: {
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        if (!query) return all.slice().sort((a, b) => a.name.localeCompare(b.name));
        const scored = [];
        for (const e of all) {
            const name = (e.name || "").toLowerCase();
            let s = 0;
            if (name.startsWith(query)) s = 100;
            else if (name.split(/[\s-]/).some(w => w.startsWith(query))) s = 80;
            else if (name.indexOf(query) >= 0) s = 60;
            else if ((e.genericName || "").toLowerCase().indexOf(query) >= 0) s = 40;
            else if ((e.keywords || []).some(k => k.toLowerCase().startsWith(query))) s = 30;
            else if ((e.comment || "").toLowerCase().indexOf(query) >= 0) s = 10;
            if (s) scored.push({ e, s });
        }
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        return scored.map(x => x.e);
    }
    function launch(e) {
        const cmd = (e.command && e.command.length) ? e.command[0].split("/").pop() : "";
        expectLaunch([e.startupClass, e.id, cmd]);
        hide(() => e.execute());
    }
    // pin the app's first window to the workspace it is launched on (gnome-like.lua),
    // so switching workspaces while a slow app starts doesn't drag it along
    function launchWs() {
        const m = Hyprland.focusedMonitor;
        return m && m.activeWorkspace ? m.activeWorkspace.id : viewWs;
    }
    function expectLaunch(names) {
        const clean = names.map(n => String(n || "").replace(/[^A-Za-z0-9._-]/g, "")).filter(n => n.length > 1);
        if (!clean.length) return;
        dispatch('function() package.loaded["gnome-like"].expect_launch({"' + clean.join('","') + '"}, '
                 + launchWs() + ') end');
    }

    // ---------- background ----------
    Image {
        id: wall
        anchors.fill: parent
        source: Theme.wallpaper
        sourceSize: Qt.size(ov.width / 2, ov.height / 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true; blur: 1.0; blurMax: 48
        brightness: -0.12
        opacity: ov.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeOut } }
    }
    Rectangle {
        anchors.fill: parent
        color: Theme.bg0
        opacity: ov.open ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }
    }
    MouseArea { anchors.fill: parent; onClicked: ov.hide() }

    // ---------- keyboard ----------
    Item {
        anchors.fill: parent
        focus: true
        Keys.forwardTo: [search]
    }

    // ---------- search field ----------
    Rectangle {
        id: searchBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: ov.open ? 32 : -60
        Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEmph } }
        width: 460; height: 48; radius: Theme.radius
        color: Qt.rgba(Theme.bg0.r, Theme.bg0.g, Theme.bg0.b, 0.85)
        border.width: 2
        border.color: search.activeFocus ? Theme.yellowDim : Theme.bg2
        // clicks on the box focus the field instead of closing the overview
        MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }
        Text {
            id: sIcon
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: "search"; color: Theme.fg4
            font { family: Theme.fontIcons; pixelSize: 22 }
        }
        TextInput {
            id: search
            anchors { left: sIcon.right; leftMargin: 10; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            color: Theme.fg0
            selectionColor: Theme.yellowDim
            font { family: Theme.fontUi; pixelSize: 16; weight: Font.DemiBold }
            clip: true
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !search.text
                text: "Type to search apps"
                color: Theme.fg4
                font: search.font
            }
            Keys.onEscapePressed: {
                if (search.text) search.text = "";
                else if (ov.appsMode) ov.appsMode = false;
                else ov.hide();
            }
            Keys.onReturnPressed: {
                if (ov.searching) { if (ov.apps.length) ov.launch(ov.apps[Math.max(0, appGrid.currentIndex)]); }
                else if (ov.selected >= 0 && ov.selected < ov.windows.length) ov.focusWindow(ov.windows[ov.selected]);
            }
            Keys.onTabPressed: {
                if (!ov.searching && ov.windows.length) ov.selected = (ov.selected + 1) % ov.windows.length;
            }
            Keys.onPressed: (e) => {
                if (!ov.searching) return;
                const cols = appGrid.columns;
                if (e.key === Qt.Key_Right) { appGrid.currentIndex = Math.min(ov.apps.length - 1, appGrid.currentIndex + 1); e.accepted = true; }
                else if (e.key === Qt.Key_Left) { appGrid.currentIndex = Math.max(0, appGrid.currentIndex - 1); e.accepted = true; }
                else if (e.key === Qt.Key_Down) { appGrid.currentIndex = Math.min(ov.apps.length - 1, appGrid.currentIndex + cols); e.accepted = true; }
                else if (e.key === Qt.Key_Up) { appGrid.currentIndex = Math.max(0, appGrid.currentIndex - cols); e.accepted = true; }
            }
            onTextChanged: appGrid.currentIndex = 0
        }
    }

    // ---------- workspace strip ----------
    Row {
        id: strip
        anchors.horizontalCenter: parent.horizontalCenter
        y: 104
        spacing: 16
        opacity: ov.open && !ov.searching ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
        transform: Translate { y: ov.open ? 0 : -30; Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEmph } } }

        Repeater {
            model: ov.workspaceIds
            delegate: WorkspaceCard {
                required property int modelData
                wsId: modelData
                active: modelData === ov.viewWs
                screenSize: Qt.size(ov.mon.width, ov.mon.height)
                windows: ov.windowsOn(modelData).map(c => ({
                    real: { x: c.at[0] - ov.mon.x, y: c.at[1] - ov.mon.y, w: c.size[0], h: c.size[1] },
                    cls: c.class, top: ov.topFor(c.address) }))
                onClicked: ov.switchWs(modelData)
            }
        }
    }

    // ---------- windows ----------
    Item {
        anchors.fill: parent
        opacity: ov.searching ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }

        Repeater {
            model: ov.windows
            delegate: WindowThumb {
                required property var modelData
                required property int index
                win: modelData
                expanded: ov.open
                selected: index === ov.selected
                onActivated: ov.focusWindow(modelData)
                onCloseRequested: ov.closeWindow(modelData)
                onDroppedOn: (t) => { if (t && t.wsId !== undefined && t.wsId !== ov.viewWs) ov.moveWindow(modelData, t.wsId); }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: ov.open && ov.windows.length === 0
            text: "No windows on this workspace"
            color: Theme.fg4
            font { family: Theme.fontUi; pixelSize: 18; weight: Font.Bold }
        }
    }

    // ---------- app results ----------
    GridView {
        id: appGrid
        readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
        anchors { top: searchBox.bottom; topMargin: 40; bottom: parent.bottom; bottomMargin: 40; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width - 160, 8 * 150)
        cellWidth: 150; cellHeight: 150
        clip: true
        model: ov.searching ? ov.apps : []
        opacity: ov.searching && ov.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.durMed } }
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false
        currentIndex: 0

        delegate: Item {
            id: appCell
            required property var modelData
            required property int index
            readonly property bool current: GridView.isCurrentItem
            width: 150; height: 150
            Rectangle {
                anchors { fill: parent; margins: 8 }
                radius: Theme.radius
                color: appCell.current ? Qt.rgba(Theme.yellowDim.r, Theme.yellowDim.g, Theme.yellowDim.b, 0.3)
                     : ah.hovered ? Qt.rgba(Theme.bg2.r, Theme.bg2.g, Theme.bg2.b, 0.8) : "transparent"
                border.width: appCell.current ? 2 : 0
                border.color: Theme.yellowDim
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64; height: 64
                        sourceSize: Qt.size(128, 128)
                        source: Quickshell.iconPath(appCell.modelData.icon, "application-x-executable")
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 124
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        text: appCell.modelData.name
                        color: Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                    }
                }
                HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: ov.launch(appCell.modelData) }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: ov.searching && ov.apps.length === 0
            text: "No apps match “" + search.text + "”"
            color: Theme.fg4
            font { family: Theme.fontUi; pixelSize: 18; weight: Font.Bold }
        }
    }

    // While fuzzel is open the overview is inert: no hover, and any click
    // outside fuzzel (which sits above this layer) closes fuzzel only.
    MouseArea {
        id: fuzzelShield
        anchors.fill: parent
        z: 1000
        visible: fuzzel.running
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPressed: fuzzel.signal(15)
        onWheel: {}
    }
}
