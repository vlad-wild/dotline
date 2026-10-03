pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — live niri state for the bar and the overview.
//
// Design choice, not an oversight: `niri msg --json event-stream` is only
// used as a "something changed, go refresh" trigger — its own per-event
// JSON payload is never parsed. niri's event-stream schema (which fields a
// WorkspacesChanged/WindowsChanged/etc. event carries) is the part of its
// IPC I'm least sure of blind; the two one-shot queries below
// (`niri msg --json workspaces` / `windows`) are plain flat arrays and a
// much safer thing to depend on without a real niri to check against.
//
// NOT runtime-verified (no Wayland/niri available while writing this) —
// first real check: `qs -c dotline` on the laptop, watch the log for the
// "Niri: ..." warnings below, and confirm workspace dots/window title
// track reality when you switch or close windows.
Singleton {
    id: root

    property var workspaces: []          // [{id, idx, output, is_active, is_focused, is_urgent, active_window_id}, ...]
    property var windows: []             // [{id, title, app_id, workspace_id, is_focused, is_floating}, ...]
    property var layoutNames: []         // e.g. ["English (US)", "Russian"]
    property int layoutIdx: 0
    readonly property string layoutShort: {
        // "EN"/"RU" from the first two letters niri gives (confirmed
        // format: {"names":[...],"current_idx":N} from `niri msg --json
        // keyboard-layouts`) — not parsing XKB codes, just the display name.
        const name = layoutNames[layoutIdx] ?? ""
        return name.slice(0, 2).toUpperCase()
    }

    readonly property var focusedWorkspace: _find(workspaces, w => w.is_focused)
    readonly property var focusedWindow: _find(windows, w => w.is_focused)
    readonly property string focusedTitle: focusedWindow ? (focusedWindow.title ?? "") : ""

    function _find(list, pred) {
        for (const item of list) {
            if (pred(item)) return item
        }
        return null
    }

    function refresh() {
        wsProc.running = true
        winProc.running = true
    }

    function focusWorkspace(idx) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(idx)])
    }
    function closeFocused() {
        Quickshell.execDetached(["niri", "msg", "action", "close-window"])
    }
    function toggleOverview() {
        Quickshell.execDetached(["niri", "msg", "action", "toggle-overview"])
    }
    // id: a window's numeric `id` field from `windows` above. Field name
    // and type (`id: u64`) confirmed from niri's own `Action::FocusWindow`
    // docs, not guessed.
    function focusWindow(id) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(id)])
    }

    Process {
        id: eventStream
        command: ["niri", "msg", "--json", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: (line) => root.refresh()
        }
        onExited: (code, status) => {
            console.warn("Niri: event-stream exited (code " + code + ", status " + status + "), retrying in 2s")
            restartTimer.start()
        }
    }
    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: eventStream.running = true
    }

    Process {
        id: wsProc
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.workspaces = JSON.parse(text)
                } catch (e) {
                    console.warn("Niri: could not parse `niri msg --json workspaces` output:", e)
                }
            }
        }
    }
    Process {
        id: winProc
        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windows = JSON.parse(text)
                } catch (e) {
                    console.warn("Niri: could not parse `niri msg --json windows` output:", e)
                }
            }
        }
    }

    // Decoupled from the event-stream refresh above: xkb's own group
    // toggle (config.kdl's `grp:win_space_toggle`) is handled inside niri
    // itself and isn't confirmed to emit an event-stream line, so this
    // polls on its own short timer instead of risking a stale indicator.
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: layoutProc.running = true
    }
    Process {
        id: layoutProc
        command: ["niri", "msg", "--json", "keyboard-layouts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.layoutNames = d.names ?? []
                    root.layoutIdx = d.current_idx ?? 0
                } catch (e) {
                    console.warn("Niri: could not parse `niri msg --json keyboard-layouts` output:", e)
                }
            }
        }
    }

    Component.onCompleted: refresh()
}
