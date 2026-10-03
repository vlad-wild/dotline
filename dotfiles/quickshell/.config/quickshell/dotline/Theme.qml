pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — the one place every other QML file gets colour from.
//
// Reads ~/.local/state/dotline/palette.json, written by
// scripts/palette-post (see lib/palette.sh) whenever the wallpaper changes,
// and re-reads it live via FileView's watchChanges. Before that file has
// ever been written (fresh install, before the first `dotline-wallpaper
// set`), the properties below keep their default values — the same
// monochrome-dark-plus-red-accent fallback used by faceauth-ui's own
// style.rs and by every static dotfile placeholder in this repo, so a
// fresh install looks consistent even before any wallpaper has been set.
//
// NOT runtime-verified against a real Quickshell yet (written on Windows,
// no Wayland/Quickshell available) — check this loads without errors on
// the very first `qs -c dotline` on the laptop.
Singleton {
    id: root

    readonly property string mode: _parsed.mode ?? "dark"
    readonly property bool isDark: mode !== "light"

    property color surface: "#1b1b1d"
    property color surfaceHigh: "#2e2e30"
    // Called `ink`, not `on`: `on` is a contextual QML keyword (`Behavior
    // on <property> { }`), and `Behavior on on { }` below would have been
    // asking for trouble in the one file every other file depends on. The
    // palette.json wire format still uses "on" (faceauth-ui's own
    // style.rs reads that key too) — _applyText() below is the one place
    // that mapping happens.
    property color ink: "#f2f2f0"
    property color muted: "#bdbdbd"
    property color accent: "#d71921"
    property color outline: "#3a3a3d"

    // Layout tokens shared across the shell (see plan: "niri: скругления 20,
    // отступы 16"). Not palette-driven, but kept here so every QML file
    // pulls both colour and layout from the one Theme singleton.
    readonly property int radius: 20
    readonly property int gap: 16
    readonly property int barHeight: 44

    readonly property string fontDot: "Matrix Sans Print"
    readonly property string fontUi: "Space Grotesk"
    readonly property string fontMono: "JetBrainsMono Nerd Font"

    Behavior on surface { ColorAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Behavior on surfaceHigh { ColorAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Behavior on ink { ColorAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Behavior on muted { ColorAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Behavior on accent { ColorAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Behavior on outline { ColorAnimation { duration: 900; easing.type: Easing.OutCubic } }

    property var _parsed: ({})

    // Quickshell.env()'s exact signature (whether a 2-arg default is
    // supported) isn't something to guess blind, so the fallback is done
    // by hand instead of relying on that.
    readonly property string _stateHome: {
        const v = Quickshell.env("XDG_STATE_HOME")
        return (v && v.length > 0) ? v : (Quickshell.env("HOME") + "/.local/state")
    }

    FileView {
        id: paletteFile
        path: root._stateHome + "/dotline/palette.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyText(text())
        onLoadFailed: (error) => {
            console.warn("Theme: no palette.json yet (" + error + ") — using the built-in monochrome/red default.")
        }
    }

    // Mirrors lib/palette.sh's own state file (scripts/theme oled on|off is
    // the one place that writes it) — watched, not just read once, so a
    // toggle from the terminal and from quicksettings/QuickSettings.qml
    // both show up live in either place.
    readonly property bool oledEnabled: _oledFile.loaded && _oledFile.text().trim() === "on"
    FileView {
        id: _oledFile
        path: root._stateHome + "/dotline/oled"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: (error) => {} // absent = off, the default — nothing to warn about
    }

    function _applyText(text) {
        let parsed
        try {
            parsed = JSON.parse(text)
        } catch (e) {
            console.warn("Theme: palette.json is not valid JSON, keeping the previous colours:", e)
            return
        }
        const need = ["mode", "surface", "surfaceHigh", "on", "muted", "accent", "outline"]
        for (const k of need) {
            if (!(k in parsed)) {
                console.warn("Theme: palette.json is missing '" + k + "', keeping the previous colours.")
                return
            }
        }
        root._parsed = parsed
        root.surface = parsed.surface
        root.surfaceHigh = parsed.surfaceHigh
        root.ink = parsed.on
        root.muted = parsed.muted
        root.accent = parsed.accent
        root.outline = parsed.outline
    }
}
