import QtQuick
import "../" as Dotline

// Point-grid glyphs — the clock face's tick pattern, the cloud/phone/face
// icons, the Arch logo in fastfetch's on-screen twin. Same technique as
// the browser mock-up's `dots()` helper (scratchpad/mockup/dotline.html),
// ported from SVG to a Canvas so it can live inside a real Quickshell panel.
//
// `pattern` is an array of equal-length strings: '.' empty, '#' a dot,
// 'o' a dimmed dot (battery level, "no signal", that kind of partial state).
//
// Bind `color`/`dimColor` to a live Theme property (e.g. `color:
// Dotline.Theme.ink`, not a one-time value) to get the same smooth colour
// fade as everything else when the wallpaper changes: Theme's own
// Behavior-driven animation re-fires this binding every frame, which is
// what makes the canvas repaint each of those frames.
Item {
    id: root

    property var pattern: ["."]
    property real cell: 6
    property real dotRadius: cell * 0.36
    property color color: Dotline.Theme.ink
    property color dimColor: Dotline.Theme.muted

    readonly property int rows: pattern.length
    readonly property int cols: rows > 0 ? pattern[0].length : 0

    implicitWidth: cols * cell
    implicitHeight: rows * cell

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            // clearRect over reset(): older/guaranteed-supported API, and
            // this canvas never changes size, so a full transform reset
            // isn't needed anyway.
            ctx.clearRect(0, 0, width, height)
            for (let y = 0; y < root.rows; y++) {
                const row = root.pattern[y]
                for (let x = 0; x < root.cols; x++) {
                    const c = row[x]
                    if (c === ".") continue
                    ctx.beginPath()
                    ctx.arc(x * root.cell + root.cell / 2, y * root.cell + root.cell / 2,
                            root.dotRadius, 0, Math.PI * 2)
                    ctx.fillStyle = (c === "o") ? root.dimColor : root.color
                    ctx.fill()
                }
            }
        }

        Connections {
            target: root
            function onPatternChanged() { canvas.requestPaint() }
            function onCellChanged() { canvas.requestPaint() }
            function onDotRadiusChanged() { canvas.requestPaint() }
            function onColorChanged() { canvas.requestPaint() }
            function onDimColorChanged() { canvas.requestPaint() }
        }
    }
}
