pragma ComponentBehavior: Bound

import QtQuick

// The actions inside the rift: one button per action, centred on the crack and turned to its
// angle. Owns selection and hold-to-confirm; a chosen action pulses once, then fire(id) runs it.
Item {
    id: menu

    property var actions: []   // [{ id, label, icon, key, confirm, after }]
    property var points: []    // button centres, px
    property real angle: 0     // degrees, direction of the rift
    property int holdMs: 600
    property int pulseMs: 240
    property real appear: 0    // 0..1, staggered across the buttons
    property bool interactive: false

    property color accent: "#cba6f7"
    property string iconFamily
    property string labelFamily
    property bool material: false // Material icon buttons (config menu.buttons)
    property var roles: ({})      // Material colour roles, for those

    property int selected: -1
    property int holdIndex: -1
    property var holdSource: null // key code or "mouse" that started the hold
    property real holdProgress: 0

    // The chosen action pulses before it runs; nothing else can be chosen meanwhile.
    property int pulseIndex: -1
    property real pulse: 0
    property bool pulseFromHold: false
    property var pulseSource: null  // key code or "mouse" that chose it
    property bool sourceDown: false // that key is still held
    property bool awaitingRelease: false
    readonly property bool committed: pulseIndex >= 0

    // The button that is held or pulsing, and how charged it is (its glow swells with it).
    readonly property int chargeIndex: pulseIndex >= 0 ? pulseIndex : holdIndex
    readonly property real charge: pulseIndex >= 0 ? (pulseFromHold ? 1 - pulse : 0) : (holdIndex >= 0 ? holdProgress : 0)

    signal fire(string id)

    function reset() {
        selected = -1;
        holdAnim.stop();
        cancelAnim.stop();
        holdIndex = -1;
        holdSource = null;
        holdProgress = 0;
        settle();
    }

    // The chosen action is done with (it failed and the menu is back): choosing works again.
    function settle() {
        pulseAnim.stop();
        pulseIndex = -1;
        pulse = 0;
        pulseFromHold = false;
        pulseSource = null;
        sourceDown = false;
        awaitingRelease = false;
    }

    function step(delta) {
        if (actions.length === 0 || committed)
            return;
        if (selected < 0)
            selected = delta > 0 ? 0 : actions.length - 1;
        else
            selected = (selected + delta + actions.length) % actions.length;
    }

    function indexForKey(text) {
        const k = (text ?? "").toUpperCase();
        if (k === "")
            return -1;
        return actions.findIndex(a => (a.key ?? "").toUpperCase() === k);
    }

    // Index of the button under a point in menu coordinates, or -1.
    function indexAt(x, y) {
        const buttons = menu.material ? materialButtons : glowButtons;
        for (let i = 0; i < buttons.count; i++) {
            const b = buttons.itemAt(i);
            if (b && b.appear > 0.5 && b.contains(b.mapFromItem(menu, x, y)))
                return i;
        }
        return -1;
    }

    // Instant actions pulse right away; the others start filling and pulse when full.
    function press(index, source) {
        if (!interactive || committed || index < 0 || index >= actions.length)
            return;
        selected = index;
        if (actions[index].confirm !== "hold") {
            startPulse(index, source, false);
            return;
        }
        cancelAnim.stop();
        holdIndex = index;
        holdSource = source;
        holdAnim.restart();
    }

    function release(source) {
        if (committed) {
            if (source === pulseSource) {
                sourceDown = false;
                if (awaitingRelease)
                    finish();
            }
            return;
        }
        if (holdIndex < 0 || source !== holdSource || !holdAnim.running)
            return;
        holdAnim.stop();
        cancelAnim.restart();
    }

    function startPulse(index, source, fromHold) {
        holdAnim.stop();
        cancelAnim.stop();
        holdIndex = -1;
        holdSource = null;
        holdProgress = 0;
        pulseIndex = index;
        pulseFromHold = fromHold;
        pulseSource = source;
        sourceDown = source !== "mouse";
        awaitingRelease = false;
        pulseAnim.restart();
    }

    // Actions that take the rift away run once the key that chose them is up: its release would
    // otherwise land in the window underneath, or wake a machine that has just gone to sleep.
    function pulseDone() {
        if (sourceDown && actions[pulseIndex]?.after === "vanish")
            awaitingRelease = true;
        else
            finish();
    }

    function finish() {
        const id = actions[pulseIndex]?.id;
        awaitingRelease = false;
        if (id)
            fire(id);
    }

    // The buttons fade in one after another.
    readonly property real stagger: 0.12
    function appearOf(index) {
        return Math.max(0, Math.min(1, appear * (1 + stagger * (actions.length - 1)) - stagger * index));
    }

    Repeater {
        id: glowButtons
        model: menu.material ? [] : menu.actions

        ActionButton {
            required property var modelData
            required property int index

            x: (menu.points[index]?.x ?? 0) - width / 2
            y: (menu.points[index]?.y ?? 0) - height / 2
            rotation: menu.angle
            label: modelData.label ?? modelData.id
            icon: modelData.icon ?? ""
            hotkey: modelData.key ?? ""
            needsHold: modelData.confirm === "hold"
            selected: menu.selected === index
            holdProgress: menu.chargeIndex === index ? menu.charge : 0
            holdLeft: menu.holdIndex === index && holdAnim.running ? menu.holdMs * (1 - menu.holdProgress) : -1
            pulse: menu.pulseIndex === index ? menu.pulse : 0
            appear: menu.appearOf(index)
            accent: menu.accent
            iconFamily: menu.iconFamily
            labelFamily: menu.labelFamily
        }
    }

    Repeater {
        id: materialButtons
        model: menu.material ? menu.actions : []

        MaterialButton {
            required property var modelData
            required property int index

            x: (menu.points[index]?.x ?? 0) - width / 2
            y: (menu.points[index]?.y ?? 0) - height / 2
            rotation: menu.angle
            icon: modelData.icon ?? ""
            tint: modelData.color || "transparent"
            selected: menu.selected === index
            holdProgress: menu.chargeIndex === index ? menu.charge : 0
            holdLeft: menu.holdIndex === index && holdAnim.running ? menu.holdMs * (1 - menu.holdProgress) : -1
            pulse: menu.pulseIndex === index ? menu.pulse : 0
            appear: menu.appearOf(index)
            accent: menu.accent
            roles: menu.roles
            iconFamily: menu.iconFamily
            labelFamily: menu.labelFamily
        }
    }

    NumberAnimation {
        id: holdAnim
        target: menu
        property: "holdProgress"
        from: 0
        to: 1
        duration: menu.holdMs
        onFinished: menu.startPulse(menu.holdIndex, menu.holdSource, true)
    }

    NumberAnimation {
        id: cancelAnim
        target: menu
        property: "holdProgress"
        to: 0
        duration: 140
        easing.type: Easing.OutCubic
        onFinished: {
            menu.holdIndex = -1;
            menu.holdSource = null;
        }
    }

    NumberAnimation {
        id: pulseAnim
        target: menu
        property: "pulse"
        from: 0
        to: 1
        duration: menu.pulseMs
        easing.type: Easing.OutSine
        onFinished: menu.pulseDone()
    }
}
