pragma ComponentBehavior: Bound

import QtQuick

// The password as orbs of energy drawn out of the rift: one per character, strung along the
// middle of the rift and centred on it. Each new one is pulled out of both edges; backspace lets
// the last one sink back. While the password is checked they pulse together, and once it's
// accepted they flare and fade. On a wrong password (reject) they turn red and shoot back into the
// edges.
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

    // Orbs on their way back into the edges after a wrong password: [{ x, y, side, start }], start
    // in ms; the typed ones vanish at once (`dropping`) as these take their place.
    property var flyers: []
    property bool dropping: false
    readonly property color red: "#ff4a55"
    readonly property int redMs: 90
    readonly property int flightMs: 150
    readonly property int burstMs: 220

    // Screen position of the point `s` px along the middle of the rift from its centre.
    function at(s) {
        const crack = rift.crack;
        if (!crack)
            return Qt.point(-100, -100);
        const p = crack.pointAt(0.5 + s / crack.length);
        return Qt.point(p.x, p.y);
    }

    // Wrong password: the orbs turn red, then shoot to alternate edges, the middle ones first.
    // Returns where and when each one hits ([{ x, y, at }], at in s from now) for rift.reject.
    function reject() {
        const crack = rift.crack;
        if (!crack || shown === 0)
            return [];
        const n = shown;
        const stagger = Math.min(22, 320 / n);
        const order = [...Array(n).keys()].sort((a, b) => Math.abs(a - (n - 1) / 2) - Math.abs(b - (n - 1) / 2));
        const fly = [], hits = [];
        for (let rank = 0; rank < n; rank++) {
            const i = order[rank];
            const p = at((i - (n - 1) / 2) * pitch);
            const side = i % 2 === 0 ? -1 : 1;
            const start = redMs + rank * stagger;
            fly.push({
                x: p.x,
                y: p.y,
                side: side,
                start: start
            });
            hits.push({
                x: p.x + crack.normal.x * side * halfGap,
                y: p.y + crack.normal.y * side * halfGap,
                at: (start + flightMs) * rift.slowmo / 1000
            });
        }
        flyers = fly;
        dropping = true;
        Qt.callLater(() => orbs.dropping = false);
        flyersDone.interval = (redMs + (n - 1) * stagger + flightMs + burstMs) * rift.slowmo + 50;
        flyersDone.restart();
        return hits;
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
            onActiveChanged: {
                if (active)
                    appear();
                else if (orbs.dropping)
                    presence = 0;
                else
                    sink.restart();
            }
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

    Timer {
        id: flyersDone
        onTriggered: orbs.flyers = []
    }

    Repeater {
        model: orbs.flyers

        Item {
            id: flyer

            required property var modelData
            property real ms: 0 // into its own timeline: red, then flight, then burst
            readonly property real redness: Math.min(1, ms / orbs.redMs)
            readonly property real flight: Math.max(0, Math.min(1, (ms - modelData.start) / orbs.flightMs))
            readonly property real burst: Math.max(0, Math.min(1, (ms - modelData.start - orbs.flightMs) / orbs.burstMs))
            readonly property real travelled: orbs.halfGap * flight * flight
            readonly property color tint: Qt.tint(orbs.core, Qt.rgba(1, 0.29, 0.33, redness))

            x: modelData.x
            y: modelData.y
            width: 1
            height: 1
            rotation: orbs.angle

            NumberAnimation on ms {
                from: 0
                to: flyer.modelData.start + orbs.flightMs + orbs.burstMs
                duration: (flyer.modelData.start + orbs.flightMs + orbs.burstMs) * orbs.rift.slowmo
            }

            // A trail back along its way while it flies.
            Rectangle {
                readonly property real length: Math.min(54, flyer.travelled)
                x: -2
                y: flyer.modelData.side > 0 ? flyer.travelled - length : -flyer.travelled
                width: 4
                height: length
                radius: 2
                visible: flyer.flight > 0 && flyer.burst === 0
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: flyer.modelData.side > 0 ? "transparent" : orbs.red
                    }
                    GradientStop {
                        position: 1
                        color: flyer.modelData.side > 0 ? orbs.red : "transparent"
                    }
                }
            }

            Item {
                y: flyer.modelData.side * flyer.travelled
                scale: 1 + 1.8 * flyer.burst
                opacity: 1 - flyer.burst

                ShaderEffect {
                    x: -30
                    y: -30
                    width: 60
                    height: 60
                    property color uColor: Qt.tint(orbs.accent, Qt.rgba(1, 0.16, 0.2, flyer.redness))
                    fragmentShader: Qt.resolvedUrl("../shaders/qsb/halo.qsb")
                }
                Rectangle {
                    x: -6
                    y: -6
                    width: 12
                    height: 12
                    radius: 6
                    color: flyer.tint
                }
            }
        }
    }
}
