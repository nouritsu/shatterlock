pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets

// The lock screen's contents, laid along the rift like the menu: clock and date, who is locked
// in, the password field, the media player and the status icons. Shown by the lock surface (and
// by the overlay while sealing and in preview).
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

    // The groups are laid end to end along the rift, centred on its middle. When they don't fit
    // (small outputs), optional ones go: status first, then media, then the user.
    readonly property real spacing: 56
    readonly property var offsets: {
        const wanted = [
            {
                id: "clock",
                w: clockGroup.width
            },
            {
                id: "user",
                w: userGroup.width,
                off: !(options.showUser ?? true)
            },
            {
                id: "field",
                w: fieldGroup.width
            },
            {
                id: "media",
                w: media.width,
                off: !(options.showMedia ?? true) || info.player === null
            },
            {
                id: "status",
                w: statusGroup.width,
                off: !(options.showStatus ?? true)
            }
        ];
        const total = list => list.reduce((sum, g) => sum + g.w, 0) + spacing * (list.length - 1);
        let shown = wanted.filter(g => !g.off);
        const room = (rift.crack?.length ?? 2900) * 0.84;
        for (const drop of ["status", "media", "user"]) {
            if (total(shown) <= room)
                break;
            shown = shown.filter(g => g.id !== drop);
        }
        const out = {};
        let x = -total(shown) / 2;
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

    // Clock and date
    Column {
        id: clockGroup
        readonly property point c: ui.centreAt(ui.offsets.clock)
        x: c.x - width / 2
        y: c.y - height / 2
        rotation: ui.angle
        spacing: -4

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, ui.options.timeFormat ?? "HH:mm")
            font.family: ui.rift.labelFamily
            font.pixelSize: 64
            font.weight: Font.Light
            color: ui.ink
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, ui.options.dateFormat ?? "dddd, d MMMM")
            font.family: ui.rift.labelFamily
            font.pixelSize: 16
            color: Qt.rgba(1, 1, 1, 0.65)
        }
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

    // Now playing
    Row {
        id: media
        readonly property point c: ui.centreAt(ui.offsets.media)
        readonly property var player: ui.info.player
        x: c.x - width / 2
        y: c.y - height / 2
        rotation: ui.angle
        spacing: 12
        visible: ui.offsets.media !== undefined

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
            width: 170
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: media.player?.trackTitle || "Unknown title"
                font.family: ui.rift.labelFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: ui.ink
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: media.player?.trackArtist ?? ""
                font.family: ui.rift.labelFamily
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.6)
            }
        }

        Row {
            id: controls
            readonly property var player: media.player
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: [
                    {
                        icon: "skip_previous",
                        enabled: controls.player?.canGoPrevious ?? false,
                        act: () => controls.player.previous()
                    },
                    {
                        icon: controls.player?.isPlaying ? "pause" : "play_arrow",
                        enabled: controls.player?.canTogglePlaying ?? false,
                        act: () => controls.player.togglePlaying()
                    },
                    {
                        icon: "skip_next",
                        enabled: controls.player?.canGoNext ?? false,
                        act: () => controls.player.next()
                    }
                ]

                Text {
                    required property var modelData
                    width: 30
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.icon
                    font.family: ui.rift.iconFamily
                    font.pixelSize: 26
                    color: modelData.enabled ? (tap.containsMouse ? "#ffffff" : ui.accent) : Qt.rgba(1, 1, 1, 0.25)

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

    // Battery and network
    Row {
        id: statusGroup
        readonly property point c: ui.centreAt(ui.offsets.status)
        x: c.x - width / 2
        y: c.y - height / 2
        rotation: ui.angle
        spacing: 16
        visible: ui.offsets.status !== undefined

        Row {
            visible: ui.info.hasBattery
            spacing: 4
            Text {
                text: ui.info.batteryIcon
                font.family: ui.rift.iconFamily
                font.pixelSize: 22
                color: ui.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: `${ui.info.batteryPercent}%`
                font.family: ui.rift.labelFamily
                font.pixelSize: 14
                color: ui.ink
            }
        }
        Row {
            spacing: 4
            Text {
                text: ui.info.netIcon
                font.family: ui.rift.iconFamily
                font.pixelSize: 22
                color: ui.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ui.info.netName || "Offline"
                font.family: ui.rift.labelFamily
                font.pixelSize: 14
                color: ui.ink
            }
        }
    }
}
