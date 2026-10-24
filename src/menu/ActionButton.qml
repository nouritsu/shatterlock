import QtQuick

// One action in the rift: icon over label, laid along the rift's angle by the menu. Shows the
// selection, the hotkey, and the hold-to-confirm fill.
Item {
    id: btn

    required property string label
    required property string icon
    required property string hotkey
    required property bool needsHold

    property bool selected: false
    property real holdProgress: 0 // 0..1 while held
    property real appear: 0       // 0 hidden .. 1 shown
    property color accent: "#cba6f7"
    property string iconFamily
    property string labelFamily

    width: 150
    height: 96
    opacity: appear
    scale: (0.85 + 0.15 * appear) * (selected ? 1.05 : 1)

    Behavior on scale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, btn.selected ? 0.16 : 0)
        border.width: 1
        border.color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, btn.selected ? 0.6 : 0)

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    // Fills along the button while it is held.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * btn.holdProgress
        radius: plate.radius
        color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, 0.4)
        visible: btn.holdProgress > 0
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
                "FILL": btn.selected ? 1 : 0
            }
            color: btn.selected ? "#ffffff" : btn.accent
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
