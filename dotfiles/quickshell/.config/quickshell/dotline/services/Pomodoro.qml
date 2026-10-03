pragma Singleton
import QtQuick
import Quickshell
import "." as Services

// dotline — Pomodoro 25/5 (plan's "Помодоро"). Independent of Modes.qml's
// "focus" on purpose: the plan says focus mode starts it "по желанию"
// (optionally), not automatically — so this is its own toggle, not
// something Modes._apply() reaches for.
Singleton {
    id: root

    readonly property int focusSeconds: 25 * 60
    readonly property int breakSeconds: 5 * 60

    property bool running: false
    property bool isBreak: false
    property int remaining: focusSeconds
    property bool _dndBefore: false

    readonly property real progress: isBreak
        ? 1 - remaining / breakSeconds
        : 1 - remaining / focusSeconds

    function start() {
        if (running) return
        running = true
        isBreak = false
        remaining = focusSeconds
        _dndBefore = Services.DoNotDisturb.enabled
        Services.DoNotDisturb.enabled = true
        tick.restart()
    }

    function stop() {
        if (!running) return
        running = false
        tick.stop()
        Services.DoNotDisturb.enabled = _dndBefore
    }

    function toggle() { if (running) stop(); else start() }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.remaining -= 1
            if (root.remaining > 0) return
            if (!root.isBreak) {
                root.isBreak = true
                root.remaining = root.breakSeconds
                Services.DoNotDisturb.enabled = false
                Quickshell.execDetached(["notify-send", "-a", "dotline", "Помодоро", "Перерыв 5 минут"])
            } else {
                root.isBreak = false
                root.remaining = root.focusSeconds
                Services.DoNotDisturb.enabled = true
                Quickshell.execDetached(["notify-send", "-a", "dotline", "Помодоро", "Фокус 25 минут"])
            }
        }
    }
}
