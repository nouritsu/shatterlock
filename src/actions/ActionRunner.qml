import QtQuick
import Quickshell
import Quickshell.Io

// Runs an action's command, and probes which logind actions this machine supports (for actions
// with "requires": "CanHibernate" and the like).
Scope {
    id: runner

    // logind method → whether it answered "yes" or "challenge"
    property var capabilities: ({})
    readonly property bool busy: proc.running || dryRun.running

    property string current: ""

    signal finished(string id, bool ok, string message)

    function available(def) {
        return !def?.requires || capabilities[def.requires] === true;
    }

    // Ask logind about every method named in `requires`; results apply from the next open.
    function probe(actionDefs) {
        if (prober.running)
            return;
        const methods = [...new Set(Object.values(actionDefs ?? {}).map(d => d.requires).filter(m => /^Can[A-Za-z]+$/.test(m ?? "")))];
        if (methods.length === 0)
            return;
        prober.command = ["sh", "-c", 'for m in "$@"; do printf "%s " "$m"; busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$m" 2>/dev/null || echo na; done', "probe", ...methods];
        prober.running = true;
    }

    function run(def, isDryRun) {
        if (busy)
            return false;
        current = def.id;
        if (isDryRun) {
            console.info(`shatterlock: dry run: would run ${JSON.stringify(def.command)} for "${def.id}"`);
            dryRun.restart();
            return true;
        }
        console.info(`shatterlock: running ${JSON.stringify(def.command)} for "${def.id}"`);
        // Through sh so that a missing program still reports back as a failed exit.
        proc.command = ["sh", "-c", 'exec "$@"', "shatterlock-action", ...def.command];
        proc.running = true;
        return true;
    }

    Process {
        id: proc
        stderr: StdioCollector {
            id: errors
        }
        onExited: code => {
            const message = code === 0 ? "" : (errors.text.trim().split("\n").pop() || `exited with status ${code}`);
            if (code !== 0)
                console.warn(`shatterlock: "${runner.current}" failed: ${message}`);
            runner.finished(runner.current, code === 0, message);
        }
    }

    Timer {
        id: dryRun
        interval: 500
        onTriggered: runner.finished(runner.current, true, "")
    }

    Process {
        id: prober
        stdout: SplitParser {
            onRead: line => {
                const [method, , answer] = line.trim().split(/\s+/);
                const value = (answer ?? "").replace(/"/g, "");
                const caps = Object.assign({}, runner.capabilities);
                caps[method] = value === "yes" || value === "challenge";
                runner.capabilities = caps;
            }
        }
    }
}
