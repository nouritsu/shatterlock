pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

// The lock screen's contents: the clock, what's playing and the status row out over the halves,
// who is locked in and the password in the rift. Shown by the lock surface (and by the overlay
// while sealing and in preview).
Item {
    id: ui

    required property var rift
    required property var locker
    required property var info
    property real appear: 1

    readonly property real angle: rift.crack?.angle ?? 0
    readonly property color accent: rift.effectiveAccent ?? rift.accent
    readonly property color ink: "#eceaf4"
    readonly property var options: rift.cfg.lock ?? ({})

    // The middle of the rift, where the crack is kept flat for the user block (see
    // RiftWindow.lockBlock), and how much the block shrinks to fit a steep rift.
    readonly property point middle: {
        const p = rift.crack?.pointAt(0.5);
        return p ? Qt.point(p.x, p.y) : Qt.point(width / 2, height / 2);
    }
    readonly property real fit: Math.min(1, (rift.lockGap / 2 - 6) / rift.blockReach(angle).across)
    readonly property bool typing: input.text.length > 0

    function focusInput() {
        input.forceActiveFocus();
    }

    anchors.fill: parent
    opacity: appear
    visible: appear > 0

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // Out of the rift, over the halves: the time and date with what's playing under them in a
    // top corner, the status row in a bottom one (corners the rift doesn't end in). A soft shadow
    // keeps them readable over the frosted and glass blurs.
    readonly property bool mirrored: rift.cfg.rift?.corners === "tl-br"

    Column {
        x: ui.mirrored ? parent.width - width - 40 : 40
        y: 24
        spacing: 18
        layer.enabled: true
        layer.effect: Shadow {}

        Column {
            anchors.right: ui.mirrored ? parent.right : undefined
            spacing: -6

            Text {
                anchors.right: ui.mirrored ? parent.right : undefined
                text: Qt.formatTime(clock.date, ui.options.timeFormat ?? "HH:mm")
                font.family: ui.rift.labelFamily
                font.pixelSize: 88
                font.weight: Font.Light
                color: ui.ink
            }
            Text {
                anchors.right: ui.mirrored ? parent.right : undefined
                leftPadding: ui.mirrored ? 0 : 4
                rightPadding: ui.mirrored ? 4 : 0
                text: Qt.formatDate(clock.date, ui.options.dateFormat ?? "dddd, d MMMM")
                font.family: ui.rift.labelFamily
                font.pixelSize: 20
                color: Qt.rgba(1, 1, 1, 0.75)
            }
        }

        LockMedia {
            anchors.right: ui.mirrored ? parent.right : undefined
            visible: (ui.options.showMedia ?? true) && ui.info.player !== null
            player: ui.info.player
            accent: ui.accent
            ink: ui.ink
            iconFamily: ui.rift.iconFamily
            labelFamily: ui.rift.labelFamily
        }
    }

    LockStatus {
        x: ui.mirrored ? 40 : parent.width - width - 40
        y: parent.height - height - 28
        visible: ui.options.showStatus ?? true
        info: ui.info
        accent: ui.accent
        ink: ui.ink
        iconFamily: ui.rift.iconFamily
        labelFamily: ui.rift.labelFamily
        layer.enabled: true
        layer.effect: Shadow {}
    }

    component Shadow: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.7)
        shadowBlur: 0.8
        shadowVerticalOffset: 2
        shadowHorizontalOffset: 0
    }

    // In the rift: who is locked in, upright in the middle, with PAM's prompt or its last message
    // under it. Typing sends it back into the rift, and the password appears as orbs instead.
    Column {
        id: userBlock
        property real sink: ui.typing ? 1 : 0
        x: ui.middle.x - width / 2
        y: ui.middle.y - height / 2
        width: ui.rift.lockBlock.width
        spacing: 4
        scale: ui.fit * (1 - 0.4 * sink)
        opacity: 1 - sink
        visible: opacity > 0

        Behavior on sink {
            NumberAnimation {
                duration: 220 * ui.rift.slowmo
                easing.type: Easing.InOutCubic
            }
        }

        ClippingRectangle {
            id: avatar
            property int candidate: 0
            anchors.horizontalCenter: parent.horizontalCenter
            visible: ui.options.showUser ?? true
            width: 72
            height: 72
            radius: 36
            color: Qt.rgba(ui.accent.r, ui.accent.g, ui.accent.b, 0.25)
            border.width: 1
            border.color: Qt.rgba(ui.accent.r, ui.accent.g, ui.accent.b, 0.6)

            Image {
                anchors.fill: parent
                source: avatar.candidate < ui.info.avatarCandidates.length ? "file://" + ui.info.avatarCandidates[avatar.candidate] : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(144, 144)
                onStatusChanged: if (status === Image.Error)
                    avatar.candidate++
            }
            Text {
                anchors.centerIn: parent
                visible: avatar.candidate >= ui.info.avatarCandidates.length
                text: (ui.info.fullName || ui.info.userName).charAt(0).toUpperCase()
                font.family: ui.rift.labelFamily
                font.pixelSize: 30
                color: ui.ink
            }
        }
        Item {
            visible: avatar.visible
            width: 1
            height: 4
        }
        Text {
            width: parent.width
            visible: avatar.visible
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: ui.info.userName
            font.family: ui.rift.labelFamily
            font.pixelSize: 17
            font.weight: Font.DemiBold
            color: ui.ink
        }
        Text {
            width: parent.width
            visible: avatar.visible && ui.info.fullName !== "" && ui.info.fullName !== ui.info.userName
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: ui.info.fullName
            font.family: ui.rift.labelFamily
            font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.65)
        }
        Text {
            width: parent.width
            topPadding: 4
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: ui.locker.message || ui.locker.prompt
            font.family: ui.rift.labelFamily
            font.pixelSize: 13
            color: ui.locker.message && ui.locker.messageIsError ? "#ff9a9a" : Qt.rgba(1, 1, 1, 0.5)
        }
    }

    LockOrbs {
        rift: ui.rift
        count: input.text.length
        busy: ui.locker.busy
        leaving: ui.rift.phase === "unlocking"
        accent: ui.accent
    }

    TextInput {
        id: input
        width: 0
        height: 0
        opacity: 0
        echoMode: TextInput.Password
        focus: true
        onAccepted: ui.locker.submit(text)
        Keys.onEscapePressed: {
            if (text.length === 0 && ui.locker.preview)
                ui.locker.cancelPreview();
            text = "";
        }

        Connections {
            target: ui.locker
            function onClearInput() {
                input.text = "";
            }
        }
    }
}
