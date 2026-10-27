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
    readonly property var alert: alertTexture

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
        function onImpactsChanged() {
            view.repackAlert();
        }
    }

    Component.onCompleted: {
        rebake();
        repackAlert();
    }

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

    // Wrong-password waves (RiftWindow.reject), drawn at a quarter of the resolution into uAlert.
    ShaderEffect {
        id: alertField
        width: view.width
        height: view.height
        visible: false
        blending: false

        property vector2d iResolution: Qt.vector2d(width, height)
        property real uElapsed: Math.max(0, (view.rift.time ?? 0) - (view.rift.alertBase ?? 0))
        property real uFade: view.rift.alertFade ?? 0
        property real uCount: Math.min(32, view.rift.impacts?.length ?? 0)
        property real uSpeed: view.rift.alertSpeed ?? 1
        property matrix4x4 uP0
        property matrix4x4 uP1
        property matrix4x4 uP2
        property matrix4x4 uP3
        property matrix4x4 uT0
        property matrix4x4 uT1

        fragmentShader: Qt.resolvedUrl("../shaders/qsb/alert.qsb")
    }

    ShaderEffectSource {
        id: alertTexture
        sourceItem: alertField
        textureSize: Qt.size(Math.max(1, Math.round(view.width / 4)), Math.max(1, Math.round(view.height / 4)))
        hideSource: true
        visible: false
        live: view.rift.alertOn ?? false
    }

    function repackAlert() {
        const impacts = (rift.impacts ?? []).slice(0, 32);
        const p = Crack.packMatrices(impacts.reduce((all, i) => all.concat([i.x, i.y]), []), 4, -1e5);
        const t = Crack.packMatrices(impacts.map(i => i.at), 2, 1e5);
        for (let i = 0; i < 4; i++)
            alertField["uP" + i] = Qt.matrix4x4(...p[i]);
        for (let i = 0; i < 2; i++)
            alertField["uT" + i] = Qt.matrix4x4(...t[i]);
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
        // "surface": the lowest Material surface, flat.
        Rectangle {
            anchors.fill: parent
            visible: view.rift.backgroundFx?.kind === "surface"
            color: view.rift.roles?.surface_container_lowest ?? view.rift.voidColor
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
