import QtQuick

// One action as a Material icon button in the rift: an icon in a tonal circle, turned to the rift's
// angle like the rest of the menu. Focused, it shows the focus ring. Pressed, it takes on the
// action's own colour (else the accent's): held, a progress ring fills around it, the circle turns
// to that colour's container and the icon gives way to the time still to hold; it swells and
// flares as it pulses on the way to running.
Item {
    id: btn

    required property string icon

    property bool selected: false
    property real holdProgress: 0 // 0..1 while held (and draining as a held action pulses)
    property int holdLeft: -1     // ms still to hold while it is held, else -1
    property real pulse: 0        // 0..1 while pulsing before it runs
    property real appear: 0       // 0 hidden .. 1 shown
    property color accent: "#cba6f7"
    property color tint: "transparent" // the action's colour while pressed; transparent: the accent
    property var roles: ({})
    property string iconFamily
    property string labelFamily

    readonly property real radius: 32
    readonly property real swell: Math.sin(Math.PI * pulse)
    readonly property bool charged: holdProgress > 0 || pulse > 0
    readonly property color ink: Qt.tint(role("on_secondary_container", "#cdd6f4"), Qt.alpha(pressedInk, container))

    // The pressed colours: the accent's roles, or Material-style tones of the action's colour for
    // the theme's mode (dark: a light ring on a deep circle; light: the other way round).
    property color surfaceTone: role("surface", "#1e1e2e")
    readonly property bool dark: surfaceTone.hslLightness < 0.5
    readonly property bool tinted: tint.a > 0
    readonly property color pressedRing: tinted ? toward(dark ? 1 : 0, dark ? 0.45 : 0.2) : role("primary", accent)
    readonly property color pressedContainer: tinted ? toward(dark ? 0 : 1, dark ? 0.55 : 0.75) : role("primary_container", "#55307f")
    readonly property color pressedInk: tinted ? toward(dark ? 1 : 0, dark ? 0.8 : 0.6) : role("on_primary_container", "#f2e8ff")

    // The tint moved `t` of the way to white (1) or black (0).
    function toward(level, t) {
        return Qt.rgba(tint.r + (level - tint.r) * t, tint.g + (level - tint.g) * t, tint.b + (level - tint.b) * t, 1);
    }

    function role(name, fallback) {
        return roles?.[name] ?? fallback;
    }

    width: 2 * (radius + 12)
    height: width
    opacity: appear
    scale: (0.7 + 0.3 * appear) * (1 + 0.14 * swell)

    // Only the circle (and its rings) take the pointer.
    containmentMask: QtObject {
        function contains(point: point): bool {
            return Math.hypot(point.x - btn.width / 2, point.y - btn.height / 2) <= btn.radius + 8;
        }
    }

    // Material motion: standard easing, short.
    component Fade: NumberAnimation {
        duration: 150
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }

    property real focusShown: selected && !charged ? 1 : 0
    Behavior on focusShown {
        Fade {}
    }

    property real container: charged ? 1 : 0
    Behavior on container {
        Fade {}
    }

    property real counting: holdLeft >= 0 ? 1 : 0
    Behavior on counting {
        Fade {}
    }

    // The pulse's flare, behind everything.
    ShaderEffect {
        anchors.centerIn: parent
        width: 190 * (1 + 0.4 * btn.swell)
        height: width
        visible: btn.swell > 0
        opacity: 0.7 * btn.swell
        property color uColor: btn.pressedRing
        fragmentShader: Qt.resolvedUrl("../shaders/qsb/halo.qsb")
    }

    ShaderEffect {
        anchors.fill: parent
        property vector2d uSize: Qt.vector2d(width, height)
        property real uRadius: btn.radius
        property color uContainer: Qt.tint(btn.role("secondary_container", "#313244"), Qt.alpha(btn.pressedContainer, btn.container))
        property color uFocusColor: btn.role("secondary", btn.accent)
        property real uFocus: btn.focusShown
        property color uArcColor: btn.pressedRing
        property color uTrackColor: btn.role("secondary_container", "#313244")
        // A held action pulses with a full ring that fades; an instant one shows none.
        property real uArc: btn.pulse > 0 ? 1 : btn.holdProgress
        property real uRing: btn.pulse > 0 ? btn.holdProgress : (btn.holdProgress > 0 ? 1 : 0)
        fragmentShader: Qt.resolvedUrl("../shaders/qsb/iconbutton.qsb")
    }

    Text {
        anchors.centerIn: parent
        text: btn.icon
        font.family: btn.iconFamily
        // Native glyphs (the default rendering mangles filled Material Symbols), drawn unrotated
        // at twice the size and then turned with the button, so their edges stay smooth.
        renderType: Text.NativeRendering
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(width * 2, height * 2)
        font.pixelSize: 28
        font.variableAxes: {
            "FILL": btn.selected || btn.pulse > 0 ? 1 : 0
        }
        color: btn.ink
        opacity: 1 - btn.counting
    }

    // While held: the time still to hold, in place of the icon.
    Column {
        anchors.centerIn: parent
        spacing: -4
        opacity: btn.counting
        visible: opacity > 0
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(width * 2, height * 2)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.ceil(Math.max(0, btn.holdLeft) / 10) * 10
            font.family: btn.labelFamily
            font.pixelSize: 19
            font.weight: Font.DemiBold
            font.features: {
                "tnum": 1
            }
            color: btn.ink
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "ms"
            font.family: btn.labelFamily
            font.pixelSize: 11
            color: btn.ink
        }
    }
}
