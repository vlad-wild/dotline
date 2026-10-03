import QtQuick
import Quickshell
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// The bar content: a Mac-style left side (system glyph + workspace/window)
// and a right side ending in the clock, meant to sit inside a PanelWindow
// from shell.qml. This file is just the row of pills — the window/anchors
// belong to whatever wraps it, so the same Bar can be reused per output.
Item {
    id: root

    required property string output

    implicitHeight: Dotline.Theme.barHeight

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Dotline.Theme.gap * 0.6

        SystemMenu { anchors.verticalCenter: parent.verticalCenter }

        Components.Pill {
            spacing: 10
            WorkspaceDots { output: root.output; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 1; height: 18; color: Dotline.Theme.outline; anchors.verticalCenter: parent.verticalCenter }
            Row {
                spacing: 9
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: 7; height: 7; radius: 3.5
                    color: Dotline.Theme.accent
                    visible: !!Services.Niri.focusedWindow
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: Services.Niri.focusedWindow ? Services.Niri.focusedTitle : "Пустой стол"
                    color: Services.Niri.focusedWindow ? Dotline.Theme.ink : Dotline.Theme.muted
                    font.family: Dotline.Theme.fontUi
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 360)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Components.Pill {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        // Power profile: a dot (muted = power-saver, ink = balanced, accent
        // = performance), click cycles via scripts/power — same action
        // Fn+F is meant to trigger once that key's real code is confirmed
        // on the laptop (see config.kdl's Mod+Ctrl+P fallback bind).
        Rectangle {
            width: 9; height: 9; radius: 4.5
            anchors.verticalCenter: parent.verticalCenter
            color: Services.PowerProfile.profile === "performance" ? Dotline.Theme.accent
                 : Services.PowerProfile.profile === "power-saver" ? Dotline.Theme.muted
                 : Dotline.Theme.ink
            Behavior on color { ColorAnimation { duration: 250 } }
            TapHandler { onTapped: Services.PowerProfile.cycle() }
        }

        // Caffeine ("не засыпать" — Mod+Ctrl+C): accent while active, plain
        // dot like the wifi/phone ones rather than a one-off pictogram.
        // Lasts until shutdown/reboot by design — see services/Caffeine.qml.
        Rectangle {
            width: 9; height: 9; radius: 4.5
            anchors.verticalCenter: parent.verticalCenter
            color: Services.Caffeine.enabled ? Dotline.Theme.accent : Dotline.Theme.muted
            Behavior on color { ColorAnimation { duration: 250 } }
            TapHandler { onTapped: Services.Caffeine.toggle() }
        }

        // Не беспокоить (Mod+Shift+N): accent dot, same shape as caffeine's.
        Rectangle {
            width: 9; height: 9; radius: 4.5
            anchors.verticalCenter: parent.verticalCenter
            color: Services.DoNotDisturb.enabled ? Dotline.Theme.accent : Dotline.Theme.muted
            Behavior on color { ColorAnimation { duration: 250 } }
            TapHandler { onTapped: Services.DoNotDisturb.toggle() }
        }

        // Режим работы (Mod+Ctrl+M циклит): видно, только когда не
        // "обычный" — в "обычном" это просто шум в баре.
        Text {
            visible: Services.Modes.current !== "normal"
            anchors.verticalCenter: parent.verticalCenter
            text: {
                switch (Services.Modes.current) {
                    case "game": return "ИГРА"
                    case "focus": return "ФОКУС"
                    case "presentation": return "ПРЕЗЕНТАЦИЯ"
                    default: return ""
                }
            }
            color: Dotline.Theme.accent
            font.family: Dotline.Theme.fontDot
            font.pixelSize: 12
            font.weight: Font.ExtraBold
            TapHandler { onTapped: Services.Modes.set("normal") }
        }

        // Помодоро: точки прогресса (не буквально "кольцо" из плана — тот
        // же компромисс, что уже был у микшера/телефона: не придумывать
        // форму виджета, которой нет готового компонента под рукой) +
        // оставшееся время. Клик — стоп.
        Row {
            visible: Services.Pomodoro.running
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            Components.DotLevel {
                anchors.verticalCenter: parent.verticalCenter
                count: 5
                filled: Math.max(1, Math.round(Services.Pomodoro.progress * 5))
                color: Services.Pomodoro.isBreak ? Dotline.Theme.ink : Dotline.Theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const m = Math.floor(Services.Pomodoro.remaining / 60)
                    const s = Services.Pomodoro.remaining % 60
                    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
                }
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontDot
                font.pixelSize: 13
            }
            TapHandler { onTapped: Services.Pomodoro.stop() }
        }

        // Media (MPRIS): a small equalizer-ish glyph (accent while
        // actually playing, muted otherwise/paused) plus the track title,
        // elided — a real scrolling marquee is future work, see
        // docs/media.md. Click opens media/MediaCard.qml.
        Row {
            visible: Services.Media.hasPlayer
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter

            Row {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [6, 12, 8]
                    delegate: Rectangle {
                        required property int modelData
                        width: 3; radius: 1.5
                        height: modelData
                        color: Services.Media.playing ? Dotline.Theme.accent : Dotline.Theme.muted
                        Behavior on color { ColorAnimation { duration: 250 } }
                        anchors.bottom: parent.bottom
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Services.Media.title || Services.Media.identity
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 13
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 160)
            }
            TapHandler {
                onTapped: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "media", "toggle"])
            }
        }

        // Third-party tray icons (apps with no native Quickshell service).
        TrayRow { anchors.verticalCenter: parent.verticalCenter }

        // Keyboard layout (EN/RU). Click cycles the same as the xkb
        // toggle bound in config.kdl, for when the physical key is awkward.
        Text {
            visible: Services.Niri.layoutNames.length > 1
            anchors.verticalCenter: parent.verticalCenter
            text: Services.Niri.layoutShort
            color: Dotline.Theme.ink
            font.family: Dotline.Theme.fontDot
            font.pixelSize: 14
            font.weight: Font.ExtraBold
            TapHandler {
                onTapped: Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"])
            }
        }

        // Phone (KDE Connect): a plain dot, same reasoning as the wifi dot
        // below — accent while a paired phone is reachable, muted
        // otherwise (including "no phone known at all"). Click opens
        // PhoneMenu.qml via the same IPC pattern as quicksettings/lock.
        Rectangle {
            width: 9; height: 9; radius: 4.5
            anchors.verticalCenter: parent.verticalCenter
            color: Services.Phone.connected ? Dotline.Theme.accent : Dotline.Theme.muted
            Behavior on color { ColorAnimation { duration: 250 } }
            TapHandler {
                onTapped: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "phone", "toggle"])
            }
        }

        // Update counter: only takes up space when there's something to
        // show (plan: "счётчик... видим только когда > 0"). Opens
        // updates/UpdatesCard.qml, same IPC shape as phone/media.
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: Services.Updates.total > 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Services.Updates.total
                color: Dotline.Theme.accent
                font.family: Dotline.Theme.fontDot
                font.pixelSize: 14
                font.weight: Font.ExtraBold
            }
            TapHandler {
                onTapped: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "updates", "toggle"])
            }
        }

        // Wifi: a plain dot rather than an icon glyph — see the design
        // note in the plan (avoids guessing a Nerd Font codepoint blind).
        // Opens quick settings on click (see QuickSettings.qml).
        Rectangle {
            id: wifiDot
            width: 9; height: 9; radius: 4.5
            anchors.verticalCenter: parent.verticalCenter
            color: Services.NetworkService.activeNetwork ? Dotline.Theme.ink : Dotline.Theme.muted
            Behavior on color { ColorAnimation { duration: 250 } }
            TapHandler {
                onTapped: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "quicksettings", "toggle"])
            }
        }
        Components.DotLevel {
            anchors.verticalCenter: parent.verticalCenter
            filled: Services.Audio.muted ? 0 : Math.round(Services.Audio.volume * 5)
        }
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: Services.Status.batteryPercent >= 0
            Text {
                text: Services.Status.batteryPercent + "%"
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontDot
                font.pixelSize: 16
                font.weight: Font.ExtraBold
                anchors.verticalCenter: parent.verticalCenter
            }
            Components.DotLevel {
                anchors.verticalCenter: parent.verticalCenter
                filled: Math.round(Services.Status.batteryPercent / 20)
                color: Services.Status.batteryCharging ? Dotline.Theme.accent : Dotline.Theme.ink
            }
        }
        Rectangle { width: 1; height: 18; color: Dotline.Theme.outline; anchors.verticalCenter: parent.verticalCenter }
        Text {
            id: clock
            text: Qt.formatDateTime(_now, "hh:mm")
            color: Dotline.Theme.ink
            font.family: Dotline.Theme.fontDot
            font.pixelSize: 21
            font.weight: Font.ExtraBold
            anchors.verticalCenter: parent.verticalCenter

            property var _now: new Date()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: parent._now = new Date() }

            TapHandler {
                onTapped: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "lock", "lock"])
            }
        }
    }
}
