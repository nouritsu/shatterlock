import QtQuick
import Quickshell

// Locked outputs other than the rift's: dark fog in the accent's tint, with the time.
Item {
    id: fog

    required property var rift

    ShaderEffect {
        anchors.fill: parent
        property real iTime: 0
        property vector2d iResolution: Qt.vector2d(width, height)
        property color uAccent: fog.rift.effectiveAccent ?? fog.rift.accent
        property color uVoid: fog.rift.voidColor
        fragmentShader: Qt.resolvedUrl("../shaders/qsb/fog.qsb")

        FrameAnimation {
            running: true
            onTriggered: parent.iTime = elapsedTime
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        anchors.centerIn: parent
        text: Qt.formatTime(clock.date, fog.rift.cfg.lock?.timeFormat ?? "HH:mm")
        font.family: fog.rift.labelFamily
        font.pixelSize: 56
        font.weight: Font.Light
        color: Qt.rgba(1, 1, 1, 0.55)
    }
}
