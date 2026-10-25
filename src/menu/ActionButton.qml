import QtQuick

// One action in the rift: icon over label, laid along the rift's angle by the menu. A soft glow
// behind it shows the selection, swells while it is held (the rift's edges feed it, see
// shaders/layers/charge.frag) and flashes when it pulses on the way to running.
Item {
    id: btn

    required property string label
    required property string icon
    required property string hotkey
    required property bool needsHold

    property bool selected: false
    property real holdProgress: 0 // 0..1 while held
    property real pulse: 0        // 0..1 while pulsing before it runs
    property real appear: 0       // 0 hidden .. 1 shown
    property color accent: "#cba6f7"
    property string iconFamily
    property string labelFamily

    readonly property real swell: Math.sin(Math.PI * pulse)

    width: 150
    height: 96
    opacity: appear
    scale: (0.85 + 0.15 * appear) * (selected ? 1.05 : 1) * (1 + 0.08 * holdProgress + 0.14 * swell)

    Behavior on scale {
        enabled: btn.pulse === 0 && btn.holdProgress === 0
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    property real selectGlow: selected ? 1 : 0
    Behavior on selectGlow {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    ShaderEffect {
        readonly property real grow: 1 + 0.9 * btn.holdProgress + 0.5 * btn.swell
        anchors.centerIn: parent
        width: 230 * grow
        height: 130 * (1 + 0.25 * (grow - 1))
        visible: opacity > 0
        opacity: Math.min(1, 0.32 * btn.selectGlow + 0.55 * btn.holdProgress + 0.6 * btn.swell)
        property color uColor: btn.accent
        fragmentShader: Qt.resolvedUrl("../shaders/qsb/halo.qsb")
    }

    Column {
        anchors.centerIn: parent
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.icon
            font.family: btn.iconFamily
            font.pixelSize: 34
            font.variableAxes: {
                "FILL": btn.selected || btn.pulse > 0 ? 1 : 0
            }
            color: btn.selected || btn.pulse > 0 ? "#ffffff" : btn.accent
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.label
            font.family: btn.labelFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.letterSpacing: 0.4
            color: "#eceaf4"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: btn.hotkey !== ""
            text: btn.needsHold ? `hold ${btn.hotkey}` : btn.hotkey
            font.family: btn.labelFamily
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.45)
        }
    }
}
