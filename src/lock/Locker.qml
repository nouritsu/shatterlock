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
// rift's output shows the same rift with the password field, the others dark fog. Unlocking takes
// PAM (password, or fingerprint where its service exists) or logind's Unlock.
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
    readonly property string fingerprintService: options.fingerprintService ?? "shatterlock-fingerprint"
    readonly property bool pamReady: pamFile.loaded
    readonly property bool fingerprintReady: fingerprintFile.loaded

    // Locked for show only: the overlay plays the lock, PAM runs, but the session stays unlocked.
    property bool preview: false
    readonly property bool sessionLocked: sessionLock.locked

    // Password field
    property string prompt: "Password"
    property string message: ""
    property bool messageIsError: false
    property bool busy: false
    property string pending: "" // typed before PAM asked for it

    // logind
    property string sessionPath: ""
    property bool sleeping: false

    readonly property LockInfo info: LockInfo {
        active: locker.rift.lockPhase
    }

    signal lockRequested(var opts)  // idle, logind, sleep: the shell decides how to open the rift
    signal clearInput

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
        prompt = fingerprintReady && !preview ? "Password, or touch the reader" : "Password";
        message = "";
        messageIsError = false;
        busy = false;
        pending = "";
        clearInput();
    }

    // The rift is sealed and its snapshot copied: take the session.
    function sealed(url) {
        snapshotUrl = url;
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

    function startAuth() {
        if (!pam.active && !pam.start()) {
            busy = false;
            pending = "";
            message = `Can't check passwords: PAM service "${pamService}" didn't start`;
            messageIsError = true;
        }
        if (fingerprintReady && !preview && !fingerprint.active)
            fingerprint.start();
    }

    function submit(text) {
        if (rift.phase !== "locked" || text === "" || busy)
            return;
        busy = true;
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
        message = why;
        messageIsError = true;
        clearInput();
        rift.quake();
        restartAuth.restart();
    }

    // Authenticated: the fog clears from the rift (on the lock surface while locked), then
    // release() gives the session back.
    function unlock() {
        if (!rift.lockPhase || rift.phase === "unlocking")
            return;
        if (pam.active)
            pam.abort();
        if (fingerprint.active)
            fingerprint.abort();
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

    PamContext {
        id: fingerprint
        config: locker.fingerprintService
        onPamMessage: {
            if (message && !responseRequired) {
                locker.message = message;
                locker.messageIsError = messageIsError;
            }
        }
        onCompleted: result => {
            if (result === PamResult.Success)
                locker.unlock();
            else if (locker.rift.phase === "locked")
                retryFingerprint.restart();
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

    Timer {
        id: retryFingerprint
        interval: 1500
        onTriggered: {
            if (locker.rift.phase === "locked" && !fingerprint.active)
                fingerprint.start();
        }
    }

    FileView {
        id: pamFile
        path: "/etc/pam.d/" + locker.pamService
        printErrors: false
    }

    FileView {
        id: fingerprintFile
        path: "/etc/pam.d/" + locker.fingerprintService
        printErrors: false
    }

    // The service files appear after a rebuild; look again now and then until they do.
    Timer {
        interval: 30000
        repeat: true
        running: !locker.pamReady || !locker.fingerprintReady
        onTriggered: {
            if (!locker.pamReady)
                pamFile.reload();
            if (!locker.fingerprintReady)
                fingerprintFile.reload();
        }
    }

    WlSessionLock {
        id: sessionLock
        onSecureChanged: {
            if (secure)
                locker.enterLocked();
        }

        WlSessionLockSurface {
            id: surface
            readonly property bool main: screen?.name === locker.rift.screen?.name
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
