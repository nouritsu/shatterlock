import QtQuick

// One full-screen layer drawn by a shader written against the shatterlock contract
// (shaders/prelude.glsl). Every layer gets the same uniforms from the rift.
ShaderEffect {
    required property var rift // RiftWindow: animated state
    required property var view // RiftView: the textures it draws from

    anchors.fill: parent

    property real iTime: rift.time
    property vector2d iResolution: Qt.vector2d(width, height)
    property real uProgress: rift.progress
    property real uSpread: rift.spread
    property real uLine: rift.lineAlpha
    property real uPhase: rift.phaseIndex
    property real uGap: rift.gap * rift.progress
    property vector2d uOffA: rift.offA
    property vector2d uOffB: rift.offB
    property vector2d uMouse: rift.mouse
    property real uHover: rift.hover
    property color uAccent: rift.accent // accent() turns it red where a wrong-password wave is
    property color uVoid: rift.voidColor
    property var uSnapshot: view.snapshot
    property var uSdf: view.sdf
    // Opening slot: the composited rift, set by the layer that hosts this effect. Other layers pass
    // the snapshot. (A default binding here would override the layer's assignment.)
    property var uSource
    property real uWarn: rift.warn ? 1 : 0
    property real uObscure: view.obscure ?? 0
    property real uObscureStyle: ({
            void: 0,
            frosted: 1,
            glass: 2
        })[rift.obscureStyle] ?? 0
    property vector4d uCrackLine: rift.crack ? Qt.vector4d(rift.crack.from.x, rift.crack.from.y, rift.crack.normal.x, rift.crack.normal.y) : Qt.vector4d(0, 0, 0, 1)
    property real uAlertOn: rift.alertOn ? 1 : 0
    property var uAlert: view.alert

    // Heavy custom shaders can draw at a fraction of the output's resolution.
    property real renderScale: 1
    layer.enabled: renderScale < 0.999
    layer.textureSize: Qt.size(Math.max(1, width * renderScale), Math.max(1, height * renderScale))
    layer.smooth: true
}
