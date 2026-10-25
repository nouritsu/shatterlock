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

    // The user and the password field are laid end to end along the rift, centred on its middle.
    readonly property real spacing: 56
    readonly property var offsets: {
        const shown = [
            {
                id: "user",
                w: userGroup.width,
                off: !(options.showUser ?? true)
            },
            {
                id: "field",
                w: fieldGroup.width
            }
        ].filter(g => !g.off);
        const total = shown.reduce((sum, g) => sum + g.w, 0) + spacing * (shown.length - 1);
        const out = {};
        let x = -total / 2;
        for (const g of shown) {
            out[g.id] = x + g.w / 2;
            x += g.w + spacing;
        }
        return out;
    }

    // Centre of a group placed `offsetPx` along the crack from its middle.
    function centreAt(offsetPx) {
        const crack = rift.crack;
        if (!crack || offsetPx === undefined)
            return Qt.point(0, 0);
        const p = crack.pointAt(0.5 + offsetPx / crack.length);
        return Qt.point(p.x, p.y);
    }

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

    // Who is locked in
    Column {
        id: userGroup
        readonly property point c: ui.centreAt(ui.offsets.user)
        x: c.x - width / 2
        y: c.y - height / 2
        rotation: ui.angle
        spacing: 6
        visible: ui.offsets.user !== undefined

        ClippingRectangle {
            id: avatar
            property int candidate: 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: 52
            height: 52
            radius: 26
            color: Qt.rgba(ui.accent.r, ui.accent.g, ui.accent.b, 0.25)
            border.width: 1
            border.color: Qt.rgba(ui.accent.r, ui.accent.g, ui.accent.b, 0.6)

            Image {
                anchors.fill: parent
                source: avatar.candidate < ui.info.avatarCandidates.length ? "file://" + ui.info.avatarCandidates[avatar.candidate] : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(104, 104)
                onStatusChanged: if (status === Image.Error)
                    avatar.candidate++
            }
            Text {
                anchors.centerIn: parent
                visible: avatar.candidate >= ui.info.avatarCandidates.length
                text: (ui.info.fullName || ui.info.userName).charAt(0).toUpperCase()
                font.family: ui.rift.labelFamily
                font.pixelSize: 22
                color: ui.ink
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ui.info.fullName || ui.info.userName
            font.family: ui.rift.labelFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: ui.ink
        }
    }

    // Password
    Item {
        id: fieldGroup
        readonly property point c: ui.centreAt(ui.offsets.field)
        x: c.x - width / 2
        y: c.y - height / 2
        width: 320
        height: 84
        rotation: ui.angle

        Rectangle {
            id: field
            width: parent.width
            height: 48
            radius: 24
            color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.08 : 0.05)
            border.width: 1
            border.color: Qt.rgba(ui.accent.r, ui.accent.g, ui.accent.b, ui.locker.busy ? 0.95 : 0.55)

            SequentialAnimation on border.width {
                running: ui.locker.busy
                loops: Animation.Infinite
                NumberAnimation {
                    to: 2.5
                    duration: 350
                }
                NumberAnimation {
                    to: 1
                    duration: 350
                }
            }

            Text {
                anchors.centerIn: parent
                visible: input.text.length === 0
                text: ui.locker.prompt
                font.family: ui.rift.labelFamily
                font.pixelSize: 15
                color: Qt.rgba(1, 1, 1, 0.45)
            }

            Row {
                anchors.centerIn: parent
                spacing: 7
                Repeater {
                    model: Math.min(input.text.length, 22)
                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: ui.accent
                    }
                }
            }
        }

        Text {
            anchors.top: field.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: field.horizontalCenter
            text: ui.locker.message
            font.family: ui.rift.labelFamily
            font.pixelSize: 13
            color: ui.locker.messageIsError ? "#ff9a9a" : Qt.rgba(1, 1, 1, 0.6)
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
}
