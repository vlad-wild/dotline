pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — current power-profiles-daemon profile, for the bar glyph.
// Polling `powerprofilesctl get` (plain one-line text, not the undocumented
// `list` format scripts/power deliberately avoids parsing) — there's no
// Quickshell.Services.PowerProfiles module (checked the real module list
// used throughout this session: Mpris/Notifications/Pam/Pipewire/Polkit/
// SystemTray/UPower/Greetd — power-profiles-daemon isn't among them).
Singleton {
    id: root

    property string profile: "balanced"   // "power-saver" | "balanced" | "performance"

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Process {
        id: proc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                if (p.length > 0) root.profile = p
            }
        }
    }

    function cycle() {
        Quickshell.execDetached(["dotline-power", "cycle"])
    }
    function set(p) {
        Quickshell.execDetached(["dotline-power", "set", p])
    }
}
