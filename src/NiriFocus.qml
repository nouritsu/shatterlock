pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The focused output's name, followed live from niri's event stream so opening the rift never waits
// on a lookup. Stays empty on other compositors.
Singleton {
    id: root

    property string focusedOutput: ""
    readonly property bool available: Quickshell.env("NIRI_SOCKET") !== null

    // workspace id → output name
    property var workspaces: ({})

    function handle(line) {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (ev.WorkspacesChanged) {
            const map = {};
            for (const ws of ev.WorkspacesChanged.workspaces) {
                map[ws.id] = ws.output;
                if (ws.is_focused && ws.output)
                    focusedOutput = ws.output;
            }
            workspaces = map;
        } else if (ev.WorkspaceActivated?.focused) {
            focusedOutput = workspaces[ev.WorkspaceActivated.id] ?? focusedOutput;
        }
    }

    Process {
        id: stream
        running: root.available
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        onExited: retry.start()
    }

    Timer {
        id: retry
        interval: 1000
        onTriggered: stream.running = true
    }
}
