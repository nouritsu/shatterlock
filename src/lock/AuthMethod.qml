pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// One way to unlock besides the password (lock.methods): a PAM service of its own that runs while
// the screen is locked, e.g. pam_u2f for a security key or pam_fprintd for a fingerprint reader.
// A success unlocks; anything else runs it again after retryMs (backing off while it keeps failing
// at once). It runs only while /etc/pam.d/<service> exists, and a "key" method with `detect` only
// while a FIDO key is plugged in: plugging one in starts it straight away.
//
// What it asks to have typed (a security key's PIN) never takes the password field on its own:
// a password typed into it would use up the key's PIN tries. Enter in the empty field hands the
// field over (Locker.wake), Escape hands it back (park: it stays off until Enter or a plugged key).
Scope {
    id: method

    required property string modelData // its id, in lock.methods
    required property var locker

    readonly property string name: modelData
    readonly property var def: locker.cfg.lock?.methodDefs?.[name] ?? ({})
    readonly property string kind: def.kind ?? "other"
    readonly property string service: def.service ?? ""
    readonly property string label: def.label || name
    readonly property string icon: def.icon || "lock"
    readonly property bool detects: kind === "key" && (def.detect ?? true)
    readonly property int retryMs: Math.max(250, def.retryMs ?? 1500)

    readonly property bool ready: serviceFile.loaded
    readonly property bool present: !detects || locker.keys.present
    property bool armed: def.start !== "enter" // start "enter": after Enter or a plugged key, once
    property bool parked: false
    readonly property bool wanted: locker.rift.phase === "locked" && ready && present && armed && !parked

    // "off"; "listening": running, nothing asked yet; "asking": it said something (touch the key,
    // place a finger); "prompt": it wants something typed.
    property string status: "off"
    property string message: ""
    property bool messageIsError: false
    // Waiting on the user. A plugged-in key (`detect`) waits for its touch as soon as pam_u2f
    // runs, whether or not it says so (its `cue` option).
    readonly property bool waiting: status === "asking" || status === "prompt" || (status === "listening" && detects)
    property bool userWoke: false // started by Enter in the empty field: its prompt takes the field

    property int delay: retryMs
    property real startedAt: 0
    property bool answered: false // something typed went to it this run
    property bool warned: false   // a PAM error was logged this lock

    signal succeeded
    signal prompting // status went "prompt"

    onWantedChanged: wanted ? start() : stop()
    Component.onCompleted: {
        if (wanted)
            start();
    }

    onPresentChanged: delay = retryMs

    // A key plugged in while locked: its method starts now, even one that waits for Enter.
    Connections {
        target: method.locker.keys
        function onPlugged() {
            if (method.detects && method.locker.rift.phase === "locked") {
                method.parked = false;
                method.armed = true;
            }
        }
    }

    // A new lock.
    function reset() {
        stop();
        armed = def.start !== "enter";
        parked = false;
        delay = retryMs;
        warned = false;
    }

    function start() {
        retry.stop();
        if (!wanted || pam.active)
            return;
        pam.config = service;
        startedAt = Date.now();
        answered = false;
        message = "";
        messageIsError = false;
        status = "listening";
        if (!pam.start() && status === "listening") // (a failed fork has already completed)
            again(true);
    }

    function stop() {
        retry.stop();
        if (pam.active)
            pam.abort();
        status = "off";
        message = "";
        messageIsError = false;
        userWoke = false;
    }

    // Ended without unlocking: again after a while, longer each time it fails at once.
    function again(quick) {
        status = "off";
        message = "";
        messageIsError = false;
        userWoke = false;
        delay = quick ? Math.min(30000, delay * 2) : retryMs;
        if (def.start === "enter")
            armed = false;
        if (wanted)
            retry.start();
    }

    // Enter in the empty field.
    function wake() {
        if (pam.active)
            return;
        userWoke = true;
        parked = false;
        armed = true;
        delay = retryMs;
        start();
        if (!pam.active) // (no key, no service: a prompt much later doesn't take the field)
            userWoke = false;
    }

    // Escape while it has the field.
    function park() {
        parked = true;
    }

    function respond(text) {
        if (status !== "prompt" || !pam.active)
            return;
        answered = true;
        message = "";
        status = "listening";
        pam.respond(text);
    }

    PamContext {
        id: pam
        onPamMessage: {
            const text = message.trim();
            if (responseRequired) {
                method.message = text;
                method.messageIsError = false;
                method.status = "prompt";
                method.prompting();
            } else if (text !== "") {
                method.message = text;
                method.messageIsError = messageIsError;
                method.status = "asking";
            }
        }
        onError: error => {
            if (!method.warned)
                console.warn(`shatterlock: lock method "${method.name}" (PAM service "${method.service}"): ${PamError.toString(error)}`);
            method.warned = true;
        }
        onCompleted: result => {
            // Failing within a second, or with an error, isn't the user's doing: a broken service,
            // a key it doesn't know.
            if (result === PamResult.Success) {
                method.status = "off";
                method.succeeded();
            } else {
                method.again(result === PamResult.Error || (!method.answered && Date.now() - method.startedAt < 1000));
            }
        }
    }

    Timer {
        id: retry
        interval: method.delay
        onTriggered: method.start()
    }

    FileView {
        id: serviceFile
        path: method.service ? "/etc/pam.d/" + method.service : ""
        printErrors: false
    }

    // The service file appears after a rebuild; look again now and then until it does.
    Timer {
        interval: 30000
        repeat: true
        running: !method.ready && method.service !== ""
        onTriggered: serviceFile.reload()
    }
}
