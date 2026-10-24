import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "rift"
import "actions"
import "fx"
import "lock"

ShellRoot {
    id: root

    RiftWindow {
        id: rift
        registry: registry
        imageMayShow: Config.current.fx?.background === "image" || (Config.current.fx?.background === "random" && (Config.current.fx?.pool?.background ?? []).includes("image"))
        keepMapped: Config.current.idle === "mapped"
        accent: Theme.accent
        voidColor: Theme.voidColor
        iconFamily: Theme.iconFamily
        labelFamily: Theme.labelFamily

        locker: locker
        onLockRequested: opts => root.lock(opts)
        onSealed: url => locker.sealed(url)

        onTriggered: id => runner.run(Object.assign({
                id: id
            }, rift.cfg.actionDefs[id]), rift.cfg.dryRun)
    }

    Locker {
        id: locker
        rift: rift
        cfg: Config.current
        onLockRequested: opts => root.lock(opts)
    }

    ShaderRegistry {
        id: registry
    }

    ActionRunner {
        id: runner
        onFinished: (id, ok, message) => rift.actionFinished(id, ok, message, rift.cfg.dryRun)
    }

    // Other outputs: a click anywhere on them closes the rift too.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: rift.active && modelData.name !== rift.screen?.name
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shatterlock-catcher"

            MouseArea {
                anchors.fill: parent
                onPressed: rift.close("click")
            }
        }
    }

    function focusedScreen() {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === NiriFocus.focusedOutput)
                return screens[i];
        }
        return screens[0] ?? null;
    }

    function parseOverrides(json) {
        if (!json)
            return {};
        try {
            const o = JSON.parse(json);
            if (o !== null && typeof o === "object" && !Array.isArray(o))
                return o;
        } catch (e) {}
        console.warn(`shatterlock: overrides must be a JSON object, got ${json}`);
        return {};
    }

    // An open that arrives before the daemon is ready (just started: config loading, window warming
    // up) runs as soon as it is, if that is within a few seconds.
    property var pendingOpen: null

    function openPending() {
        if (pendingOpen === null || !Config.ready || rift.phase !== "idle")
            return;
        const p = pendingOpen;
        pendingOpen = null;
        if (Date.now() - p.at < 3000)
            open(p.overrides);
    }

    // The resolved config for one open: overrides applied, unavailable actions dropped, "random"
    // effects drawn.
    function buildConfig(overrides) {
        const cfg = Config.resolve(parseOverrides(overrides));
        cfg.actions = cfg.actions.filter(id => runner.available(cfg.actionDefs[id]));
        cfg.fxChosen = {
            background: registry.choose("background", cfg.fx),
            edge: registry.choose("edge", cfg.fx),
            opening: registry.choose("opening", cfg.fx)
        };
        if (cfg.motion === "reduced") {
            // No shaking, shards or glitching.
            cfg.fxChosen.opening = "none";
            if (cfg.fxChosen.edge === "glitch")
                cfg.fxChosen.edge = "glow";
        }
        return cfg;
    }

    function open(overrides) {
        if (!Config.ready || rift.phase === "warming") {
            pendingOpen = {
                overrides: overrides,
                at: Date.now()
            };
            return;
        }
        if (rift.active || rift.lockPhase)
            return;
        const screen = focusedScreen();
        if (!screen)
            return;
        const cfg = buildConfig(overrides);
        rift.screen = screen;
        rift.open(cfg, "menu");
        runner.probe(cfg.actionDefs);
    }

    // Lock the session (opts: { preview, now }). Seals the open rift, or opens one straight into
    // the seal. Without its PAM service shatterlock won't lock, and runs the Lock action's command
    // instead.
    function lock(opts) {
        opts = opts ?? {};
        if (rift.lockPhase)
            return;
        if (!Config.ready || rift.phase === "warming") {
            lockRetry.opts = opts;
            lockRetry.restart();
            return;
        }
        if (!locker.canLock(opts)) {
            fallbackLock();
            if (rift.active)
                rift.close("lock-fallback");
            return;
        }
        locker.begin(opts);
        if (["spreading", "opening", "open", "firing"].includes(rift.phase)) {
            rift.seal(!!opts.now);
        } else if (rift.phase === "capturing") {
            rift.menuActions = [];
            rift.lockAfterOpen = true;
            rift.lockNow = !!opts.now;
        } else {
            const screen = focusedScreen();
            if (!screen)
                return;
            rift.screen = screen;
            rift.open(buildConfig(""), "lock", !!opts.now);
        }
    }

    function fallbackLock() {
        const def = Config.current.actionDefs?.lock;
        if (def)
            runner.run(Object.assign({
                id: "lock"
            }, def), Config.current.dryRun);
    }

    Timer {
        id: lockRetry
        property var opts: ({})
        interval: 300
        onTriggered: root.lock(opts)
    }

    function toggle(overrides) {
        if (rift.lockPhase)
            return;
        if (rift.active)
            rift.close("toggle");
        else
            open(overrides);
    }

    // One line per command: `open {json}`, `toggle {json}`, `close`, `reload` or `lock {json}`.
    function command(line) {
        const sp = line.indexOf(" ");
        const cmd = sp < 0 ? line : line.slice(0, sp);
        const arg = sp < 0 ? "" : line.slice(sp + 1);
        switch (cmd) {
        case "open":
            open(arg);
            break;
        case "toggle":
            toggle(arg);
            break;
        case "close":
            rift.close("command");
            break;
        case "reload":
            Config.reload();
            break;
        case "lock":
            lock(parseOverrides(arg));
            break;
        default:
            console.warn(`shatterlock: unknown command "${cmd}"`);
        }
    }

    // Fast path for compositor binds (`nc -NU`, ~5 ms; `quickshell ipc call` costs ~50 ms).
    // `<socket>.owner` says which build it belongs to, so the CLI of a newer build doesn't talk to
    // an older daemon after an upgrade.
    SocketServer {
        id: socket
        active: true
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shatterlock.sock"
        handler: Socket {
            parser: SplitParser {
                onRead: line => root.command(line)
            }
        }
        Component.onCompleted: owner.setText(Quickshell.shellDir)
    }

    FileView {
        id: owner
        path: socket.path + ".owner"
        printErrors: false
    }

    IpcHandler {
        target: "rift"

        function open(overrides: string): void {
            root.open(overrides);
        }
        function toggle(overrides: string): void {
            root.toggle(overrides);
        }
        function close(): void {
            rift.close("command");
        }
        function reload(): void {
            Config.reload();
        }
        // options: JSON, e.g. {"preview": true} or {"now": true}
        function lock(options: string): void {
            root.lock(root.parseOverrides(options));
        }
        function stats(): string {
            return JSON.stringify(Object.assign({
                shaderTime: rift.time,
                openFrames: rift.openFrames,
                live: rift.live,
                capturing: rift.capturingLive,
                fx: rift.cfg.fxChosen,
                geometry: {
                    screen: rift.screen ? [rift.screen.name, rift.screen.width, rift.screen.height, rift.screen.devicePixelRatio] : null,
                    window: [rift.width, rift.height],
                    snapshot: [rift.snapshotSize.width, rift.snapshotSize.height],
                    crackLength: rift.crack?.length ?? null
                },
                warn: rift.warn,
                mouse: [Math.round(rift.mouse.x), Math.round(rift.mouse.y)],
                buttons: (rift.crack?.anchorPoints ?? []).map(p => [Math.round(p.x), Math.round(p.y)])
            }, rift.timings));
        }
        // The config an open with these overrides would use.
        function config(overrides: string): string {
            return JSON.stringify(Config.resolve(root.parseOverrides(overrides)), null, 2);
        }
        function status(): string {
            return JSON.stringify({
                phase: rift.phase,
                focusedOutput: NiriFocus.focusedOutput,
                screen: root.focusedScreen()?.name ?? null,
                configPath: Config.userPath,
                packagedSettings: Config.packagedPath,
                configReady: Config.ready,
                live: Config.current.live ?? false,
                accent: Theme.accent.toString(),
                capabilities: runner.capabilities,
                runnerBusy: runner.busy,
                lock: {
                    pamReady: locker.pamReady,
                    fingerprintReady: locker.fingerprintReady,
                    sessionLocked: locker.sessionLocked,
                    preview: locker.preview,
                    busy: locker.busy,
                    message: locker.message,
                    sessionPath: locker.sessionPath
                }
            }, null, 2);
        }
    }

    // Debug aid: SHATTERLOCK_AUTOCLOSE=<ms> closes the rift on its own after it opens.
    Timer {
        interval: parseInt(Quickshell.env("SHATTERLOCK_AUTOCLOSE") || "0")
        running: interval > 0 && rift.phase === "open"
        onTriggered: rift.close("autoclose")
    }

    Connections {
        target: rift
        function onPhaseChanged() {
            root.openPending();
        }
    }

    // The rift's output went away (unplugged, turned off): drop the rift at once.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (rift.phase === "idle" || rift.phase === "warming")
                return;
            const screens = Quickshell.screens;
            for (let i = 0; i < screens.length; i++) {
                if (screens[i].name === rift.screen?.name)
                    return;
            }
            rift.abort("output-gone");
        }
    }

    Connections {
        target: Config
        function onReloaded() {
            root.openPending();
            runner.probe(Config.current.actionDefs);
            registry.track(Config.current.fx);
            console.info(`shatterlock: config loaded (${Config.current.actions.length} actions)`);
        }
    }
}
