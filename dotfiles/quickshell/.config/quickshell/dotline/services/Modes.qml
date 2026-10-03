pragma Singleton
import QtQuick
import "." as Services

// dotline — "Режимы работы" (plan's Обычный/Игра/Фокус/Презентация).
// Honest scope: a mode is only as real as the levers it actually has to
// pull right now. Built on three that already exist (DoNotDisturb.qml,
// Caffeine.qml, PowerProfile.qml) — not yet wired because their own
// underlying feature doesn't exist in this rice yet: hiding the bar (no
// auto-hide built), disabling niri animations/blur (needs the config
// generator from 6a1, which isn't built), auto-detecting gamemode,
// excluding the calendar from DND (no calendar built), hiding desktop
// widgets (no widget layer built at all), screencast privacy window
// rules. See docs/modes.md for the exact list.
//
// A mode is a snapshot-and-apply: entering a non-"normal" mode from
// "normal" takes a snapshot of the few real levers, then applies the
// mode's overrides; going back to "normal" restores the snapshot instead
// of hardcoding what "normal" means (so whatever the user had set
// manually before switching modes comes back, not just some default).
Singleton {
    id: root

    readonly property var names: ["normal", "game", "focus", "presentation"]
    property string current: "normal"
    property var _snapshot: null

    function set(mode) {
        if (!names.includes(mode) || mode === current) return
        if (mode === "normal") {
            _restore()
        } else {
            if (current === "normal") _snapshot = {
                dnd: Services.DoNotDisturb.enabled,
                caffeine: Services.Caffeine.enabled,
                profile: Services.PowerProfile.profile,
            }
            _apply(mode)
        }
        current = mode
    }

    function toggle(mode) { set(current === mode ? "normal" : mode) }

    function cycle() {
        set(names[(names.indexOf(current) + 1) % names.length])
    }

    function _apply(mode) {
        if (mode === "game") {
            Services.DoNotDisturb.enabled = true
            Services.PowerProfile.set("performance")
        } else if (mode === "focus") {
            Services.DoNotDisturb.enabled = true
        } else if (mode === "presentation") {
            Services.DoNotDisturb.enabled = true
            Services.Caffeine.enabled = true
        }
    }

    function _restore() {
        if (!root._snapshot) return
        Services.DoNotDisturb.enabled = root._snapshot.dnd
        Services.Caffeine.enabled = root._snapshot.caffeine
        Services.PowerProfile.set(root._snapshot.profile)
        root._snapshot = null
    }
}
