pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// dotline — Wi-Fi for the bar glyph and the quick-settings panel.
// Verified against the real Quickshell.Networking docs: Networking
// (singleton)/NetworkDevice/Network/WifiNetwork property and function
// names below are quoted from there, not guessed — this is event-driven
// (NetworkManager's own D-Bus signals via Quickshell), unlike the old
// Status.qml which polled `nmcli` text output on a timer.
//
// ObjectModel (what `.devices`/`.networks` are) has no .count/.get(i) —
// only a plain-list `.values` property, confirmed from Quickshell's own
// ObjectModel docs after an earlier draft of this file assumed the
// count/get(i) shape instead.
Singleton {
    id: root

    readonly property var wifiDevice: {
        for (const d of Networking.devices.values) {
            if (d.type === DeviceType.Wifi) return d
        }
        return null
    }
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var networks: {
        if (!wifiDevice) return []
        const list = [...wifiDevice.networks.values]
        // Strongest signal first; the currently connected network always on top.
        list.sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
        return list
    }
    readonly property var activeNetwork: networks.find(n => n.connected) ?? null
    readonly property string activeName: activeNetwork ? activeNetwork.name : ""

    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled
    }

    // network: a WifiNetwork from `networks` above.
    function connectTo(network, password) {
        if (network.known || network.security === WifiSecurityType.Open) {
            network.connect()
        } else if (password && password.length > 0) {
            network.connectWithPsk(password)
        }
    }

    function forget(network) { network.forget() }
    function disconnectActive() { if (activeNetwork) activeNetwork.disconnect() }
}
