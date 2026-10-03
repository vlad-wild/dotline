pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — monitor list for the settings window's "Экраны" page.
// One-shot query (refresh()), not continuously polled: monitors don't
// change while the settings window happens to be open, same reasoning as
// Settings.qml's "about" info (osInfo/kernelInfo/niriInfo).
//
// `niri msg --json outputs` field names (name/make/model/current_mode/
// modes[]/logical.scale) are confirmed from niri's own IPC docs; the
// exact top-level shape (plain array vs. a map keyed by output name)
// could NOT be confirmed the same way (niri-wm.github.io/niri/IPC.html
// doesn't show a worked example, and the niri_ipc docs.rs page doesn't
// either) — _normalize() below accepts either shape rather than betting
// on one. `on`/`off` as niri_ipc::OutputAction variants are confirmed;
// anything beyond that (Scale/Mode/Transform/Position actions) is NOT
// exposed here on purpose — their exact CLI argument syntax isn't
// confirmed, and this rice doesn't guess at commands that touch a
// monitor's actual signal.
Singleton {
    id: root

    property var outputs: []

    function refresh(): void { proc.running = true }

    Process {
        id: proc
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed
                try {
                    parsed = JSON.parse(text)
                } catch (e) {
                    console.warn("Displays: niri msg --json outputs didn't print valid JSON:", e)
                    return
                }
                root.outputs = root._normalize(parsed)
            }
        }
    }

    function _normalize(parsed) {
        const raw = Array.isArray(parsed) ? parsed : Object.values(parsed)
        return raw.map(o => {
            const mode = (o.current_mode !== null && o.current_mode !== undefined && o.modes)
                ? o.modes[o.current_mode] : null
            return {
                name: o.name ?? "?",
                label: [o.make, o.model].filter(s => s).join(" ") || o.name,
                enabled: !!o.logical,
                resolution: mode ? (mode.width + "×" + mode.height) : "",
                refresh: mode ? Math.round(mode.refresh_rate / 1000) + " Гц" : "",
                scale: o.logical ? o.logical.scale : null,
            }
        })
    }

    function setEnabled(name, on) {
        Quickshell.execDetached(["niri", "msg", "output", name, on ? "on" : "off"])
    }
}
