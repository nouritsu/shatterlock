pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Particles

// Opening slot "shards": triangles of the frozen screen break off the edges and tumble into the
// rift, with a puff of dust.
Item {
    id: shards

    required property var rift
    required property var view

    property var pieces: []
    property real t: 0

    anchors.fill: parent

    function start() {
        const crack = rift.crack;
        if (!crack)
            return;
        const list = [];
        for (let i = 0; i < 36; i++) {
            const p = crack.pointAt(0.04 + Math.random() * 0.92);
            const side = Math.random() < 0.5 ? -1 : 1; // -1: from half A
            const size = 12 + Math.random() * 30;
            list.push({
                x: p.x + crack.normal.x * side * size * 0.6 - size / 2,
                y: p.y + crack.normal.y * side * size * 0.6 - size / 2,
                size: size,
                side: side,
                delay: Math.random() * 0.35,
                spin: (Math.random() - 0.5) * 720,
                drift: (Math.random() - 0.5) * 60,
                tri: [Math.random() * 0.4, Math.random() * 0.3, 0.6 + Math.random() * 0.4, Math.random() * 0.5, Math.random(), 0.6 + Math.random() * 0.4]
            });
        }
        pieces = list;
        fall.restart();
        for (let i = 0; i < dust.count; i++)
            dust.itemAt(i).burst(14);
    }

    NumberAnimation {
        id: fall
        target: shards
        property: "t"
        from: 0
        to: 1
        duration: 1100
    }

    Repeater {
        model: shards.pieces

        ShaderEffect {
            required property var modelData

            readonly property real life: Math.max(0, Math.min(1, (shards.t - modelData.delay) / 0.65))
            // Rides on its half, while falling away from it into the rift.
            readonly property vector2d base: modelData.side < 0 ? shards.rift.offA : shards.rift.offB
            readonly property vector2d away: shards.rift.normal.times(-modelData.side * 46 * life)

            x: modelData.x + base.x + away.x + modelData.drift * life
            y: modelData.y + base.y + away.y + 140 * life * life
            width: modelData.size
            height: modelData.size
            rotation: modelData.spin * life
            opacity: 1 - life * life
            visible: life > 0 && life < 1

            property vector4d uSrc: Qt.vector4d(modelData.x / shards.width, modelData.y / shards.height, modelData.size / shards.width, modelData.size / shards.height)
            property vector2d uA: Qt.vector2d(modelData.tri[0], modelData.tri[1])
            property vector2d uB: Qt.vector2d(modelData.tri[2], modelData.tri[3])
            property vector2d uC: Qt.vector2d(modelData.tri[4], modelData.tri[5])
            property color uTint: shards.rift.voidColor
            property color uRim: shards.rift.accent
            property var uSnapshot: shards.view.snapshot

            fragmentShader: Qt.resolvedUrl("../shaders/qsb/shard.qsb")
        }
    }

    ParticleSystem {
        id: particles
    }

    ImageParticle {
        system: particles
        source: "qrc:///particleresources/fuzzydot.png"
        color: Qt.rgba(0.7, 0.68, 0.74, 0.3)
        colorVariation: 0.06
        alpha: 0.35
    }

    Gravity {
        system: particles
        magnitude: 260
        angle: 90
    }

    // Dust puffs from points along the crack.
    Repeater {
        id: dust
        model: 14

        Emitter {
            required property int index

            readonly property var at: shards.rift.crack ? shards.rift.crack.pointAt((index + 0.5) / 14) : ({
                    x: 0,
                    y: 0
                })

            system: particles
            x: at.x - 4
            y: at.y - 4
            width: 8
            height: 8
            emitRate: 0
            lifeSpan: 900
            lifeSpanVariation: 300
            size: 5
            sizeVariation: 3
            endSize: 1
            velocity: AngleDirection {
                angleVariation: 180
                magnitude: 60
                magnitudeVariation: 40
            }
        }
    }
}
