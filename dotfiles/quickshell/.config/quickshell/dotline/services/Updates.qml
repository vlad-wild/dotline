pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — pending-update counts for the bar glyph, from
// scripts/update-check (see that script for what each count means and
// why jq is a safe hard dependency there). Polled, not event-driven: none
// of checkupdates/paru/flatpak/fwupdmgr has a "tell me when something
// changes" signal, so this is the same Timer+Process+StdioCollector shape
// already used by PowerProfile.qml, just on a much longer interval —
// these counts don't need to be fresher than ~20 minutes, and checkupdates/
// paru -Qua both do real network/disk work worth not repeating often.
Singleton {
    id: root

    property int pacman: 0
    property int aur: 0
    property int flatpak: 0
    property int firmware: 0
    property int total: 0

    Timer {
        interval: 20 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    // scripts/update-check isn't on PATH (link_bin only covers the small
    // set of commands niri binds need by name — this one is only ever
    // called from here), so it's run by full path like Apps.qml/Phone.qml
    // already do via DOTLINE_ROOT.
    Process {
        id: proc
        command: [Quickshell.env("DOTLINE_ROOT") + "/scripts/update-check"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed
                try {
                    parsed = JSON.parse(text)
                } catch (e) {
                    console.warn("Updates: update-check didn't print valid JSON, keeping previous counts:", e)
                    return
                }
                root.pacman = parsed.pacman ?? 0
                root.aur = parsed.aur ?? 0
                root.flatpak = parsed.flatpak ?? 0
                root.firmware = parsed.firmware ?? 0
                root.total = parsed.total ?? 0
            }
        }
    }

    function refresh(): void { proc.running = true }

    // Launched visibly in kitty (per the plan: "видны вопросы pacman"),
    // same pattern as Launcher.qml's `$command` mode. A snapshot happens
    // inside update.sh itself before touching packages, not here.
    function updateAll(): void {
        const script = Quickshell.env("DOTLINE_ROOT") + "/update.sh"
        Quickshell.execDetached(["kitty", "sh", "-c", script + "; echo; read -p 'Нажмите Enter для выхода…'"])
    }
}
