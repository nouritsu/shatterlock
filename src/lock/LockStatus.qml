pragma ComponentBehavior: Bound

import QtQuick

// The lock screen's status row: network, Bluetooth, a security key that can unlock (while one is
// plugged in), Caps Lock (while it's on) and battery.
Row {
    id: status

    required property var info
    property var methods: [] // the lock methods (AuthMethod)
    property color accent: "#cba6f7"
    property color ink: "#eceaf4"
    property string iconFamily
    property string labelFamily

    spacing: 22

    component Entry: Row {
        property string icon
        property string label
        spacing: 5

        Text {
            text: parent.icon
            font.family: status.iconFamily
            font.pixelSize: 22
            color: status.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            font.family: status.labelFamily
            font.pixelSize: 14
            color: status.ink
        }
    }

    Entry {
        icon: status.info.netIcon
        label: status.info.netName || "Offline"
    }
    Entry {
        visible: status.info.hasBluetooth
        icon: status.info.bluetoothIcon
        label: status.info.bluetoothText
    }
    Repeater {
        model: status.methods.filter(m => m.detects && m.ready && m.present)

        Entry {
            required property var modelData
            icon: modelData.icon
            label: modelData.label
        }
    }
    Entry {
        visible: status.info.capsLock
        icon: "keyboard_capslock"
        label: "Caps Lock"
    }
    Entry {
        visible: status.info.hasBattery
        icon: status.info.batteryIcon
        label: `${status.info.batteryPercent}%`
    }
}
