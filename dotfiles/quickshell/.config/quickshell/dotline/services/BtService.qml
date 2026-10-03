pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// dotline — Bluetooth for the bar glyph and the quick-settings panel.
// Verified against the real Quickshell.Bluetooth docs (same pass as
// Network.qml): Bluetooth/BluetoothAdapter/BluetoothDevice property and
// function names below are quoted from there. `devices` is an
// ObjectModel, read through `.values` (see Network.qml's own note on
// that — no .count/.get(i)).
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool powered: available && adapter.enabled
    readonly property bool scanning: available && adapter.discovering
    readonly property var devices: available ? [...adapter.devices.values] : []
    readonly property var connectedDevices: devices.filter(d => d.connected)
    // `name` is read-only on BluetoothAdapter (system-provided, not
    // renameable through this API — confirmed from Quickshell's own
    // docs) — settings page shows it, doesn't offer to edit it.
    readonly property string adapterName: available ? adapter.name : ""
    readonly property bool discoverable: available && adapter.discoverable

    function togglePower() {
        if (available) adapter.enabled = !adapter.enabled
    }
    function toggleScan() {
        if (available) adapter.discovering = !adapter.discovering
    }
    function toggleDiscoverable() {
        if (available) adapter.discoverable = !adapter.discoverable
    }

    // device: a BluetoothDevice from `devices` above.
    function pair(device) { device.pair() }
    function connectDevice(device) { device.connected = true }
    function disconnectDevice(device) { device.connected = false }
    function forget(device) { device.forget() }
}
