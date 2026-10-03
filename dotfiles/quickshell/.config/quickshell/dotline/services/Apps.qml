pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — installed applications for the launcher, from
// scripts/list-apps (desktop-file scanning lives there, not here, same
// reasoning as the phone/wallpaper helpers: a plain script is much easier
// to get right and to test than hand-rolled .desktop parsing in QML).
Singleton {
    id: root

    property var list: []     // [{name, exec, icon, terminal}, ...]
    property bool loaded: false

    function refresh() {
        proc.running = true
    }

    function launch(app) {
        if (app.terminal) {
            Quickshell.execDetached(["kitty", "sh", "-c", app.exec])
        } else {
            Quickshell.execDetached(["sh", "-c", app.exec])
        }
    }

    // Our own script, not a system binary — invoked by full path via
    // DOTLINE_ROOT (set in dotfiles/environment, see Theme.qml's
    // similar use of Quickshell.env) rather than relying on ~/.local/bin,
    // since nothing else needs this one exposed on PATH.
    Process {
        id: proc
        command: [Quickshell.env("DOTLINE_ROOT") + "/scripts/list-apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.list = JSON.parse(text)
                    root.loaded = true
                } catch (e) {
                    console.warn("Apps: could not parse list-apps output:", e)
                }
            }
        }
    }

    Component.onCompleted: refresh()
}
