import QtQuick
import Quickshell
import Quickshell.Wayland
import "crack.js" as Crack
import "../menu"
import "../lock"

// Full-screen overlay for one output. Stays unmapped until open() (unless keepMapped); the
// snapshot is taken before anything of ours is visible, so it never captures itself.
//
// Live mode (config "live") keeps capturing while the rift is up, so the halves show the screen
// as it carries on. That needs niri's `hide-from-own-capture` layer rule, which leaves this window
// out of its own captures; without it the halves would show the rift inside themselves.
//
// Screencopy needs the window's graphics context, which only exists once the window has been
// shown, so the window maps itself for a couple of transparent, click-through frames at startup
// ("warming") before hiding.
PanelWindow {
    id: win

    // warming → idle → capturing → spreading → opening → open → (closing | firing) → idle
    // Locking: … → open → sealing → locked → unlocking → closing → idle
    property string phase: "warming"
    readonly property bool lockPhase: phase === "sealing" || phase === "locked" || phase === "unlocking"
    readonly property bool active: phase === "capturing" || phase === "spreading" || phase === "opening" || phase === "open" || phase === "firing"
    readonly property int phaseIndex: ({
            spreading: 1,
            opening: 2,
            open: 3,
            closing: 4,
            firing: 5,
            sealing: 6,
            locked: 7,
            unlocking: 8
        })[phase] ?? 0

    // Resolved config for the current open (see Config.resolve); fixed until the next open.
    property var cfg: ({})

    // Effect slots: the names chosen for this open (cfg.fxChosen, "random" already drawn), resolved
    // through the registry; re-evaluated when a custom shader is rebuilt.
    property var registry: null
    readonly property var backgroundFx: registry ? registry.lookup("background", cfg.fxChosen?.background ?? "void", registry.builds) : null
    readonly property var edgeFx: registry ? registry.lookup("edge", cfg.fxChosen?.edge ?? "glow", registry.builds) : null
    readonly property var openingFx: registry ? registry.lookup("opening", cfg.fxChosen?.opening ?? "none", registry.builds) : null
    readonly property bool warn: !!(backgroundFx?.failed || edgeFx?.failed || openingFx?.failed)
    property bool imageMayShow: false

    property real gap: 170
    readonly property real lockGap: cfg.lock?.width ?? 250
    readonly property bool reducedMotion: cfg.motion === "reduced"
    readonly property bool crackSpread: !reducedMotion && (cfg.animation?.crackSpread ?? true)
    // Debug aid: SHATTERLOCK_SLOWMO=<factor> stretches every animation.
    readonly property real slowmo: parseFloat(Quickshell.env("SHATTERLOCK_SLOWMO") || "1")
    readonly property int spreadMs: (cfg.animation?.spreadMs ?? 120) * slowmo
    readonly property int openMs: (cfg.animation?.openMs ?? 330) * (reducedMotion ? 0.6 : 1) * slowmo
    readonly property int closeMs: (cfg.animation?.closeMs ?? 200) * slowmo
    readonly property real overshoot: reducedMotion ? 0 : cfg.animation?.overshoot ?? 0.08

    property color accent: "#cba6f7"
    property color voidColor: "#05040a"
    property string iconFamily
    property string labelFamily

    // An action was chosen (and confirmed, if it needs holding).
    signal triggered(string id)

    // [{ id, label, icon, key, confirm, command }] for this open, in order along the crack.
    property var menuActions: []

    // Locking (see lock/Locker.qml).
    property var locker: null
    property real lockAppear: 0 // the lock screen's contents
    property bool lockAfterOpen: false
    property bool lockNow: false
    property bool sealWaveDone: false
    property string sealUrl: ""
    property var grabResult: null // keeps the snapshot copy (sealUrl) alive

    // The Lock action, when shatterlock itself does the locking.
    signal lockRequested(var opts)
    // Sealed for locking: the blur wave is over and `url` holds a copy of the snapshot.
    signal sealed(string url)

    // Stay mapped (transparent, click-through) while idle: ~25 ms opens instead of ~80 ms, at the
    // cost of a surface that is always on screen (config "idle": "mapped").
    property bool keepMapped: false
    onKeepMappedChanged: {
        if (phase === "idle")
            visible = keepMapped;
    }

    // Where the action buttons sit along the crack; the crack is flattened under each of them.
    readonly property real buttonPitch: 210
    readonly property real buttonLength: 150
    readonly property real buttonThickness: 104

    // Animated state, read by every shader layer (fx/SlotLayer.qml).
    property real progress: 0      // 0 closed .. 1 open
    property real spread: 0        // how far the hairline crack has run
    property real lineAlpha: 0     // visibility of the hairline crack
    property real shake: 0         // px along the normal, for the settle after slamming shut
    property real time: 0          // seconds since the opening started
    property vector2d mouse: Qt.vector2d(-1, -1)
    property real hover: -1
    readonly property var snapshot: snapTexture
    readonly property size snapshotSize: snap.sourceSize

    // Lock blur wave: 0 none .. 1 over the whole screen, and how it looks (config lock.blur).
    property real obscure: 0
    readonly property string obscureStyle: cfg.lock?.blur ?? "void"

    // Accent as drawn: flashes red on a wrong password.
    property real alert: 0
    readonly property color effectiveAccent: Qt.tint(accent, Qt.rgba(1, 0.16, 0.2, alert))
    readonly property int openFrames: clock.openFrames

    property var crack: null
    readonly property vector2d normal: crack ? Qt.vector2d(crack.normal.x, crack.normal.y) : Qt.vector2d(0, 0)
    property real jolt: 0          // px, the halves jerking apart and back (wrong password)
    readonly property vector2d offA: normal.times(shake - jolt - 0.5 * gap * progress)
    readonly property vector2d offB: normal.times(shake + jolt + 0.5 * gap * progress)

    // The halves follow the live screen (config "live"), except from the Lock press until the
    // session is unlocked again: the lock screen keeps the frame from the press. A rift opened
    // straight into locking (a bind, idle, logind) never goes live before it.
    readonly property bool live: cfg.live === true
    readonly property bool capturingLive: live && (phase === "unlocking" || phase === "closing" || (active && !lockAfterOpen))

    // Timing of the last open, ms since the epoch (for `shatterlock stats`).
    property var timings: ({})

    property bool captured: false
    property bool mapped: false

    visible: true
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    mask: active || lockPhase || phase === "closing" ? null : clickThrough
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shatterlock"
    WlrLayershell.keyboardFocus: active || lockPhase ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Region {
        id: clickThrough
    }

    // mode "menu": the action buttons; "lock": straight into sealing, no buttons (`now`: no
    // animation at all, for locking before sleep).
    function open(config, mode, now) {
        if (phase === "closing" && mode !== "lock") {
            // Changed our mind mid-slam: part again from where the halves are.
            closeSeq.stop();
            reopenSeq.start();
            return;
        }
        if (phase === "closing")
            abort("relock");
        if (phase !== "idle")
            return;
        cfg = config;
        timings = {
            requested: Date.now()
        };
        lockAfterOpen = mode === "lock";
        lockNow = mode === "lock" && !!now;
        gap = cfg.rift?.width ?? 170;
        menuActions = lockAfterOpen ? [] : (cfg.actions ?? []).map(id => Object.assign({
                id: id
            }, cfg.actionDefs[id]));
        inputArea.forceActiveFocus();
        menu.reset();
        menu.appear = 0;
        statusText = "";
        errorText = "";
        buildCrack();
        phase = "capturing";
        progress = 0;
        spread = crackSpread ? 0 : 1;
        lineAlpha = crackSpread ? 1 : 0;
        shake = 0;
        time = 0;
        captured = false;
        mapped = keepMapped && visible;
        // Map (still fully transparent) while the capture is in flight, so the two waits overlap.
        visible = true;
        // A fresh capture context grabs one frame on creation and resets hasContent.
        snap.captureSource = null;
        snap.captureSource = win.screen;
    }

    function close(reason) {
        if (phase === "capturing") {
            timings.closedBy = reason ?? "unknown";
            finishClose();
            return;
        }
        if (!active)
            return;
        timings.closedBy = reason ?? "unknown";
        timings.closedAt = Date.now();
        openSeq.stop();
        reopenSeq.stop();
        phase = "closing";
        closeSeq.start();
    }

    // Both the snapshot and the first mapped frame are ready: show the halves at progress 0
    // (pixel-identical to the real screen) and start.
    function startOpening() {
        if (phase !== "capturing" || !captured || !mapped)
            return;
        timings.started = Date.now();
        if (lockNow) {
            spread = 1;
            lineAlpha = 0;
            progress = 1;
            seal(true);
            return;
        }
        openSeq.start();
    }

    // Gone at once, no animation (e.g. its output disappeared).
    function abort(reason) {
        timings.closedBy = reason;
        openSeq.stop();
        reopenSeq.stop();
        closeSeq.stop();
        finishClose();
    }

    function finishClose() {
        phase = "idle";
        progress = 0;
        lineAlpha = 0;
        shake = 0;
        jolt = 0;
        alert = 0;
        obscure = 0;
        lockAppear = 0;
        lockAfterOpen = false;
        lockNow = false;
        grabResult = null;
        sealUrl = "";
        visible = keepMapped;
        snap.captureSource = null;
    }

    function buildCrack() {
        const w = win.screen?.width ?? win.width;
        const h = win.screen?.height ?? win.height;
        const count = menuActions.length;
        const length = Math.hypot(w, h);
        const anchors = [];
        if (lockAfterOpen) {
            // Under the lock screen's groups (see LockUI.centreAt).
            const squeeze = Math.min(1, length / 2900);
            for (const px of [-640, -300, 40, 400, 730])
                anchors.push(0.5 + px * squeeze / length);
        } else {
            // Small outputs: squeeze the buttons together so they all fit along the diagonal.
            const pitch = Math.min(buttonPitch, length * 0.82 / Math.max(1, count - 1));
            for (let i = 0; i < count; i++)
                anchors.push(0.5 + (i - (count - 1) / 2) * pitch / length);
        }

        let seed = cfg.rift?.seed ?? 1;
        if (seed === "random")
            seed = Math.floor(Math.random() * 2147483647);

        crack = Crack.generate({
            width: w,
            height: h,
            corners: cfg.rift?.corners ?? "bl-tr",
            seed: seed,
            jaggedness: cfg.rift?.jaggedness ?? 0.6,
            branches: cfg.rift?.branches ?? true,
            anchors: anchors,
            anchorHalfLength: lockAfterOpen ? 170 : buttonLength / 2 + 10,
            anchorSlack: Math.max(3, ((lockAfterOpen ? lockGap : gap) - buttonThickness) / 2 - 6)
        });
    }

    ScreencopyView {
        id: snap
        anchors.fill: parent
        live: win.capturingLive
        paintCursor: false

        onHasContentChanged: {
            if (!hasContent || win.phase !== "capturing")
                return;
            win.timings.captured = Date.now();
            win.captured = true;
            win.startOpening();
        }
    }

    // ScreencopyView draws its own node rather than providing a texture, so shaders sample it
    // through this (re-rendered only when a new capture arrives). Mipmapped for the lock blur.
    ShaderEffectSource {
        id: snapTexture
        sourceItem: snap
        // Exactly the captured buffer: Qt's own guess uses the screen's rounded-up scale (2 for 1.5)
        // and would leave the picture filling only part of the texture.
        textureSize: snap.sourceSize
        mipmap: true
        hideSource: true
        visible: false
    }

    // The rift itself. While warming it also draws every built-in shader once, invisibly, so their
    // pipelines exist before the first open picks one.
    RiftView {
        id: view
        anchors.fill: parent
        rift: win
        snapshotSource: snapTexture
        warming: win.phase === "warming"
    }

    onPhaseChanged: {
        if (phase === "opening" && !reducedMotion)
            view.startShards();
    }

    SequentialAnimation {
        id: openSeq
        ScriptAction {
            script: win.phase = win.crackSpread ? "spreading" : "opening"
        }
        NumberAnimation {
            target: win
            property: "spread"
            to: 1
            duration: win.crackSpread ? win.spreadMs : 0
            easing.type: Easing.InQuad
        }
        ScriptAction {
            script: win.phase = "opening"
        }
        ParallelAnimation {
            NumberAnimation {
                target: win
                property: "progress"
                from: 0
                to: 1
                duration: win.openMs
                easing.type: win.overshoot > 0 ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: win.overshoot * 17
            }
            NumberAnimation {
                target: win
                property: "lineAlpha"
                to: 0
                duration: win.openMs * 0.4
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: win.openMs * 0.45
                }
                NumberAnimation {
                    target: menu
                    property: "appear"
                    to: 1
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }
        }
        ScriptAction {
            script: win.finishOpening()
        }
    }

    SequentialAnimation {
        id: reopenSeq
        ScriptAction {
            script: win.phase = "opening"
        }
        ParallelAnimation {
            NumberAnimation {
                target: win
                property: "progress"
                to: 1
                duration: win.openMs * 0.6
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: win
                properties: "lineAlpha,shake"
                to: 0
                duration: win.openMs * 0.3
            }
            NumberAnimation {
                target: menu
                property: "appear"
                to: 1
                duration: win.openMs * 0.6
            }
        }
        ScriptAction {
            script: win.finishOpening()
        }
    }

    function finishOpening() {
        phase = "open";
        timings.opened = Date.now();
        timings.worstFrameMs = pacing.worstMs;
        timings.framesWhileOpening = pacing.frames;
        timings.hitches = pacing.hitches;
        if (lockAfterOpen)
            seal(false);
    }

    // Lock: the menu goes, the rift widens, the blur wave runs out from its edges, then the snapshot
    // is copied for the lock surface and sealed() fires. `now`: all at once.
    //
    // The copy waits for the wave so that it matches what the rift shows: a live capture still in
    // flight at the press can land a frame later.
    function seal(now) {
        if (phase === "idle" || phase === "warming" || lockPhase)
            return;
        openSeq.stop();
        reopenSeq.stop();
        closeSeq.stop();
        phase = "sealing";
        timings.sealStarted = Date.now();
        sealWaveDone = false;
        sealUrl = "";
        grabResult = null;
        if (now) {
            menu.appear = 0;
            progress = 1;
            gap = lockGap;
            obscure = 1;
            lockAppear = 1;
            sealWaveDone = true;
            checkSealed();
        } else {
            sealSeq.start();
        }
    }

    function checkSealed() {
        if (phase !== "sealing" || !sealWaveDone)
            return;
        if (sealUrl !== "") {
            timings.sealed = Date.now();
            sealed(sealUrl);
        } else if (grabResult === null) {
            grabResult = {}; // in flight
            snap.grabToImage(result => {
                if (win.phase !== "sealing")
                    return;
                win.grabResult = result;
                win.sealUrl = result.url.toString();
                win.checkSealed();
            }, snap.sourceSize);
        }
    }

    function lockedNow() {
        phase = "locked";
        if (locker?.preview)
            lockLoader.item?.focusInput();
    }

    // Unlocked: the fog clears, then the halves slam shut and the live screen comes back.
    function unseal() {
        sealSeq.stop();
        quakeSeq.stop();
        phase = "unlocking";
        unsealSeq.start();
    }

    // Wrong password: an aftershock, and the edges flash red.
    function quake() {
        quakeSeq.restart();
    }

    SequentialAnimation {
        id: sealSeq
        ParallelAnimation {
            NumberAnimation {
                target: menu
                property: "appear"
                to: 0
                duration: 120
            }
            NumberAnimation {
                target: win
                property: "gap"
                to: win.lockGap
                duration: 450
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: win
                property: "progress"
                to: 1
                duration: 250
            }
            NumberAnimation {
                target: win
                property: "obscure"
                from: 0
                to: 1
                duration: (win.cfg.lock?.waveMs ?? 900) * win.slowmo
                easing.type: Easing.InOutSine
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 250
                }
                NumberAnimation {
                    target: win
                    property: "lockAppear"
                    to: 1
                    duration: 350
                    easing.type: Easing.OutCubic
                }
            }
        }
        ScriptAction {
            script: {
                win.sealWaveDone = true;
                win.checkSealed();
            }
        }
    }

    SequentialAnimation {
        id: unsealSeq
        ParallelAnimation {
            NumberAnimation {
                target: win
                property: "lockAppear"
                to: 0
                duration: 180
            }
            NumberAnimation {
                target: win
                property: "obscure"
                to: 0
                duration: 450 * win.slowmo
                easing.type: Easing.InQuad
            }
        }
        ScriptAction {
            script: {
                win.phase = "closing";
                closeSeq.start();
            }
        }
    }

    SequentialAnimation {
        id: quakeSeq
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation {
                    target: win
                    property: "jolt"
                    to: win.reducedMotion ? 0 : 16
                    duration: 45
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: win
                    property: "jolt"
                    to: win.reducedMotion ? 0 : -9
                    duration: 60
                }
                NumberAnimation {
                    target: win
                    property: "jolt"
                    to: win.reducedMotion ? 0 : 6
                    duration: 55
                }
                NumberAnimation {
                    target: win
                    property: "jolt"
                    to: 0
                    duration: 80
                    easing.type: Easing.OutQuad
                }
            }
            SequentialAnimation {
                NumberAnimation {
                    target: win
                    property: "shake"
                    to: win.reducedMotion ? 0 : -7
                    duration: 40
                }
                NumberAnimation {
                    target: win
                    property: "shake"
                    to: win.reducedMotion ? 0 : 6
                    duration: 55
                }
                NumberAnimation {
                    target: win
                    property: "shake"
                    to: win.reducedMotion ? 0 : -3
                    duration: 55
                }
                NumberAnimation {
                    target: win
                    property: "shake"
                    to: 0
                    duration: 70
                }
            }
            SequentialAnimation {
                NumberAnimation {
                    target: win
                    property: "alert"
                    to: 1
                    duration: 60
                }
                PauseAnimation {
                    duration: 250
                }
                NumberAnimation {
                    target: win
                    property: "alert"
                    to: 0
                    duration: 550
                }
            }
        }
    }

    // Slam shut, settle, let the seam fade, then give the live screen back.
    SequentialAnimation {
        id: closeSeq
        ParallelAnimation {
            NumberAnimation {
                target: menu
                property: "appear"
                to: 0
                duration: 80
            }
            NumberAnimation {
                target: win
                property: "progress"
                to: 0
                duration: win.closeMs
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: win
                property: "lineAlpha"
                to: 1
                duration: win.closeMs
            }
            NumberAnimation {
                target: win
                property: "spread"
                to: 1
                duration: 0
            }
        }
        SequentialAnimation {
            NumberAnimation {
                target: win
                property: "shake"
                to: win.reducedMotion ? 0 : 2
                duration: 30
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: win
                property: "shake"
                to: win.reducedMotion ? 0 : -1
                duration: 45
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: win
                property: "shake"
                to: 0
                duration: 45
                easing.type: Easing.InOutQuad
            }
        }
        NumberAnimation {
            target: win
            property: "lineAlpha"
            to: 0
            duration: 90
        }
        ScriptAction {
            script: win.finishClose()
        }
    }

    FrameAnimation {
        id: warmup
        running: win.phase === "warming"
        onTriggered: {
            if (currentFrame >= 3) {
                win.visible = win.keepMapped;
                win.phase = "idle";
            }
        }
    }

    // The render loop ticks this once the mapped window starts producing frames.
    FrameAnimation {
        running: win.visible && win.phase === "capturing" && !win.mapped
        onTriggered: {
            win.timings.mapped = Date.now();
            win.mapped = true;
            win.startOpening();
        }
    }

    // Shader clock.
    FrameAnimation {
        id: clock
        running: win.phase !== "idle" && win.phase !== "warming" && win.phase !== "capturing"
        property int openFrames: 0
        onRunningChanged: {
            if (running) {
                win.time = 0;
                openFrames = 0;
            }
        }
        onTriggered: {
            win.time = elapsedTime;
            if (win.phase === "open")
                openFrames++;
        }
    }

    // Frame pacing while opening (for `shatterlock stats`).
    FrameAnimation {
        id: pacing
        property real worstMs: 0
        property int frames: 0
        running: win.phase === "spreading" || win.phase === "opening"
        property var hitches: []
        onRunningChanged: {
            if (running) {
                worstMs = 0;
                frames = 0;
                hitches = [];
            }
        }
        onTriggered: {
            frames++;
            if (frames > 1)
                worstMs = Math.max(worstMs, frameTime * 1000);
            if (frameTime > 0.009)
                hitches.push(`${frames}:${win.phase}:${Math.round(frameTime * 1000)}ms`);
        }
    }

    RiftMenu {
        id: menu
        anchors.fill: parent
        actions: win.menuActions
        points: win.crack?.anchorPoints ?? []
        angle: win.crack?.angle ?? 0
        holdMs: win.cfg.animation?.holdMs ?? 600
        interactive: win.phase === "opening" || win.phase === "open"
        accent: win.accent
        iconFamily: win.iconFamily
        labelFamily: win.labelFamily
        onFire: id => win.fire(id)
        onSelectedChanged: win.hover = selected
    }

    // What the rift shows while a "stay" action runs, and the last failure.
    property string statusText: ""
    property string errorText: ""

    // "vanish" actions (lock, suspend, ...) remove the rift at once and then run. "stay" actions
    // (shutdown, ...) keep it, show their status, and bring the menu back if they fail.
    function fire(id) {
        const def = menuActions.find(a => a.id === id);
        if (!def)
            return;
        timings.fired = id;
        if (id === "lock" && (cfg.lock?.enabled ?? true)) {
            // shatterlock locks itself (falling back to the command if it can't).
            lockRequested({});
            return;
        }
        errorText = "";
        if (def.after === "vanish") {
            timings.closedBy = "action:" + id;
            openSeq.stop();
            reopenSeq.stop();
            finishClose();
            triggered(id);
            return;
        }
        openSeq.stop();
        reopenSeq.stop();
        progress = Math.max(progress, 1);
        phase = "firing";
        statusText = def.status || `${def.label}…`;
        menu.appear = 0;
        triggered(id);
    }

    function actionFinished(id, ok, message, wasDryRun) {
        if (phase !== "firing")
            return;
        if (!ok) {
            statusText = "";
            errorText = `${message}`;
            errorTimer.restart();
            phase = "open";
            menu.appear = 1;
        } else if (wasDryRun) {
            close("dry-run:" + id);
        } else {
            // The session or the machine is going away; if it hasn't after a while, step aside.
            staleTimer.restart();
        }
    }

    Timer {
        id: errorTimer
        interval: 5000
        onTriggered: win.errorText = ""
    }

    Timer {
        id: staleTimer
        interval: 20000
        onTriggered: win.close("stale")
    }

    RiftStatus {
        at: win.crack ? Qt.point(win.crack.pointAt(0.5).x, win.crack.pointAt(0.5).y) : Qt.point(0, 0)
        angle: win.crack?.angle ?? 0
        text: win.statusText
        appear: win.phase === "firing" && win.statusText !== "" ? 1 : 0
        accent: win.accent
        family: win.labelFamily

        Behavior on appear {
            NumberAnimation {
                duration: 200
            }
        }
    }

    // Errors sit near the end of the rift, clear of the buttons.
    RiftStatus {
        at: win.crack ? Qt.point(win.crack.pointAt(0.86).x, win.crack.pointAt(0.86).y) : Qt.point(0, 0)
        angle: win.crack?.angle ?? 0
        text: win.errorText
        isError: true
        appear: win.errorText !== "" && win.phase === "open" ? 1 : 0
        accent: win.accent
        family: win.labelFamily

        Behavior on appear {
            NumberAnimation {
                duration: 200
            }
        }
    }

    // Whether a point lies in the open gap (and not on either half).
    function insideRift(x, y) {
        if (!crack)
            return false;
        const off = crack.offsetFrom(x - normal.x * shake, y - normal.y * shake);
        return Math.abs(off) < gap * progress / 2;
    }

    // Up/Down follow the rift's slope: with "bl-tr" it climbs to the right, so Up moves right.
    readonly property int upStep: (crack?.dir.y ?? 0) < 0 ? 1 : -1

    Item {
        id: inputArea
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            event.accepted = true;
            if (event.isAutoRepeat || win.lockPhase)
                return;
            switch (event.key) {
            case Qt.Key_Escape:
                win.close("escape");
                return;
            case Qt.Key_Right:
            case Qt.Key_Tab:
                menu.step(1);
                return;
            case Qt.Key_Left:
            case Qt.Key_Backtab:
                menu.step(-1);
                return;
            case Qt.Key_Up:
                menu.step(win.upStep);
                return;
            case Qt.Key_Down:
                menu.step(-win.upStep);
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                menu.press(menu.selected, event.key);
                return;
            }
            const i = menu.indexForKey(event.text);
            if (i >= 0)
                menu.press(i, event.key);
            else
                event.accepted = false;
        }

        Keys.onReleased: event => {
            if (!event.isAutoRepeat)
                menu.release(event.key);
        }

        MouseArea {
            id: pointer
            property int hovered: -1

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: hovered >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor

            onPositionChanged: mouse => {
                win.mouse = Qt.vector2d(mouse.x, mouse.y);
                hovered = menu.indexAt(mouse.x, mouse.y);
                if (hovered >= 0)
                    menu.selected = hovered;
            }
            onPressed: mouse => {
                if (win.lockPhase)
                    return;
                const i = menu.indexAt(mouse.x, mouse.y);
                if (i >= 0)
                    menu.press(i, "mouse");
                else if (!win.insideRift(mouse.x, mouse.y))
                    win.close("click");
            }
            onReleased: menu.release("mouse")
        }
    }

    // The lock screen's contents, shown here while sealing and in preview; the lock surface
    // (lock/Locker.qml) shows its own copy once the session is locked.
    Loader {
        id: lockLoader
        anchors.fill: parent
        active: win.locker !== null
        sourceComponent: LockUI {
            rift: win
            locker: win.locker
            info: win.locker.info
            appear: win.lockAppear
        }
    }
}
