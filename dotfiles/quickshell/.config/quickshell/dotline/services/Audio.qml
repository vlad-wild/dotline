pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "." as Services

// dotline — audio: default sink (bar/OSD), per-app mixer and
// output/input device pickers (quicksettings), mic level (privacy dot in
// the plan, not built yet — see services/Caffeine.qml's sibling note) and
// Mod+Shift+M (mute the focused window's app).
//
// Verified against the real Quickshell.Services.Pipewire docs:
// `PwObjectTracker` is required to bind a node before its
// `audio.volume`/`audio.muted` do anything live — easy to miss, called
// out explicitly in the docs as a gotcha, and already learned the hard
// way for the default sink alone before this file grew to track every
// node. `Pipewire.nodes` is an ObjectModel — `.values`, same lesson as
// BtService/NetworkService. `PwNodeType.AudioOutStream` (an app's
// playback stream, not a physical sink) and the `properties["application.
// process.id"]` key (confirmed from pipewire-props(7), not guessed) are
// what make the per-app mixer and Mod+Shift+M possible.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool ready: Pipewire.ready

    readonly property var allNodes: ready ? [...Pipewire.nodes.values] : []

    // Physical devices, for the output/input picker.
    readonly property var sinks: allNodes.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var sources: allNodes.filter(n => !n.isSink && !n.isStream && n.audio)

    // App playback streams, for the per-app mixer.
    readonly property var appStreams: allNodes.filter(n => n.type === PwNodeType.AudioOutStream && n.audio)

    function appLabel(node) {
        return (node.properties && node.properties["application.name"]) ||
               node.description || node.nickname || node.name
    }

    // Tracks every node this file might read live audio.* fields from —
    // allNodes already covers sinks/sources/appStreams since they're all
    // filtered from it.
    PwObjectTracker {
        objects: root.allNodes
    }

    PwNodePeakMonitor {
        id: micPeak
        node: root.source
    }
    readonly property real micLevel: micPeak.peak

    function setVolume(v) {
        if (sink?.audio) sink.audio.volume = Math.max(0, Math.min(1, v))
    }
    function toggleMute() {
        if (sink?.audio) sink.audio.muted = !sink.audio.muted
    }

    function setAppVolume(node, v) {
        if (node?.audio) node.audio.volume = Math.max(0, Math.min(1, v))
    }
    function toggleAppMute(node) {
        if (node?.audio) node.audio.muted = !node.audio.muted
    }

    function selectSink(node) { Pipewire.preferredDefaultAudioSink = node }
    function selectSource(node) { Pipewire.preferredDefaultAudioSource = node }

    // Mod+Shift+M (config.kdl): mutes whichever app stream belongs to the
    // same process as niri's currently focused window. Matched by pid
    // (`application.process.id` on the stream vs `pid` on the window,
    // both confirmed real fields, not app_id/name — those don't reliably
    // correspond 1:1 between a window and its audio stream).
    function muteFocusedAppStream() {
        const w = Services.Niri.focusedWindow
        if (!w || !w.pid) return
        for (const n of appStreams) {
            const streamPid = n.properties && Number(n.properties["application.process.id"])
            if (streamPid === w.pid) toggleAppMute(n)
        }
    }
}
