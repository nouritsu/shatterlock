pragma ComponentBehavior: Bound

import QtQuick
import "crack.js" as Crack
import "../fx"

// Everything the rift draws: the crack field, the background slot, the two halves and the edge
// slot (post-processed by the opening slot while it runs), and shards. Animated state comes from
// `rift` (RiftWindow). The menu's overlay and the lock screen each host one, so the lock can
// carry on exactly where the overlay was.
Item {
    id: view

    required property var rift
    property var snapshotSource: null // texture provider for the frozen screen, mipmapped
    property bool warming: false      // draw every built-in once, invisibly, to build pipelines

    readonly property var snapshot: snapshotSource
    readonly property var sdf: sdfTexture
    // The lock blur as this view draws it (the overlay draws the cleared rift while it is hidden
    // behind the lock surface).
    property real obscure: rift.obscure ?? 0

    function rebake() {
        const crack = rift.crack;
        if (!crack)
            return;
        const v = Crack.packMatrices(crack.samples, 9, 0);
        for (let i = 0; i < 9; i++)
            bake["uV" + i] = Qt.matrix4x4(...v[i]);
        bake.uFrom = Qt.vector2d(crack.from.x, crack.from.y);
        bake.uDir = Qt.vector2d(crack.dir.x, crack.dir.y);
        bake.uNormal = Qt.vector2d(crack.normal.x, crack.normal.y);
        bake.uLength = crack.length;
    }

    function startShards() {
        shardsLoader.item?.start();
    }

    Connections {
        target: view.rift
        function onCrackChanged() {
            view.rebake();
        }
    }

    Component.onCompleted: rebake()

    // The crack field, baked once per crack into a float texture (see shaders/bake.frag).
    ShaderEffect {
        id: bake
        width: view.width
        height: view.height
        visible: false
        blending: false

        property vector2d iResolution: Qt.vector2d(width, height)
        property vector2d uFrom
        property vector2d uDir
        property vector2d uNormal
        property real uLength: 1
        property matrix4x4 uV0
        property matrix4x4 uV1
        property matrix4x4 uV2
        property matrix4x4 uV3
        property matrix4x4 uV4
        property matrix4x4 uV5
        property matrix4x4 uV6
        property matrix4x4 uV7
        property matrix4x4 uV8

        fragmentShader: Qt.resolvedUrl("../shaders/qsb/bake.qsb")
    }

    ShaderEffectSource {
        id: sdfTexture
        sourceItem: bake
        textureSize: Qt.size(Math.max(1, bake.width), Math.max(1, bake.height)) // logical px is plenty
        format: ShaderEffectSource.RGBA16F
        hideSource: true
        visible: false
    }

    // Layer stack, bottom to top: background slot, the halves, edge slot. While the opening slot
    // runs a shader, the stack is drawn into a texture (uSource) that the shader post-processes.
    Item {
        id: stack
        anchors.fill: parent
        visible: view.rift.phase !== "idle" && view.rift.phase !== "capturing" && view.rift.phase !== "warming"

        layer.enabled: view.rift.openingFx?.kind === "shader" && (view.rift.phase === "capturing" || view.rift.phase === "spreading" || view.rift.phase === "opening")
        layer.samplerName: "uSource"
        layer.effect: SlotLayer {
            rift: view.rift
            view: view
            fragmentShader: view.rift.openingFx?.url ?? Qt.resolvedUrl("../shaders/qsb/glitch_tear.qsb")
        }

        SlotLayer {
            rift: view.rift
            view: view
            visible: view.rift.backgroundFx?.kind === "shader"
            uSource: view.snapshot
            fragmentShader: visible ? view.rift.backgroundFx.url : Qt.resolvedUrl("../shaders/qsb/void.qsb")
            renderScale: view.rift.cfg.fx?.renderScale?.background ?? 1
        }
        Loader {
            anchors.fill: parent
            // Kept loaded whenever the config may show the image, so it is decoded ahead of time.
            active: view.rift.backgroundFx?.kind === "image" || view.rift.imageMayShow
            visible: view.rift.backgroundFx?.kind === "image"
            sourceComponent: ImageBackground {
                rift: view.rift
                options: view.rift.cfg.fx?.image ?? ({})
            }
        }
        SlotLayer {
            rift: view.rift
            view: view
            fragmentShader: Qt.resolvedUrl("../shaders/qsb/halves.qsb")
            uSource: view.snapshot
        }
        SlotLayer {
            rift: view.rift
            view: view
            visible: view.rift.edgeFx?.kind === "shader"
            uSource: view.snapshot
            fragmentShader: visible ? view.rift.edgeFx.url : Qt.resolvedUrl("../shaders/qsb/glow.qsb")
            renderScale: view.rift.cfg.fx?.renderScale?.edge ?? 1
        }
    }

    Loader {
        id: shardsLoader
        anchors.fill: parent
        active: view.rift.openingFx?.kind === "shards" && view.rift.phase !== "idle"
        sourceComponent: Shards {
            rift: view.rift
            view: view
        }
    }

    Repeater {
        model: view.warming ? (view.rift.registry?.builtinUrls ?? []).concat([Qt.resolvedUrl("../shaders/qsb/halves.qsb")]) : []

        SlotLayer {
            required property url modelData
            rift: view.rift
            view: view
            opacity: 0.002
            uSource: view.snapshot
            fragmentShader: modelData
        }
    }
}
