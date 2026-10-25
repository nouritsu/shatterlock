pragma ComponentBehavior: Bound

import QtQuick

// The password as orbs of energy gathered in the rift: one per character, strung along the middle
// of the rift and centred on it. Each new one forms from motes drifting in along the rift;
// backspace lets the last one sink back. While the password is checked they pulse together, and
// once it's accepted they flare and fade. On a wrong password (reject) they turn red and shoot off
// in random directions into the rift's edges.
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

    // Orbs on their way into the edges after a wrong password: [{ x, y, heading, distance, start,
    // flight }] (heading in degrees from the rift's direction, times in ms); the typed ones vanish at
    // once (`dropping`) as these take their place.
    property var flyers: []
    property bool dropping: false
    readonly property color red: "#ff4a55"
    readonly property int redMs: 90
    readonly property int burstMs: 220

    // Screen position of the point `s` px along the middle of the rift from its centre.
    function at(s) {
        const crack = rift.crack;
        if (!crack)
            return Qt.point(-100, -100);
        const p = crack.pointAt(0.5 + s / crack.length);
        return Qt.point(p.x, p.y);
    }

    // A screen-space offset turned into an orb's own frame (x along the rift, y across it).
    function local(dx, dy) {
        const a = angle * Math.PI / 180;
        return Qt.point(dx * Math.cos(a) + dy * Math.sin(a), -dx * Math.sin(a) + dy * Math.cos(a));
    }

    // Wrong password: the orbs turn red, then shoot off at random angles (never nearly along the
    // rift), the middle ones first, and burst where they meet an edge. Returns where and when each
    // one hits ([{ x, y, at }], at in s from now) for rift.reject.
    function reject() {
        const crack = rift.crack;
        if (!crack || shown === 0)
            return [];
        const n = shown;
        const stagger = Math.min(22, 320 / n);
        const order = [...Array(n).keys()].sort((a, b) => Math.abs(a - (n - 1) / 2) - Math.abs(b - (n - 1) / 2));
        const fly = [], hits = [];
        let done = 0;
        for (let rank = 0; rank < n; rank++) {
            const i = order[rank];
            const p = at((i - (n - 1) / 2) * pitch);
            const side = Math.random() < 0.5 ? -1 : 1;
            const a = (25 + Math.random() * 130) * Math.PI / 180;
            const dx = crack.dir.x * Math.cos(a) + crack.normal.x * side * Math.sin(a);
            const dy = crack.dir.y * Math.cos(a) + crack.normal.y * side * Math.sin(a);
            // Step out until the edge (the crack is jagged, so it's found rather than worked out).
            let distance = halfGap / Math.sin(a);
            for (let d = 0; d < 900; d += 3) {
                if (Math.abs(crack.offsetFrom(p.x + dx * d, p.y + dy * d)) >= halfGap) {
                    distance = d;
                    break;
                }
            }
            const start = redMs + rank * stagger;
            const flight = 150 + Math.min(120, Math.max(0, distance - halfGap) * 0.3);
            fly.push({
                x: p.x,
                y: p.y,
                heading: side * a * 180 / Math.PI,
                distance: distance,
                start: start,
                flight: flight
            });
            hits.push({
                x: p.x + dx * distance,
                y: p.y + dy * distance,
                at: (start + flight) * rift.slowmo / 1000
            });
            done = Math.max(done, start + flight + burstMs);
        }
        flyers = fly;
        dropping = true;
        Qt.callLater(() => orbs.dropping = false);
        flyersDone.interval = done * rift.slowmo + 50;
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
            property real birth: 1    // 0 .. 1 while it forms
            property var motes: []    // where its motes start, in its own frame, and when they set off

            // The motes drift in (most of the way), then the orb blooms where they meet.
            readonly property real bloom: Math.max(0, Math.min(1, (birth - 0.55) / 0.45))
            readonly property real swell: bloom < 1 ? 1 + 0.35 * Math.sin(Math.PI * bloom) : 1
            readonly property point p: orbs.at(s)

            // Motes start at random points further along the rift, either way, and anywhere across it.
            function appear() {
                s = targetS;
                const crack = orbs.rift.crack;
                const list = [];
                for (let k = 0; crack && k < 3; k++) {
                    const along = (Math.random() < 0.5 ? -1 : 1) * (90 + Math.random() * 230);
                    const across = (Math.random() * 2 - 1) * 0.55 * orbs.halfGap;
                    const from = orbs.at(s + along);
                    const here = orbs.at(s);
                    const l = orbs.local(from.x + crack.normal.x * across - here.x, from.y + crack.normal.y * across - here.y);
                    list.push({
                        x: l.x,
                        y: l.y,
                        delay: Math.random() * 0.2
                    });
                }
                motes = list;
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
                duration: 360 * orbs.rift.slowmo
            }

            NumberAnimation {
                id: sink
                target: orb
                property: "presence"
                to: 0
                duration: 160 * orbs.rift.slowmo
                easing.type: Easing.InCubic
            }

            // The motes, drifting in from where they started and shrinking into the orb.
            Repeater {
                model: orb.motes

                Item {
                    id: mote
                    required property var modelData
                    readonly property real u: Math.max(0, Math.min(1, (orb.birth - modelData.delay) / 0.6))
                    readonly property real rest: 1 - u * u * (3 - 2 * u) // of the way still to go
                    x: modelData.x * rest
                    y: modelData.y * rest
                    visible: u < 1
                    opacity: Math.min(1, u * 6)
                    scale: 0.5 + 0.5 * rest

                    ShaderEffect {
                        x: -14
                        y: -14
                        width: 28
                        height: 28
                        property color uColor: orbs.accent
                        fragmentShader: Qt.resolvedUrl("../shaders/qsb/halo.qsb")
                    }
                    Rectangle {
                        x: -3
                        y: -3
                        width: 6
                        height: 6
                        radius: 3
                        color: orbs.core
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
            readonly property real end: modelData.start + modelData.flight + orbs.burstMs
            readonly property real redness: Math.min(1, ms / orbs.redMs)
            readonly property real flight: Math.max(0, Math.min(1, (ms - modelData.start) / modelData.flight))
            readonly property real burst: Math.max(0, Math.min(1, (ms - modelData.start - modelData.flight) / orbs.burstMs))
            readonly property real travelled: modelData.distance * flight * flight
            readonly property color tint: Qt.tint(orbs.core, Qt.rgba(1, 0.29, 0.33, redness))

            // Turned to its heading: it flies along its own x.
            x: modelData.x
            y: modelData.y
            width: 1
            height: 1
            rotation: orbs.angle + modelData.heading

            NumberAnimation on ms {
                from: 0
                to: flyer.end
                duration: flyer.end * orbs.rift.slowmo
            }

            // A trail back along its way while it flies.
            Rectangle {
                readonly property real length: Math.min(54, flyer.travelled)
                x: flyer.travelled - length
                y: -2
                width: length
                height: 4
                radius: 2
                visible: flyer.flight > 0 && flyer.burst === 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: orbs.red
                    }
                }
            }

            Item {
                x: flyer.travelled
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
