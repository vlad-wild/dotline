import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import "bar" as Bar
import "notifications" as Notifications
import "launcher" as LauncherNs
import "osd" as OsdNs
import "lock" as LockNs
import "polkit" as PolkitNs
import "quicksettings" as QuickSettingsNs
import "keys" as KeysNs
import "settings" as SettingsNs
import "phone" as PhoneNs
import "media" as MediaNs
import "updates" as UpdatesNs
import "firstrun" as FirstRunNs
import "services" as Services

// dotline — Quickshell entry point (`qs -c dotline`, matching
// dotfiles/niri/config.kdl's spawn-at-startup).
//
// Checked against the real docs at quickshell.org (ShellRoot, PanelWindow,
// IpcHandler, Socket, WlSessionLock, PolkitAgent, NotificationServer,
// PamContext) after an earlier draft guessed several of these blind and
// got real things wrong in the process — a missing Quickshell.Wayland
// import (WlSessionLock/WlSessionLockSurface live there, not in the base
// Quickshell module, so this file wouldn't have parsed at all), IpcHandler
// functions needing explicit type annotations, Socket needing an explicit
// flush() after write(), and an unnecessary Variants wrapper around
// WlSessionLock's surface. Still genuinely unverified: `focusable: true`
// on the launcher's PanelWindow (real property per the docs, but whether
// it's enough on its own for a layer-shell surface to actually grab
// keyboard — that part still needs the laptop) and PolkitAgent actually
// completing a real pkexec flow end to end.
ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            margins {
                top: 12
                left: 16
                right: 16
            }
            implicitHeight: 44
            color: "transparent"

            Bar.Bar {
                anchors.fill: parent
                output: barWindow.screen.name
            }

            // Caffeine (Mod+Ctrl+C / Bar.qml's cup glyph): wraps
            // idle-inhibit-unstable-v1 (confirmed from the real
            // IdleInhibitor docs — needs a `window`, so one per screen's
            // own bar window, same as everything else in this Variants).
            IdleInhibitor {
                window: barWindow
                enabled: Services.Caffeine.enabled
            }
        }
    }

    PanelWindow {
        id: notifyWindow
        anchors {
            top: true
            right: true
        }
        // Sized to the toasts actually showing (see NotificationPopup's
        // own implicitWidth/Height), not a fixed box — PanelWindow's docs
        // don't list an input-mask/click-through property, so the fix for
        // "empty transparent area blocks clicks" is keeping the window
        // itself small, the same move made for the OSD window below.
        implicitWidth: notifications.implicitWidth
        implicitHeight: notifications.implicitHeight
        color: "transparent"

        Notifications.NotificationPopup {
            id: notifications
            anchors.fill: parent
        }
    }

    PanelWindow {
        id: launcherWindow
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        focusable: true
        visible: launcher.open

        LauncherNs.Launcher {
            id: launcher
            anchors.fill: parent
        }

        IpcHandler {
            target: "launcher"
            function toggle(): void { launcher.toggle() }
            function open(): void { launcher.show() }
            function close(): void { launcher.hide() }
        }
    }

    PanelWindow {
        id: osdWindow
        // Only anchored to the bottom edge (not left/right/top): per the
        // wlr-layer-shell protocol this centers the surface horizontally
        // and sizes it to implicitWidth/implicitHeight, instead of
        // covering the whole screen — sidesteps the notification window's
        // click-through problem entirely for this one, rather than
        // guessing at an input-mask property that PanelWindow's own docs
        // don't list.
        anchors { bottom: true }
        margins { bottom: 48 }
        implicitWidth: 320
        implicitHeight: 64
        color: "transparent"

        OsdNs.Osd {
            id: osd
            anchors.fill: parent
        }

        IpcHandler {
            target: "osd"
            function show(kind: string, percent: string, muted: string): void { osd.flash(kind, percent, muted) }
        }
    }

    // The actual Wayland session lock. Verified against the real
    // Quickshell.Wayland docs: `locked` is the control property, and
    // `surface` is a default Component WlSessionLock instantiates itself
    // once per screen — no Variants wrapper (an earlier draft of this
    // file had one, which the docs say isn't how this works). `secure`
    // confirms the compositor actually covered every screen; logged for
    // now rather than given its own UI state.
    WlSessionLock {
        id: sessionLock
        locked: false

        onSecureChanged: {
            if (locked) console.log("Lock: secure =", secure, "(false until every screen is actually covered)")
        }

        WlSessionLockSurface {
            LockNs.Lock {
                anchors.fill: parent
                onUnlocked: sessionLock.locked = false
            }
        }

        IpcHandler {
            target: "lock"
            function lock(): void { sessionLock.locked = true }
            function unlock(): void { sessionLock.locked = false }
        }
    }

    // Registers itself as the session's polkit authentication agent on
    // creation (org.freedesktop.PolicyKit1.AuthenticationAgent) — see
    // `isRegistered` below for whether that actually succeeded.
    PolkitAgent {
        id: polkitAgent
        Component.onCompleted: {
            if (!isRegistered) {
                console.warn("Polkit: agent failed to register — is another " +
                    "one (polkit-gnome, polkit-kde-agent, …) already running? " +
                    "Only one agent may hold the session at a time.")
            }
        }
    }

    PanelWindow {
        id: polkitWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: polkitAgent.isActive

        PolkitNs.PolkitDialog {
            anchors.fill: parent
            agent: polkitAgent
        }
    }

    PanelWindow {
        id: quickSettingsWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: quickSettings.open

        QuickSettingsNs.QuickSettings {
            id: quickSettings
            anchors.fill: parent
        }

        IpcHandler {
            target: "quicksettings"
            function toggle(): void { quickSettings.toggle() }
            function open(): void { quickSettings.show() }
            function close(): void { quickSettings.hide() }
        }
    }

    PanelWindow {
        id: keysWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: keysSheet.open

        KeysNs.KeysCheatSheet {
            id: keysSheet
            anchors.fill: parent
        }

        IpcHandler {
            target: "keys"
            function toggle(): void { keysSheet.toggle() }
            function open(): void { keysSheet.show() }
            function close(): void { keysSheet.hide() }
        }
    }

    PanelWindow {
        id: settingsWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: settings.open

        SettingsNs.Settings {
            id: settings
            anchors.fill: parent
        }

        IpcHandler {
            target: "settings"
            function toggle(): void { settings.toggle() }
            function open(): void { settings.show() }
            function close(): void { settings.hide() }
        }
    }

    PanelWindow {
        id: phoneWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: phoneMenu.open

        PhoneNs.PhoneMenu {
            id: phoneMenu
            anchors.fill: parent
        }

        IpcHandler {
            target: "phone"
            function toggle(): void { phoneMenu.toggle() }
            function open(): void { phoneMenu.show() }
            function close(): void { phoneMenu.hide() }
        }
    }

    PanelWindow {
        id: mediaWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: mediaCard.open

        MediaNs.MediaCard {
            id: mediaCard
            anchors.fill: parent
        }

        IpcHandler {
            target: "media"
            function toggle(): void { mediaCard.toggle() }
            function open(): void { mediaCard.show() }
            function close(): void { mediaCard.hide() }
        }
    }

    PanelWindow {
        id: updatesWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: updatesCard.open

        UpdatesNs.UpdatesCard {
            id: updatesCard
            anchors.fill: parent
        }

        IpcHandler {
            target: "updates"
            function toggle(): void { updatesCard.toggle() }
            function open(): void { updatesCard.show() }
            function close(): void { updatesCard.hide() }
        }
    }

    PanelWindow {
        id: firstRunWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        focusable: true
        visible: firstRunCard.open

        FirstRunNs.FirstRun {
            id: firstRunCard
            anchors.fill: parent
        }

        IpcHandler {
            target: "firstrun"
            function toggle(): void { firstRunCard.toggle() }
            function open(): void { firstRunCard.show() }
            function close(): void { firstRunCard.hide() }
        }
    }

    IpcHandler {
        target: "caffeine"
        function toggle(): void { Services.Caffeine.toggle() }
        function enable(): void { Services.Caffeine.enabled = true }
        function disable(): void { Services.Caffeine.enabled = false }
    }

    IpcHandler {
        target: "audio"
        function muteFocused(): void { Services.Audio.muteFocusedAppStream() }
    }

    IpcHandler {
        target: "dnd"
        function toggle(): void { Services.DoNotDisturb.toggle() }
        function enable(): void { Services.DoNotDisturb.enabled = true }
        function disable(): void { Services.DoNotDisturb.enabled = false }
    }

    IpcHandler {
        target: "modes"
        function cycle(): void { Services.Modes.cycle() }
        function set(mode: string): void { Services.Modes.set(mode) }
    }

    // Warning dim, 10s before the auto-lock below actually fires: a
    // second IdleMonitor with a shorter timeout, purely visual (no input
    // handling needed — any real activity resets *both* monitors' isIdle
    // at the Wayland protocol level before it ever reaches this window,
    // same reasoning as the OSD/notification windows' click-through
    // notes elsewhere in this file).
    readonly property int lockTimeoutSec: 300
    readonly property int dimWarningSec: 10

    PanelWindow {
        id: dimWindow
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: opacity > 0
        opacity: dimWarn.isIdle ? 0.85 : 0
        Behavior on opacity { NumberAnimation { duration: dimWarn.isIdle ? 2000 : 150 } }

        Rectangle { anchors.fill: parent; color: "black" }
    }

    IdleMonitor {
        id: dimWarn
        timeout: lockTimeoutSec - dimWarningSec
    }

    // Auto-lock after 5 minutes of inactivity — separate from the lid's
    // switch-events lock in config.kdl, which is instant regardless of
    // this timeout. Wraps ext-idle-notify-v1 (confirmed from the real
    // IdleMonitor docs); needs the compositor to support that protocol —
    // niri is expected to, not independently confirmed here. Caffeine
    // doesn't need separate handling here: idle-inhibit-unstable-v1 (what
    // the IdleInhibitor above wraps) is specifically meant to stop the
    // compositor from reporting idle at all while active, to every
    // ext-idle-notify-v1 client — this one included.
    IdleMonitor {
        timeout: lockTimeoutSec
        onIsIdleChanged: {
            if (isIdle) Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "lock", "lock"])
        }
    }
}
