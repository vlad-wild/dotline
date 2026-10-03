pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// dotline — MPRIS media player (bar indicator + quicksettings-style card,
// see media/MediaCard.qml). Verified API (Mpris singleton has exactly one
// property, `players: ObjectModel<MprisPlayer>`; MprisPlayer's trackTitle/
// trackArtist/trackAlbum/trackArtUrl/volume/playbackState/canXxx, and
// play()/pause()/next()/previous()/seek()/togglePlaying()) against the
// real quickshell.org/docs/v0.3.1 pages, not guessed.
//
// Two gotchas from those docs that would've been easy to get wrong:
// - `position` does NOT update reactively on its own (the docs say this is
//   deliberate, to save CPU) — has to be polled by calling the player's
//   own `positionChanged()` while something is playing, which is what the
//   Timer below does; without it the progress dots would freeze.
// - Not every player supports every control — always gate on the matching
//   `canXxx`/`xxxSupported` property, never assume.
Singleton {
    id: root

    readonly property var players: Mpris.players ? [...Mpris.players.values] : []

    // Manual pick (quicksettings player switcher) when nothing is playing;
    // whatever IS playing always wins over it, so the bar/card follow
    // whichever app just started music rather than getting stuck on a
    // paused player the user happened to click once.
    property var manualPlayer: null

    readonly property var activePlayer: {
        const playing = players.find(p => p.playbackState === MprisPlaybackState.Playing)
        if (playing) return playing
        if (manualPlayer && players.includes(manualPlayer)) return manualPlayer
        return players[0] ?? null
    }
    function selectPlayer(p) { manualPlayer = p }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool playing: hasPlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property string title: hasPlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string artist: hasPlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string album: hasPlayer ? (activePlayer.trackAlbum || "") : ""
    readonly property string artUrl: hasPlayer ? (activePlayer.trackArtUrl || "") : ""
    readonly property string identity: hasPlayer ? (activePlayer.identity || "") : ""
    readonly property real position: hasPlayer ? activePlayer.position : 0
    readonly property real length: hasPlayer && activePlayer.lengthSupported ? activePlayer.length : 0
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
    readonly property bool hasVolume: hasPlayer && activePlayer.volumeSupported
    readonly property real volume: hasVolume ? activePlayer.volume : 0

    // See the file-level note: MPRIS position is poll-only.
    Timer {
        interval: 1000
        repeat: true
        running: root.playing
        onTriggered: root.activePlayer && root.activePlayer.positionChanged()
    }

    function toggle() { if (root.hasPlayer && root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying() }
    function next() { if (root.hasPlayer && root.activePlayer.canGoNext) root.activePlayer.next() }
    function previous() { if (root.hasPlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous() }
    function seekTo(fraction) {
        if (!root.hasPlayer || !root.activePlayer.canSeek || root.length <= 0) return
        root.activePlayer.position = Math.max(0, Math.min(1, fraction)) * root.length
    }
    function setVolume(v) {
        if (root.hasVolume) root.activePlayer.volume = Math.max(0, Math.min(1, v))
    }
}
