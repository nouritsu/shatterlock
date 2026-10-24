import QtQuick

// A line of text laid along the rift: what is happening ("Shutting down…") or what went wrong.
Item {
    id: status

    property string text
    property bool isError: false
    property real appear: 0
    property point at
    property real angle: 0
    property color accent: "#cba6f7"
    property string family

    x: at.x - width / 2
    y: at.y - height / 2
    width: 1000
    height: 64
    rotation: angle
    opacity: appear
    visible: appear > 0

    Text {
        id: label
        anchors.centerIn: parent
        text: status.text
        font.family: status.family
        font.pixelSize: status.isError ? 18 : 28
        font.weight: Font.DemiBold
        font.letterSpacing: status.isError ? 0.2 : 1.2
        color: status.isError ? "#ff9a9a" : "#f4f0ff"
        style: Text.Outline
        styleColor: Qt.rgba(status.accent.r, status.accent.g, status.accent.b, 0.35)

        SequentialAnimation on opacity {
            running: status.visible && !status.isError
            loops: Animation.Infinite
            NumberAnimation {
                to: 0.55
                duration: 700
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1
                duration: 700
                easing.type: Easing.InOutSine
            }
        }
    }
}
