import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// What the lock screen shows besides the password: who you are, battery, network, Bluetooth,
// Caps Lock and the media player. Network and Caps Lock are polled only while `active`.
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

    // Bluetooth (when there is an adapter): off, on, or what's connected
    readonly property bool hasBluetooth: Bluetooth.defaultAdapter !== null
    readonly property bool bluetoothOn: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property var bluetoothConnected: Bluetooth.devices.values.filter(d => d.connected)
    readonly property string bluetoothIcon: !bluetoothOn ? "bluetooth_disabled" : bluetoothConnected.length > 0 ? "bluetooth_connected" : "bluetooth"
    readonly property string bluetoothText: {
        if (!bluetoothOn)
            return "Off";
        if (bluetoothConnected.length === 0)
            return "On";
        if (bluetoothConnected.length === 1)
            return bluetoothConnected[0].name || bluetoothConnected[0].deviceName;
        return `${bluetoothConnected.length} devices`;
    }

    // Caps Lock, from the keyboards' LEDs: neither Qt nor Quickshell exposes the lock state.
    property bool capsLock: false
    property var capsLeds: []

    // Media: the playing player, else the first one
    readonly property var player: {
        const players = Mpris.players.values;
        return players.find(p => p.isPlaying) ?? players[0] ?? null;
    }

    onActiveChanged: {
        if (active)
            findLeds.running = true; // keyboards come and go
    }

    Process {
        id: findLeds
        command: ["sh", "-c", "for f in /sys/class/leds/*::capslock/brightness; do [ -e \"$f\" ] && echo \"$f\"; done"]
        stdout: StdioCollector {
            onStreamFinished: info.capsLeds = text.split("\n").filter(l => l !== "")
        }
    }

    Variants {
        id: leds
        model: info.capsLeds

        FileView {
            required property string modelData
            path: modelData
            blockLoading: true
            printErrors: false
        }
    }

    Timer {
        interval: 250
        repeat: true
        triggeredOnStart: true
        running: info.active && info.capsLeds.length > 0
        onTriggered: {
            let on = false;
            for (const led of leds.instances) {
                led.reload();
                on = on || parseInt(led.text()) > 0;
            }
            info.capsLock = on;
        }
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
