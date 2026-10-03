pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — KDE Connect, via scripts/phone (see its own
// docstring and docs/phone.md for the D-Bus surface it wraps). No native
// Quickshell module for KDE Connect exists, so this follows the same
// "our own script, not hand-rolled protocol parsing in QML" reasoning as
// Apps.qml/list-apps — except this one is long-running (Process stays up
// for the whole session, not a one-shot JSON.parse), so it uses write()
// + a SplitParser on stdout instead of StdioCollector.
Singleton {
    id: root

    // {id, name, reachable, paired, pairRequested, pairRequestedByPeer,
    //  battery: {charge, charging} | null}
    property var devices: ({})           // id -> device object, see above
    readonly property var deviceList: Object.values(devices)
    readonly property var primaryDevice: deviceList.find(d => d.paired && d.reachable) ?? null
    readonly property bool connected: primaryDevice !== null
    readonly property var pendingPairRequests: deviceList.filter(d => d.pairRequestedByPeer)

    function _send(line) {
        if (!proc.running) return
        proc.write(line + "\n")
    }

    function ring(id) { _send(id ? ("ring " + id) : "ring") }
    function ping(id) { _send(id ? ("ping " + id) : "ping") }
    function share(path, id) { _send("share " + path + (id ? (" " + id) : "")) }
    function browse(id) { _send(id ? ("browse " + id) : "browse") }
    function requestPair(id) { _send("pair " + id) }
    function unpair(id) { _send("unpair " + id) }
    function acceptPair(id) { _send("accept " + id) }
    function rejectPair(id) { _send("reject " + id) }

    Process {
        id: proc
        command: [Quickshell.env("DOTLINE_ROOT") + "/scripts/phone"]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => {
                let msg
                try {
                    msg = JSON.parse(data)
                } catch (e) {
                    console.warn("Phone: bad line from dotline-phone:", data, e)
                    return
                }
                if (msg.event === "device") {
                    const next = Object.assign({}, root.devices)
                    next[msg.id] = msg
                    root.devices = next
                } else if (msg.event === "error") {
                    console.warn("Phone:", msg.message)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            console.warn("Phone: dotline-phone exited (" + exitCode + "), devices now unknown")
            root.devices = ({})
        }
    }
}
