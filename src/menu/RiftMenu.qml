pragma ComponentBehavior: Bound

import QtQuick

// The actions inside the rift: one button per action, centred on the crack and turned to its
// angle. Owns selection and hold-to-confirm; emits fire(id) when an action should run.
Item {
    id: menu

    property var actions: []   // [{ id, label, icon, key, confirm }]
    property var points: []    // button centres, px
    property real angle: 0     // degrees, direction of the rift
    property int holdMs: 600
    property real appear: 0    // 0..1, staggered across the buttons
    property bool interactive: false

    property color accent: "#cba6f7"
    property string iconFamily
    property string labelFamily

    property int selected: -1
    property int holdIndex: -1
    property var holdSource: null // key code or "mouse" that started the hold
    property real holdProgress: 0

    signal fire(string id)

    function reset() {
        selected = -1;
        holdAnim.stop();
        cancelAnim.stop();
        holdIndex = -1;
        holdSource = null;
        holdProgress = 0;
    }

    function step(delta) {
        if (actions.length === 0)
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
        for (let i = 0; i < buttons.count; i++) {
            const b = buttons.itemAt(i);
            if (b && b.appear > 0.5 && b.contains(b.mapFromItem(menu, x, y)))
                return i;
        }
        return -1;
    }

    // Instant actions fire right away; the others start filling and fire when full.
    function press(index, source) {
        if (!interactive || index < 0 || index >= actions.length)
            return;
        selected = index;
        if (actions[index].confirm !== "hold") {
            fire(actions[index].id);
            return;
        }
        cancelAnim.stop();
        holdIndex = index;
        holdSource = source;
        holdAnim.restart();
    }

    function release(source) {
        if (holdIndex < 0 || source !== holdSource || !holdAnim.running)
            return;
        holdAnim.stop();
        cancelAnim.restart();
    }

    Repeater {
        id: buttons
        model: menu.actions

        ActionButton {
            required property var modelData
            required property int index

            readonly property real stagger: 0.12

            x: (menu.points[index]?.x ?? 0) - width / 2
            y: (menu.points[index]?.y ?? 0) - height / 2
            rotation: menu.angle
            label: modelData.label ?? modelData.id
            icon: modelData.icon ?? ""
            hotkey: modelData.key ?? ""
            needsHold: modelData.confirm === "hold"
            selected: menu.selected === index
            holdProgress: menu.holdIndex === index ? menu.holdProgress : 0
            appear: Math.max(0, Math.min(1, menu.appear * (1 + stagger * (menu.actions.length - 1)) - stagger * index))
            accent: menu.accent
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
        onFinished: {
            const id = menu.actions[menu.holdIndex]?.id;
            menu.holdIndex = -1;
            menu.holdSource = null;
            menu.holdProgress = 0;
            if (id)
                menu.fire(id);
        }
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
}
