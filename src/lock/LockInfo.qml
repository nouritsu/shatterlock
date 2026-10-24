import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// What the lock screen shows besides the password: who you are, battery, network and the media
// player. Network is polled (nmcli) only while `active`.
Scope {
    id: info

    property bool active: false

    // User
    readonly property string userName: Quickshell.env("USER") ?? ""
    property string fullName: ""
    readonly property var avatarCandidates: [`/var/lib/AccountsService/icons/${userName}`, `${Quickshell.env("HOME")}/.face`, `${Quickshell.env("HOME")}/.face.icon`]

    // Battery (laptops only)
    readonly property bool hasBattery: UPower.devices.values.some(d => d.isLaptopBattery)
    readonly property int batteryPercent: Math.round((UPower.displayDevice?.percentage ?? 0) * 100)
    readonly property bool charging: UPower.displayDevice?.state === UPowerDeviceState.Charging || UPower.displayDevice?.state === UPowerDeviceState.FullyCharged
    readonly property string batteryIcon: {
        if (charging)
            return "battery_charging_full";
        const bars = Math.max(0, Math.min(6, Math.round(batteryPercent / 100 * 6)));
        return batteryPercent >= 95 ? "battery_full" : `battery_${bars}_bar`;
    }

    // Network: "wifi" | "ethernet" | "" (offline)
    property string netKind: ""
    property string netName: ""
    property int wifiSignal: 0
    readonly property string netIcon: netKind === "ethernet" ? "lan" : netKind === "wifi" ? (wifiSignal >= 75 ? "signal_wifi_4_bar" : wifiSignal >= 50 ? "network_wifi_3_bar" : wifiSignal >= 25 ? "network_wifi_2_bar" : "network_wifi_1_bar") : "signal_wifi_off"

    // Media: the playing player, else the first one
    readonly property var player: {
        const players = Mpris.players.values;
        return players.find(p => p.isPlaying) ?? players[0] ?? null;
    }

    Process {
        running: true
        command: ["getent", "passwd", info.userName]
        stdout: StdioCollector {
            onStreamFinished: info.fullName = (text.split(":")[4] ?? "").split(",")[0]
        }
    }

    Process {
        id: nmcli
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null; echo --; nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [devices, wifi] = text.split("--\n");
                let kind = "", name = "";
                for (const line of (devices ?? "").split("\n")) {
                    const [type, state, ...rest] = line.split(":");
                    if (state !== "connected")
                        continue;
                    if (type === "ethernet" || (type === "wifi" && kind !== "ethernet")) {
                        kind = type;
                        name = rest.join(":");
                    }
                }
                const inUse = (wifi ?? "").split("\n").find(l => l.startsWith("*"));
                info.netKind = kind;
                info.netName = name;
                info.wifiSignal = inUse ? parseInt(inUse.split(":")[1]) || 0 : 0;
            }
        }
    }

    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: info.active
        onTriggered: nmcli.running = true
    }
}
