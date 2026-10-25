pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets

// Now playing on the lock screen: cover, title and artist, and the transport controls.
Row {
    id: media

    required property var player
    property color accent: "#cba6f7"
    property color ink: "#eceaf4"
    property string iconFamily
    property string labelFamily

    spacing: 12

    ClippingRectangle {
        width: 52
        height: 52
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.06)
        Image {
            anchors.fill: parent
            source: media.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(104, 104)
            asynchronous: true
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: 200
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: media.player?.trackTitle || "Unknown title"
            font.family: media.labelFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: media.ink
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: media.player?.trackArtist ?? ""
            font.family: media.labelFamily
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.6)
        }
    }

    Row {
        id: controls
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: [
                {
                    icon: "skip_previous",
                    enabled: media.player?.canGoPrevious ?? false,
                    act: () => media.player.previous()
                },
                {
                    icon: media.player?.isPlaying ? "pause" : "play_arrow",
                    enabled: media.player?.canTogglePlaying ?? false,
                    act: () => media.player.togglePlaying()
                },
                {
                    icon: "skip_next",
                    enabled: media.player?.canGoNext ?? false,
                    act: () => media.player.next()
                }
            ]

            Text {
                required property var modelData
                width: 30
                horizontalAlignment: Text.AlignHCenter
                text: modelData.icon
                font.family: media.iconFamily
                font.pixelSize: 26
                color: modelData.enabled ? (tap.containsMouse ? "#ffffff" : media.accent) : Qt.rgba(1, 1, 1, 0.25)

                MouseArea {
                    id: tap
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: parent.modelData.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.modelData.act()
                }
            }
        }
    }
}
