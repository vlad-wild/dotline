pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — battery, for the bar. Wifi and volume used to live here
// too (polling nmcli/wpctl on a timer), but moved to NetworkService.qml
// and Audio.qml once it turned out Quickshell has real event-driven
// services for both (Quickshell.Networking, Quickshell.Services.Pipewire)
// — no reason to poll text output when a live D-Bus/Pipewire binding is
// right there. Battery stays here: sysfs is plain files, nothing to gain
// by going through Quickshell.Services.UPower instead.
Singleton {
    id: root

    property int batteryPercent: -1       // -1 = unknown (desktop, no battery)
    property bool batteryCharging: false

    // Edge-triggered low-battery toasts (plan §"Батарея и сон"): fire once
    // per threshold crossed while on battery, re-arm once charging starts
    // or the level climbs comfortably back above them — not on every
    // 5-second poll tick while already below a threshold. Below 5%,
    // systemd-sleep.conf.d's own suspend-then-hibernate already hibernates
    // regardless of this (see system/etc/systemd/sleep.conf.d), so this is
    // just the heads-up, not the safety net itself.
    property bool warned20: false
    property bool warned10: false
    property bool warned5: false

    onBatteryPercentChanged: _checkBatteryWarnings()
    onBatteryChargingChanged: _checkBatteryWarnings()

    function _checkBatteryWarnings() {
        if (batteryPercent < 0) return
        if (batteryCharging || batteryPercent > 25) {
            warned20 = false; warned10 = false; warned5 = false
            return
        }
        if (batteryPercent <= 5 && !warned5) {
            warned5 = true
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "dotline",
                "Батарея 5%", "Скоро гибернация — подключите зарядку"])
        } else if (batteryPercent <= 10 && !warned10) {
            warned10 = true
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "dotline",
                "Батарея 10%", "Подключите зарядку"])
        } else if (batteryPercent <= 20 && !warned20) {
            warned20 = true
            Quickshell.execDetached(["notify-send", "-a", "dotline", "Батарея 20%", ""])
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function refresh() {
        // sysfs attribute files don't reliably fire inotify events on
        // change (they're regenerated on read, not "modified" the way
        // watchChanges expects), so this polls both on a timer instead of
        // trusting FileView's own watcher for these two.
        batCapacity.reload()
        batStatus.reload()
    }

    FileView {
        id: batCapacity
        path: "/sys/class/power_supply/BAT0/capacity"
        onLoaded: {
            const n = parseInt(text().trim(), 10)
            if (!isNaN(n)) root.batteryPercent = n
        }
        onLoadFailed: (error) => { root.batteryPercent = -1 }
    }
    FileView {
        id: batStatus
        path: "/sys/class/power_supply/BAT0/status"
        onLoaded: {
            root.batteryCharging = text().trim() === "Charging"
        }
    }
}
