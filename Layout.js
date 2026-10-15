var TOOLBAR_SIDES = ["right", "left", "top", "bottom"]

function margin(width, height) {
    return Math.min(12, Math.max(0, width) / 4, Math.max(0, height) / 4)
}

function fitScale(width, height, boardWidth, boardHeight) {
    var edge = margin(width, height)
    return Math.max(0, Math.min(1, (width - 2 * edge) / boardWidth, (height - 2 * edge) / boardHeight))
}

function clampPosition(value, extent, boardExtent, scale, edge) {
    return Math.max(edge, Math.min(Math.max(edge, extent - boardExtent * scale - edge), value))
}

// Board geometry with the toolbar docked on one side of the paper. The toolbar is
// toolLength long and thickness deep whichever way it faces. The space around the paper
// leaves room for its tilt and shadow, and for the brass clip above it.
function dock(side, paperWidth, paperHeight, toolLength, thickness) {
    var edge = 18
    var gap = 26
    var layout = { paperX: 28, paperY: 58 }
    if (side === "left")
        layout.paperX = edge + thickness + gap
    else if (side === "top")
        layout.paperY = edge + thickness + 40

    if (side === "top" || side === "bottom") {
        layout.toolX = layout.paperX + Math.round((paperWidth - toolLength) / 2)
        layout.toolY = side === "top" ? edge : layout.paperY + paperHeight + gap
        layout.width = layout.paperX + paperWidth + 28
        layout.height = layout.paperY + paperHeight + (side === "bottom" ? gap + thickness + edge : 42)
    } else {
        layout.toolX = side === "left" ? edge : layout.paperX + paperWidth + gap
        layout.toolY = layout.paperY + Math.round((paperHeight - toolLength) / 2)
        layout.width = layout.paperX + paperWidth + (side === "right" ? gap + thickness + edge : 28)
        layout.height = layout.paperY + paperHeight + 42
    }
    return layout
}

// The paper side a dragged toolbar should dock to. Distances are relative to the paper's
// half-size, and the current side is kept near the diagonals so docking does not flicker.
function nearestSide(x, y, paper, current) {
    var nx = (x - (paper.x + paper.width / 2)) / (paper.width / 2)
    var ny = (y - (paper.y + paper.height / 2)) / (paper.height / 2)
    var scores = { right: nx, left: -nx, bottom: ny, top: -ny }
    var best = TOOLBAR_SIDES.indexOf(current) >= 0 ? current : "right"
    for (var i = 0; i < TOOLBAR_SIDES.length; i++) {
        var side = TOOLBAR_SIDES[i]
        if (scores[side] > scores[best] + (best === current ? 0.15 : 0))
            best = side
    }
    return best
}

if (typeof module !== "undefined")
    module.exports = {
        TOOLBAR_SIDES: TOOLBAR_SIDES,
        margin: margin,
        fitScale: fitScale,
        clampPosition: clampPosition,
        dock: dock,
        nearestSide: nearestSide
    }
