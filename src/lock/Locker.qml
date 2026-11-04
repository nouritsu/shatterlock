pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import "../rift"

// shatterlock's lock screen. Locking seals the rift (RiftWindow.seal: a blur wave runs out from its
// edges while a copy of the snapshot is taken), then an ext-session-lock covers every output: the
// rift's output (while it is gone, the focused one) shows the same rift with the password field,
// the others dark fog. Unlocking takes the password (PAM), any of the methods in lock.methods (a
// security key, a fingerprint: AuthMethod) or logind's Unlock.
//
// It never locks without /etc/pam.d/<lock.pamService>: PAM without its service file falls back to
// "other", which denies everyone. The shell then runs the Lock action's command instead.
Scope {
    id: locker

    required property var rift
    property var cfg: ({})

    readonly property var options: cfg.lock ?? ({})
    readonly property bool enabled: options.enabled ?? true
    readonly property string pamService: options.pamService ?? "shatterlock"
    readonly property bool pamReady: pamFile.loaded

    // The other ways to unlock, in lock.methods order.
    readonly property var methods: {
        const ids = options.methods ?? [];
        const all = methodVariants.instances;
        const out = [];
        for (let i = 0; i < all.length; i++)
            out.push(all[i]);
        return out.sort((a, b) => ids.indexOf(a.name) - ids.indexOf(b.name));
    }
    // The method the password field types into for now (its PIN prompt), or null: the password.
    property var inputMethod: null

    readonly property SecurityKeys keys: SecurityKeys {
        active: locker.rift.lockPhase && locker.methods.some(m => m.detects && m.ready)
    }

    // Locked for show only: the overlay plays the lock, PAM runs, but the session stays unlocked.
    property bool preview: false
    // The compositor has locked the session. Not sessionLock.locked: Quickshell 0.3.2 doesn't
    // notify that going false (fixed upstream after 0.3.2), so it would stay true after an unlock.
    readonly property bool sessionLocked: sessionLock.secure

    // The output the rift locked on, by name. Outputs can go away and come back while locked (a
    // monitor waking from standby reconnects as a new screen), and the rift's own screen doesn't
    // follow them back, so the lock surfaces find their place by this name.
    property string output: ""
    property string focusedOutput: "" // the compositor's focused output (NiriFocus)

    // The output that shows the rift and the password field: the rift's own while it is connected,
    // else the focused one, else the first. Every other output gets fog. Whenever an output is
    // connected there is one, so the password field never disappears.
    readonly property string mainOutput: mainScreen(Quickshell.screens)?.name ?? ""

    function mainScreen(screens) {
        let focused = null;
        let first = null;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (s.name === "")
                continue; // Qt's placeholder while no output is connected
            if (s.name === output)
                return s;
            if (s.name === focusedOutput)
                focused = s;
            first = first ?? s;
        }
        return focused ?? first;
    }

    // Password field
    property string prompt: "" // what PAM asks for when it isn't the password (a one-time code)
    property string message: ""
    property bool messageIsError: false
    property bool busy: false
    property bool withPassword: false // a password was sent: its orbs are up when it unlocks
    property string pending: "" // typed before PAM asked for it

    // logind
    property string sessionPath: ""
    property bool sleeping: false

    readonly property LockInfo info: LockInfo {
        active: locker.rift.lockPhase
    }

    signal lockRequested(var opts)  // idle, logind, sleep: the shell decides how to open the rift
    signal clearInput
    signal rejected // a wrong password

    // Whether a lock with these options can go ahead; logs why not.
    function canLock(opts) {
        if (opts?.preview)
            return true;
        if (!enabled) {
            console.warn("shatterlock: lock.enabled is false");
            return false;
        }
        if (!pamReady) {
            console.warn(`shatterlock: /etc/pam.d/${pamService} is missing, so shatterlock won't lock (add security.pam.services.${pamService} = {})`);
            return false;
        }
        return true;
    }

    // Called by the shell just before it seals the rift.
    function begin(opts) {
        preview = !!opts?.preview;
        prompt = "";
        message = "";
        messageIsError = false;
        busy = false;
        withPassword = false;
        pending = "";
        inputMethod = null;
        for (const m of methods)
            m.reset();
        clearInput();
    }

    // The rift is sealed and its snapshot copied: take the session.
    function sealed(url) {
        snapshotUrl = url;
        output = rift.screen?.name || output;
        if (preview)
            enterLocked();
        else
            sessionLock.locked = true;
    }

    property string snapshotUrl: ""

    function enterLocked() {
        rift.lockedNow();
        if (!preview)
            lockedHint(true);
        if (sleeping)
            inhibitor.running = false; // locked: let the machine sleep
        startAuth();
    }

    // The password's PAM conversation. The methods start on their own once locked.
    function startAuth() {
        if (!pam.active && !pam.start()) {
            busy = false;
            pending = "";
            message = `Can't check passwords: PAM service "${pamService}" didn't start`;
            messageIsError = true;
        }
    }

    function submit(text) {
        if (rift.phase !== "locked" || busy)
            return;
        if (inputMethod) { // (empty too: pam_u2f's `interactive` asks for just Enter)
            const m = inputMethod;
            inputMethod = null;
            m.respond(text);
            clearInput();
            return;
        }
        if (text === "") {
            wake();
            return;
        }
        busy = true;
        withPassword = true;
        message = "";
        if (pam.responseRequired) {
            pam.respond(text);
        } else {
            pending = text;
            startAuth();
        }
    }

    function failed(why) {
        busy = false;
        withPassword = false;
        message = why;
        messageIsError = true;
        rejected(); // while the orbs are still up: the lock screen sends them off (rift.reject)
        clearInput();
        restartAuth.restart();
    }

    // Enter in the empty field: a method that wants something typed gets the field; the others
    // that wait for it (start "enter", or handed back with Escape) start.
    function wake() {
        const asking = methods.find(m => m.status === "prompt");
        if (asking) {
            take(asking);
            return;
        }
        for (const m of methods)
            m.wake();
    }

    function take(m) {
        inputMethod = m;
        clearInput();
    }

    // Escape in the empty field while a method has it: back to the password; the method stays off
    // until Enter or a key plugged in.
    function handBack() {
        const m = inputMethod;
        inputMethod = null;
        m?.park();
    }

    // Authenticated: the fog clears from the rift (on the lock surface while locked), then
    // release() gives the session back.
    function unlock() {
        if (!rift.lockPhase || rift.phase === "unlocking")
            return;
        if (pam.active)
            pam.abort();
        for (const m of methods)
            m.stop();
        inputMethod = null;
        busy = false;
        pending = "";
        rift.unseal();
    }

    function release() {
        if (sessionLock.locked) {
            lockedHint(false);
            sessionLock.locked = false;
        }
        preview = false;
        snapshotUrl = "";
        output = "";
    }

    function cancelPreview() {
        if (preview)
            unlock();
    }

    function lockedHint(on) {
        if (sessionPath)
            Quickshell.execDetached(["busctl", "call", "org.freedesktop.login1", sessionPath, "org.freedesktop.login1.Session", "SetLockedHint", "b", on ? "true" : "false"]);
    }

    function onLogind(line) {
        if (sessionPath && line.startsWith(sessionPath + ":")) {
            if (line.includes(".Session.Lock ("))
                lockRequested({
                    reason: "logind"
                });
            else if (line.includes(".Session.Unlock ("))
                unlock();
            return;
        }
        const sleep = /\.Manager\.PrepareForSleep \((true|false)/.exec(line);
        if (!sleep)
            return;
        sleeping = sleep[1] === "true";
        if (!sleeping) {
            inhibitor.running = inhibitor.wanted;
        } else if (rift.phase === "locked" || !(options.beforeSleep ?? true)) {
            inhibitor.running = false;
        } else {
            lockRequested({
                now: true,
                reason: "sleep"
            });
        }
    }

    PamContext {
        id: pam
        config: locker.pamService
        onPamMessage: {
            if (responseRequired) {
                if (locker.pending !== "") {
                    const p = locker.pending;
                    locker.pending = "";
                    respond(p);
                } else if (!/^password:?$/i.test(message.trim()) && message.trim() !== "") {
                    locker.prompt = message.trim(); // e.g. a one-time code
                }
            } else if (message) {
                locker.message = message;
                locker.messageIsError = messageIsError;
            }
        }
        onCompleted: result => {
            if (result === PamResult.Success)
                locker.unlock();
            else if (locker.rift.phase === "locked")
                locker.failed(result === PamResult.Error ? "Couldn't check the password" : "Wrong password");
        }
    }

    Variants {
        id: methodVariants
        model: locker.options.methods ?? []

        AuthMethod {
            id: method
            locker: locker
            onSucceeded: locker.unlock()
            onPrompting: {
                if (method.userWoke && !locker.inputMethod)
                    locker.take(method);
            }
            // Its prompt answered, or it stopped: the field goes back to the password.
            onStatusChanged: {
                if (locker.inputMethod === method && method.status !== "prompt") {
                    locker.inputMethod = null;
                    locker.clearInput();
                }
            }
        }
    }

    Timer {
        id: restartAuth
        interval: 400
        onTriggered: {
            if (locker.rift.phase === "locked")
                locker.startAuth();
        }
    }

    FileView {
        id: pamFile
        path: "/etc/pam.d/" + locker.pamService
        printErrors: false
    }

    // The service file appears after a rebuild; look again now and then until it does.
    Timer {
        interval: 30000
        repeat: true
        running: !locker.pamReady
        onTriggered: pamFile.reload()
    }

    WlSessionLock {
        id: sessionLock
        onSecureChanged: {
            if (secure)
                locker.enterLocked();
        }

        WlSessionLockSurface {
            id: surface
            readonly property bool main: screen?.name === locker.mainOutput
            color: "black"

            Loader {
                anchors.fill: parent
                active: surface.main
                sourceComponent: Item {
                    Image {
                        id: frozen
                        source: locker.snapshotUrl
                        visible: false
                        mipmap: true
                        smooth: true
                        cache: false
                    }
                    RiftView {
                        anchors.fill: parent
                        rift: locker.rift
                        snapshotSource: frozen
                    }
                    LockUI {
                        rift: locker.rift
                        locker: locker
                        info: locker.info
                        appear: locker.rift.lockAppear
                        Component.onCompleted: focusInput()
                    }
                }
            }

            Loader {
                anchors.fill: parent
                active: !surface.main
                sourceComponent: LockFog {
                    rift: locker.rift
                }
            }
        }
    }

    // Idle: lock after lock.idle.ac / lock.idle.battery seconds without input (0: never).
    IdleMonitor {
        timeout: UPower.onBattery ? (locker.options.idle?.battery ?? 0) : (locker.options.idle?.ac ?? 0)
        enabled: timeout > 0 && locker.pamReady && locker.enabled
        onIsIdleChanged: {
            if (isIdle)
                locker.lockRequested({
                    reason: "idle"
                });
        }
    }

    // Holds sleep back until the screen is locked (lock.beforeSleep).
    Process {
        id: inhibitor
        readonly property bool wanted: (locker.options.beforeSleep ?? true) && locker.pamReady && locker.enabled
        running: wanted
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=shatterlock", "--why=Locking the screen first", "sleep", "infinity"]
    }

    Process {
        running: true
        command: ["sh", "-c", 'busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager GetSessionByPID u "$1" 2>/dev/null || busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager GetSession s "$(loginctl show-user "$USER" -p Display --value)"', "sh", String(Quickshell.processId)]
        stdout: StdioCollector {
            onStreamFinished: locker.sessionPath = (/"([^"]+)"/.exec(text) ?? [])[1] ?? ""
        }
    }

    Process {
        id: logind
        running: locker.sessionPath !== ""
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: line => locker.onLogind(line)
        }
        onExited: retryLogind.start()
    }

    Timer {
        id: retryLogind
        interval: 2000
        onTriggered: logind.running = true
    }
}
