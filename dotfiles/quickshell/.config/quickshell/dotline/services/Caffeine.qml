pragma Singleton
import QtQuick

// dotline — "don't sleep" (plan's "кофеин"). Deliberately not
// persisted anywhere: it's meant to last "until shutdown or reboot" (the
// plan's own words), not survive one — a plain in-memory property is
// exactly that, no state file needed. The actual inhibiting happens in
// shell.qml via Quickshell.Wayland's IdleInhibitor (wraps
// idle-inhibit-unstable-v1), attached to the bar's own PanelWindow; this
// singleton is just the shared on/off switch between the bar glyph, the
// Mod+Ctrl+C bind, and that inhibitor.
Singleton {
    id: root

    property bool enabled: false
    function toggle() { enabled = !enabled }
}
