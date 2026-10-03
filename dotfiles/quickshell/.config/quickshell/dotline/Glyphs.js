.pragma library

// Dot-grid bitmaps for DotMatrix.qml. Same patterns as the interactive
// mock-up (scratchpad/mockup/dotline.html, object `G`), so the shell
// built in step 5/6 looks like what was already agreed on there instead of
// redrawing these from scratch.

var cloud = [
    ".......###......",
    ".....#######....",
    "..###########...",
    ".#############..",
    ".###############",
    "################",
    "################",
    ".##############."
]

var face = [
    ".#########.",
    "#.........#",
    "#...###...#",
    "#.........#",
    "#.........#",
    "#..#...#..#",
    "#.........#",
    "#....#....#",
    "#....#....#",
    "#...##....#",
    "#.........#",
    "#..#...#..#",
    "#...###...#",
    "#.........#",
    "#.........#",
    "#....#....#",
    ".#########."
]

// Rows 4-8, columns other than the two outer ones, are the "battery" band:
// pass a fill level in [0, 1] to phoneAt() and those rows switch between
// '#' (lit) and 'o' (dim) bottom-up, same as the mock-up's `level` param.
var phoneBase = [
    ".#######.",
    "#.......#",
    "#..###..#",
    "#.......#",
    "#.#####.#",
    "#.#####.#",
    "#.#####.#",
    "#.#####.#",
    "#.#####.#",
    "#.......#",
    "#.......#",
    ".#######."
]

function phoneAt(level) {
    // Row "#.#####.#": idx 0-1 and 7-8 are the phone's own frame, idx 2-6
    // (5 chars) are the battery band this redraws — slice(0,2)/slice(7)
    // keep the frame untouched so every row stays the same width.
    var lit = Math.round((level === undefined ? 1 : level) * 5)
    var rows = phoneBase.slice()
    for (var y = 4; y <= 8; y++) {
        var band = (8 - y) < lit ? "#" : "o"
        rows[y] = rows[y].slice(0, 2) + band.repeat(5) + rows[y].slice(7)
    }
    return rows
}

var arch = [
    "......#......",
    ".....###.....",
    ".....###.....",
    "....#####....",
    "....#####....",
    "...#######...",
    "..####.####..",
    "..###...###..",
    ".###.....###.",
    ".##.......##.",
    "##.........##"
]
