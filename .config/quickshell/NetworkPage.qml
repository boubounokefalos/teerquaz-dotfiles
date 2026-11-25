import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings → Network: status + traffic, devices, Wi-Fi (when there is a card),
// details, and per-profile settings (autoconnect, DHCP / manual IPv4, DNS).
// Changing the IPv4 settings of the connection in use must be confirmed
// within 20 s, or the old settings come back.
ColumnLayout {
    id: page
    spacing: 14

    property bool shown: false
    onShownChanged: { Net.rateUsers += shown ? 1 : -1; if (shown) Net.refresh(); }

    // ---------- profile editor ----------
    property string editUuid: ""
    readonly property var editProfile: Net.profiles.find(p => p.uuid === editUuid) || null
    // pick the active wired profile (or the first one) when nothing is chosen yet
    readonly property var editable: Net.profiles.filter(p => p.type === "802-3-ethernet" || p.type === "802-11-wireless")
    onEditableChanged: if (!editProfile && editable.length) {
        const a = editable.find(p => p.active);
        editUuid = (a || editable[0]).uuid;
    }
    onEditUuidChanged: loadProfile()

    property var cur: ({})            // values as stored in NM
    property string method: "auto"    // edited values
    property bool dirty: false
    property var previous: null       // for revert
    property int countdown: 0

    function loadProfile() {
        if (!editUuid) return;
        profRead.command = ["nmcli", "-t", "-f", "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,connection.autoconnect,connection.interface-name", "connection", "show", "uuid", editUuid];
        profRead.running = true;
    }
    Process {
        id: profRead
        stdout: StdioCollector {
            onStreamFinished: {
                const v = {};
                for (const line of text.split("\n")) {
                    if (!line) continue;
                    const f = Net.fields(line);
                    v[f[0]] = f.slice(1).join(":");
                }
                page.cur = v;
                page.method = v["ipv4.method"] === "manual" ? "manual" : "auto";
                addr.text = v["ipv4.addresses"] || "";
                gw.text = v["ipv4.gateway"] || "";
                dns.text = (v["ipv4.dns"] || "").split(",").join(", ");
                page.dirty = false;
            }
        }
    }
    readonly property bool addrOk: method !== "manual" || /^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/.test(addr.text.trim())
    readonly property bool gwOk: !gw.text.trim() || /^\d{1,3}(\.\d{1,3}){3}$/.test(gw.text.trim())
    readonly property bool dnsOk: dns.text.trim().split(/[\s,]+/).filter(x => x).every(x => /^[0-9a-fA-F:.]+$/.test(x))

    function apply() {
        if (!editProfile || !addrOk || !gwOk || !dnsOk) return;
        const live = editProfile.active;
        if (live) previous = { method: cur["ipv4.method"] === "manual" ? "manual" : "auto",
                               addresses: cur["ipv4.addresses"] || "", gateway: cur["ipv4.gateway"] || "",
                               dns: cur["ipv4.dns"] || "" };
        Net.setIpv4(editUuid, { method: method, addresses: addr.text.trim(), gateway: gw.text.trim(), dns: dns.text }, live);
        dirty = false;
        reloadLater.restart();
        if (live) { countdown = 20; tick.start(); }
    }
    function keep() { tick.stop(); countdown = 0; previous = null; }
    function revert() {
        tick.stop(); countdown = 0;
        if (previous) Net.setIpv4(editUuid, previous, true);
        previous = null;
        reloadLater.restart();
        Quickshell.execDetached(["qs", "ipc", "call", "osd", "message", "lan", "Network settings reverted"]);
    }
    Timer { id: tick; interval: 1000; repeat: true; onTriggered: { page.countdown--; if (page.countdown <= 0) page.revert(); } }
    Timer { id: reloadLater; interval: 1500; onTriggered: page.loadProfile() }

    function typeName(t) { return t === "802-3-ethernet" || t === "ethernet" ? "Wired" : t === "802-11-wireless" || t === "wifi" ? "Wi-Fi" : t === "vpn" || t === "wireguard" ? "VPN" : t; }

    // ================= status =================
    SectionTitle { text: "Network" }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 96
        radius: 16
        color: Theme.bg1
        Rectangle {
            id: bigIcon
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            width: 56; height: 56; radius: 28
            color: Net.connected ? Theme.blueDim : Theme.bg2
            Text {
                anchors.centerIn: parent
                text: Net.icon
                color: Net.connected ? Theme.textOnBlue : Theme.fg4
                font { family: Theme.fontIcons; pixelSize: 30 }
            }
        }
        Column {
            anchors { left: bigIcon.right; leftMargin: 16; right: traffic.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                width: parent.width; elide: Text.ElideRight
                text: Net.title
                color: Theme.fg0
                font { family: Theme.fontDisplay; pixelSize: 22; weight: Font.Bold }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: Net.statusText + (Net.primary ? "  ·  " + Net.primary.name : "")
                color: Net.connected && Net.connectivity !== "full" ? Theme.orange : Theme.fg4
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
        }
        Column {
            id: traffic
            visible: Net.connected
            anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
            spacing: 4
            Row {
                spacing: 6
                Text { text: "arrow_downward"; color: Theme.blue; font { family: Theme.fontIcons; pixelSize: 18 } }
                Text { width: 80; text: Net.rate(Net.rxRate); color: Theme.fg1; font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold } }
            }
            Row {
                spacing: 6
                Text { text: "arrow_upward"; color: Theme.yellow; font { family: Theme.fontIcons; pixelSize: 18 } }
                Text { width: 80; text: Net.rate(Net.txRate); color: Theme.fg1; font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold } }
            }
        }
    }

    Text {
        visible: Net.lastError !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Net.lastError
        color: Theme.red
        font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
    }

    SettingRow {
        label: "Networking"; hint: "Turning this off disconnects every device"
        Toggle { checked: Net.networking; onToggled: (v) => Net.setNetworking(v) }
    }

    // ================= devices =================
    SectionTitle { text: "Devices"; Layout.topMargin: 14 }
    Repeater {
        model: Net.devices
        delegate: SettingRow {
            required property var modelData
            label: page.typeName(modelData.type) + "  ·  " + modelData.name
            hint: modelData.state === "connected" ? "Connected to " + modelData.connection
                : modelData.state.startsWith("connecting") ? "Connecting…"
                : modelData.state === "unavailable" ? "Cable unplugged or device unavailable"
                : modelData.state.charAt(0).toUpperCase() + modelData.state.slice(1)
            Toggle {
                checked: modelData.state === "connected" || modelData.state.startsWith("connecting")
                onToggled: (v) => v ? Net.connectDevice(modelData.name) : Net.disconnectDevice(modelData.name)
            }
        }
    }
    Text {
        visible: Net.devices.length === 0
        text: "No wired or Wi-Fi devices found."
        color: Theme.fg4
        font { family: Theme.fontUi; pixelSize: 13 }
    }

    // ================= Wi-Fi =================
    ColumnLayout {
        visible: Net.hasWifi
        Layout.fillWidth: true
        Layout.topMargin: 14
        spacing: 14
        property string joining: ""      // SSID whose password row is open

        id: wifi
        RowLayout {
            Layout.fillWidth: true
            SectionTitle { text: "Wi-Fi"; Layout.fillWidth: true }
            PillButton { text: "Scan"; visible: Net.wifiEnabled; onClicked: Net.rescan() }
            Toggle { checked: Net.wifiEnabled; onToggled: (v) => Net.setWifi(v) }
        }
        Repeater {
            model: Net.wifiEnabled ? Net.wifiList : []
            delegate: Rectangle {
                id: wrow
                required property var modelData
                readonly property bool known: Net.profiles.some(p => p.name === modelData.ssid)
                readonly property bool asking: wifi.joining === modelData.ssid
                Layout.fillWidth: true
                implicitHeight: asking ? 104 : 52
                radius: Theme.radius
                color: modelData.inUse ? Theme.bg1 : (wh.hovered ? Theme.bg1 : Theme.clear(Theme.bg1))
                Behavior on implicitHeight { NumberAnimation { duration: Theme.durMed; easing.type: Theme.easeEmph } }
                clip: true
                HoverHandler { id: wh }

                Row {
                    x: 14; y: 14
                    spacing: 12
                    Text {
                        text: wrow.modelData.signal > 75 ? "signal_wifi_4_bar" : wrow.modelData.signal > 50 ? "network_wifi_3_bar"
                            : wrow.modelData.signal > 25 ? "network_wifi_2_bar" : "network_wifi_1_bar"
                        color: wrow.modelData.inUse ? Theme.blue : Theme.fg1
                        font { family: Theme.fontIcons; pixelSize: 20 }
                    }
                    Text {
                        text: wrow.modelData.ssid
                        color: Theme.fg1
                        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                    }
                    Text {
                        visible: wrow.modelData.security !== ""
                        text: "lock"; color: Theme.fg4
                        font { family: Theme.fontIcons; pixelSize: 16 }
                    }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 6 }
                    spacing: 8
                    PillButton {
                        visible: wrow.known && !wrow.modelData.inUse
                        text: "Forget"
                        onClicked: { const p = Net.profiles.find(p => p.name === wrow.modelData.ssid); if (p) Net.forget(p.uuid); }
                    }
                    PillButton {
                        text: wrow.modelData.inUse ? "Disconnect" : "Connect"
                        primary: !wrow.modelData.inUse
                        onClicked: {
                            if (wrow.modelData.inUse) {
                                const d = Net.devices.find(d => d.type === "wifi");
                                if (d) Net.disconnectDevice(d.name);
                            } else if (wrow.known || !wrow.modelData.security) Net.connectWifi(wrow.modelData.ssid, "");
                            else { wifi.joining = wrow.modelData.ssid; pw.text = ""; pw.forceActiveFocus(); }
                        }
                    }
                }
                Row {
                    visible: wrow.asking
                    x: 14; y: 56
                    spacing: 8
                    TextBox {
                        id: pw
                        width: wrow.width - 220
                        password: true
                        placeholder: "Password"
                        onAccepted: { Net.connectWifi(wrow.modelData.ssid, text); wifi.joining = ""; }
                    }
                    PillButton { text: "Cancel"; onClicked: wifi.joining = "" }
                    PillButton { text: "Join"; primary: true; onClicked: { Net.connectWifi(wrow.modelData.ssid, pw.text); wifi.joining = ""; } }
                }
            }
        }
    }

    // ================= details =================
    SectionTitle { text: "Details"; Layout.topMargin: 14; visible: Net.connected }
    Rectangle {
        visible: Net.connected
        Layout.fillWidth: true
        implicitHeight: detGrid.implicitHeight + 32
        radius: 16
        color: Theme.bg1
        GridLayout {
            id: detGrid
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            columns: 2
            columnSpacing: 24
            rowSpacing: 8
            Repeater {
                model: [
                    ["IPv4 address", (Net.details.ip4 || []).join("\n")],
                    ["Gateway", Net.details.gateway || ""],
                    ["DNS", (Net.details.dns || []).join("\n")],
                    ["IPv6 address", (Net.details.ip6 || []).join("\n")],
                    ["Hardware address", Net.details.mac || ""],
                    ["Link speed", Net.details.speed || ""]
                ].filter(r => r[1])
                delegate: Item {
                    required property var modelData
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    implicitHeight: Math.max(k.implicitHeight, v.implicitHeight)
                    Text {
                        id: k
                        width: 160
                        text: modelData[0]
                        color: Theme.fg4
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                    }
                    TextEdit {   // selectable, so addresses can be copied
                        id: v
                        anchors { left: k.right; leftMargin: 16; right: parent.right }
                        readOnly: true
                        selectByMouse: true
                        wrapMode: Text.WrapAnywhere
                        text: modelData[1]
                        color: Theme.fg1
                        selectionColor: Theme.yellowDim
                        selectedTextColor: Theme.bg0
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                    }
                }
            }
        }
    }

    // ================= profile settings =================
    SectionTitle { text: "Connection settings"; Layout.topMargin: 14; visible: page.editable.length > 0 }

    SettingRow {
        visible: page.editable.length > 1
        label: "Profile"; hint: "Saved connections on this computer"
        Dropdown {
            model: page.editable.map(p => p.name)
            current: page.editProfile ? page.editProfile.name : ""
            onPicked: (v) => { const p = page.editable.find(p => p.name === v); if (p) page.editUuid = p.uuid; }
        }
    }
    SettingRow {
        visible: page.editProfile !== null
        label: page.editProfile ? page.editProfile.name : ""
        hint: page.editProfile ? page.typeName(page.editProfile.type) + (page.editProfile.active ? "  ·  in use" : "  ·  not in use") : ""
        Row {
            spacing: 8
            PillButton {
                visible: page.editProfile !== null && !page.editProfile.active
                text: "Connect"; primary: true
                onClicked: Net.up(page.editUuid)
            }
            PillButton {
                visible: page.editProfile !== null && page.editProfile.active
                text: "Disconnect"
                onClicked: Net.down(page.editUuid)
            }
        }
    }
    SettingRow {
        visible: page.editProfile !== null
        label: "Connect automatically"; hint: "Use this profile when the device is available"
        Toggle {
            checked: page.editProfile ? page.editProfile.autoconnect : false
            onToggled: (v) => Net.setAutoconnect(page.editUuid, v)
        }
    }
    SettingRow {
        visible: page.editProfile !== null
        label: "IPv4"; hint: page.method === "manual" ? "Fixed address you enter below" : "Address from the router (DHCP)"
        Dropdown {
            model: ["Automatic (DHCP)", "Manual"]
            current: page.method === "manual" ? "Manual" : "Automatic (DHCP)"
            onPicked: (v) => { page.method = v === "Manual" ? "manual" : "auto"; page.dirty = true;
                               if (page.method === "manual" && !addr.text && Net.details.ip4 && Net.details.ip4.length) {
                                   addr.text = Net.details.ip4[0]; gw.text = Net.details.gateway || "";
                               } }
        }
    }
    SettingRow {
        visible: page.editProfile !== null && page.method === "manual"
        label: "Address"; hint: "With prefix, e.g. 192.168.1.50/24"
        TextBox { id: addr; placeholder: "192.168.1.50/24"; invalid: !page.addrOk; onTextChanged: if (editing) page.dirty = true }
    }
    SettingRow {
        visible: page.editProfile !== null && page.method === "manual"
        label: "Gateway"; hint: "Usually your router"
        TextBox { id: gw; placeholder: "192.168.1.1"; invalid: !page.gwOk; onTextChanged: if (editing) page.dirty = true }
    }
    SettingRow {
        visible: page.editProfile !== null
        label: "DNS servers"; hint: page.method === "manual" ? "Separate with commas" : "Leave empty to use the router's; otherwise these are added first"
        TextBox { id: dns; placeholder: page.method === "manual" ? "1.1.1.1, 9.9.9.9" : "Automatic"; invalid: !page.dnsOk; onTextChanged: if (editing) page.dirty = true }
    }

    RowLayout {
        visible: page.editProfile !== null
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: page.countdown > 0 ? "Keep these settings? Reverting in " + page.countdown + " s"
                : page.dirty && page.editProfile && page.editProfile.active ? "Applying reconnects this profile; you'll have 20 s to keep the change."
                : ""
            color: page.countdown > 0 ? Theme.orange : Theme.fg4
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
        }
        PillButton { visible: page.countdown > 0; text: "Revert"; onClicked: page.revert() }
        PillButton { visible: page.countdown > 0; text: "Keep"; primary: true; onClicked: page.keep() }
        PillButton { visible: page.countdown === 0 && page.dirty; text: "Reset"; onClicked: page.loadProfile() }
        PillButton {
            visible: page.countdown === 0
            text: "Apply"; primary: page.dirty
            opacity: page.dirty && page.addrOk && page.gwOk && page.dnsOk ? 1 : 0.5
            onClicked: if (page.dirty) page.apply()
        }
    }

    SettingRow {
        label: "Advanced"; hint: "VPN, proxies, IPv6 and everything else NetworkManager can do"
        PillButton { text: "Open connection editor"; onClicked: Quickshell.execDetached(["nm-connection-editor"]) }
    }
}
