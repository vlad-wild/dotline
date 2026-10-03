pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — client for faceauthd's socket (see faceauth's
// src/daemon.rs, branch feat/faceauthd — this is the one Quickshell file
// in the whole rice whose wire protocol is pinned against real, tested
// code rather than guessed: SOCKET_PATH, the exact "op"/"event" field
// names and every value below are copied from that file and its own
// `#[test]`s, not reconstructed from the plan's earlier, less certain
// draft of this same protocol).
//
// What IS still a guess here, same caveat as the rest of this shell: the
// Quickshell `Socket` type itself (path/connected/parser/write()) — I
// don't have a real Quickshell to check its I/O API shape against.
//
// Usage: FaceAuth.verify("lock"), watch scanning/faceVisible/matched while
// it runs, react to success()/failed(outcome, reason).
Singleton {
    id: root

    readonly property string socketPath: "/run/faceauth/faceauthd.sock"

    property bool scanning: false
    property bool faceVisible: false
    property bool tooDark: false
    property real lastScore: 0
    property bool matched: false

    signal started()
    signal success()
    // outcome: "no_match" | "too_dark" | "skipped" | "cancelled" | "busy" | "error"
    signal failed(string outcome, string reason)

    property string _service: "lock"

    function verify(service) {
        if (root.scanning) return
        root._service = service || "lock"
        root.scanning = true
        root.faceVisible = false
        root.tooDark = false
        root.matched = false
        socket.connected = true
    }

    function cancel() {
        if (socket.connected) {
            socket.write(JSON.stringify({ op: "cancel" }) + "\n")
            socket.flush()
        }
    }

    Socket {
        id: socket
        path: root.socketPath

        onConnectedChanged: {
            if (connected) {
                // flush() is required — write() alone only queues the
                // data (confirmed from Quickshell's own Socket docs), an
                // earlier draft of this file was missing it and would
                // have sat connected without ever actually asking
                // faceauthd for anything.
                write(JSON.stringify({ op: "verify", service: root._service }) + "\n")
                flush()
            }
        }

        parser: SplitParser {
            onRead: (line) => root._handle(line)
        }
    }

    function _handle(line) {
        if (!line || !line.trim()) return
        let ev
        try {
            ev = JSON.parse(line)
        } catch (e) {
            console.warn("FaceAuth: bad line from faceauthd:", line)
            return
        }
        switch (ev.event) {
            case "started":
                root.started()
                break
            case "frame":
                root.faceVisible = ev.face
                root.tooDark = ev.dark
                root.matched = ev.matched
                if (ev.score !== undefined && ev.score !== null) root.lastScore = ev.score
                break
            case "result":
                root.scanning = false
                socket.connected = false
                if (ev.outcome === "success") {
                    root.success()
                } else {
                    root.failed(ev.outcome, ev.reason || "")
                }
                break
            // "status"/"history"/"calibration_progress"/"calibration" are for
            // the settings page (not built yet), not the lock screen path.
        }
    }
}
