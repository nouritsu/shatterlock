import QtQuick
import Quickshell
import Quickshell.Io

// The FIDO security keys plugged in: hidraw devices whose HID report descriptor has the FIDO usage
// page (0xF1D0, the item `06 d0 f1`). Both live in sysfs and need no permissions. While `active`,
// udev's hidraw events trigger a rescan, so a key plugged in shows up at once and nothing polls;
// without udevadm it rescans every few seconds instead.
Scope {
    id: keys

    property bool active: false
    property var names: [] // the keys' product names, e.g. "Yubico YubiKey FIDO+CCID"
    readonly property bool present: names.length > 0

    property bool scanned: false // since it went active
    property bool polling: false

    // A key was plugged in (not one that was already there when it went active).
    signal plugged

    onActiveChanged: {
        if (active) {
            polling = false;
            monitor.running = true;
            scan();
        } else {
            monitor.running = false;
            scanned = false;
            names = [];
        }
    }

    // Running already: it runs once more when done (Process queues one restart).
    function scan() {
        scanner.running = true;
    }

    Process {
        id: scanner
        command: ["sh", "-c", 'for d in /sys/class/hidraw/*; do od -An -tx1 -v "$d/device/report_descriptor" 2>/dev/null | tr -s " \\n" "  " | grep -q " 06 d0 f1" && sed -n "s/^HID_NAME=//p" "$d/device/uevent"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                if (!keys.active)
                    return;
                const found = text.split("\n").filter(n => n !== "");
                const more = found.length > keys.names.length;
                if (found.join("\n") !== keys.names.join("\n"))
                    keys.names = found;
                if (more && keys.scanned)
                    keys.plugged();
                keys.scanned = true;
            }
        }
    }

    // A hidraw device came or went. udev reports after its rules ran, so the device's permissions
    // are in place by the time PAM opens it.
    Process {
        id: monitor
        property bool started: false
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=hidraw"]
        stdout: SplitParser {
            onRead: line => {
                if (/^UDEV\s/.test(line))
                    rescan.restart();
            }
        }
        onStarted: started = true
        onRunningChanged: {
            if (running || !keys.active)
                return;
            if (!started)
                console.warn("shatterlock: udevadm isn't available; looking for security keys every 3 s instead");
            started = false;
            keys.polling = true;
        }
    }

    // One event per interface; a key has several.
    Timer {
        id: rescan
        interval: 150
        onTriggered: keys.scan()
    }

    Timer {
        interval: 3000
        repeat: true
        running: keys.active && keys.polling
        onTriggered: keys.scan()
    }
}
