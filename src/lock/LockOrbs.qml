pragma ComponentBehavior: Bound

import QtQuick

// The password as orbs of energy drawn out of the rift: one per character, strung along the
// middle of the rift and centred on it. Each new one is pulled out of both edges; backspace lets
// the last one sink back. While the password is checked they pulse together, and once it's
// accepted they flare and fade.
Item {
    id: orbs

    required property var rift
    property int count: 0          // characters typed
    property bool busy: false      // being checked
    property bool leaving: false   // accepted
    property color accent: "#cba6f7"

    readonly property int max: 32
    readonly property real pitch: 26
    readonly property int shown: Math.min(count, max)
    readonly property real angle: rift.crack?.angle ?? 0
    readonly property real halfGap: rift.gap * rift.progress / 2
    readonly property color core: Qt.tint(accent, Qt.rgba(1, 1, 1, 0.65))

    property real throb: 0
    property real leave: leaving ? 1 : 0

    // Screen position of the point `s` px along the middle of the rift from its centre.
    function at(s) {
        const crack = rift.crack;
        if (!crack)
            return Qt.point(-100, -100);
        const p = crack.pointAt(0.5 + s / crack.length);
        return Qt.point(p.x, p.y);
    }

    anchors.fill: parent

    Behavior on leave {
        NumberAnimation {
            duration: 180 * orbs.rift.slowmo
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation on throb {
        running: orbs.busy
        loops: Animation.Infinite
        onRunningChanged: if (!running)
            orbs.throb = 0
        NumberAnimation {
            to: 1
            duration: 320
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: 320
            easing.type: Easing.InOutSine
        }
    }

    Repeater {
        model: orbs.max

        Item {
            id: orb

            required property int index
            readonly property bool active: index < orbs.shown
            readonly property real targetS: (index - (orbs.shown - 1) / 2) * orbs.pitch
            property real s: 0
            property real presence: 0 // sinks to 0 when deleted
            property real birth: 1    // 0 .. 1 while it is pulled out of the edges

            // Sparks race in from both edges (first half), then the orb blooms (second half).
            readonly property real race: Math.min(1, birth / 0.5)
            readonly property real bloom: Math.max(0, Math.min(1, (birth - 0.4) / 0.6))
            readonly property real swell: bloom < 1 ? 1 + 0.35 * Math.sin(Math.PI * bloom) : 1
            readonly property point p: orbs.at(s)

            function appear() {
                s = targetS;
                sink.stop();
                presence = 1;
                birthAnim.restart();
            }

            x: p.x - width / 2
            y: p.y - height / 2
            width: 1
            height: 1
            rotation: orbs.angle
            visible: presence > 0

            Component.onCompleted: if (active)
                appear()
            onActiveChanged: active ? appear() : sink.restart()
            onTargetSChanged: if (active)
                s = targetS

            Behavior on s {
                enabled: orb.active && orb.presence > 0
                NumberAnimation {
                    duration: 160 * orbs.rift.slowmo
                    easing.type: Easing.OutCubic
                }
            }

            NumberAnimation {
                id: birthAnim
                target: orb
                property: "birth"
                from: 0
                to: 1
                duration: 280 * orbs.rift.slowmo
            }

            NumberAnimation {
                id: sink
                target: orb
                property: "presence"
                to: 0
                duration: 160 * orbs.rift.slowmo
                easing.type: Easing.InCubic
            }

            // The sparks, pulled out of both edges along the normal (local y): a glowing head
            // with a tail back to the edge it left.
            Repeater {
                model: [-1, 1]

                Item {
                    id: spark
                    required property int modelData
                    readonly property real reach: orbs.halfGap * (1 - orb.race * orb.race)
                    readonly property real tail: Math.min(60, orbs.halfGap - reach)
                    visible: orb.race < 1
                    opacity: 1 - 0.4 * orb.race

                    Rectangle {
                        x: -1.5
                        y: spark.modelData > 0 ? spark.reach : -spark.reach - spark.tail
                        width: 3
                        height: spark.tail
                        radius: 1.5
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: spark.modelData > 0 ? orbs.core : "transparent"
                            }
                            GradientStop {
                                position: 1
                                color: spark.modelData > 0 ? "transparent" : orbs.core
                            }
                        }
                    }
                    ShaderEffect {
                        x: -11
                        y: spark.modelData * spark.reach - 11
                        width: 22
                        height: 22
                        property color uColor: orbs.core
                        fragmentShader: Qt.resolvedUrl("../shaders/qsb/halo.qsb")
                    }
                }
            }

            Item {
                scale: orb.bloom * orb.swell * orb.presence * (1 + 0.22 * orbs.throb + 0.5 * orbs.leave)
                opacity: orb.presence * (1 - orbs.leave)

                ShaderEffect {
                    x: -30
                    y: -30
                    width: 60
                    height: 60
                    opacity: 0.75 + 0.25 * orbs.throb
                    property color uColor: orbs.accent
                    fragmentShader: Qt.resolvedUrl("../shaders/qsb/halo.qsb")
                }

                Rectangle {
                    x: -6
                    y: -6
                    width: 12
                    height: 12
                    radius: 6
                    color: orbs.core
                }
            }
        }
    }
}
