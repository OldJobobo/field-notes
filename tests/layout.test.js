const test = require("node:test")
const assert = require("node:assert/strict")
const Layout = require("../Layout.js")

test("fits the entire board on small, narrow and large displays", () => {
  for (const [width, height] of [[1920, 1080], [1280, 720], [800, 600], [640, 480], [400, 900], [10, 10]]) {
    const edge = Layout.margin(width, height)
    const scale = Layout.fitScale(width, height, 880, 660)
    assert.ok(scale > 0 && scale <= 1)
    assert.ok(880 * scale + edge * 2 <= width + 1e-9)
    assert.ok(660 * scale + edge * 2 <= height + 1e-9)
  }
  assert.equal(Layout.fitScale(1920, 1080, 880, 660), 1, "large displays retain authored dimensions")
  assert.equal(Layout.fitScale(0, 0, 880, 660), 0)
})

test("clamps dragging and nudging using scaled extents after a resize", () => {
  const width = 640, height = 480
  const edge = Layout.margin(width, height)
  const scale = Layout.fitScale(width, height, 880, 660)
  assert.equal(Layout.clampPosition(-100, width, 880, scale, edge), edge)
  assert.ok(Layout.clampPosition(10000, width, 880, scale, edge) + 880 * scale <= width - edge + 1e-9)
  assert.ok(Layout.clampPosition(10000, height, 660, scale, edge) + 660 * scale <= height - edge + 1e-9)
})

test("keeps the original board when the toolbar is docked right", () => {
  assert.deepEqual(Layout.dock("right", 760, 560, 540, 48),
    { paperX: 28, paperY: 58, toolX: 814, toolY: 68, width: 880, height: 660 })
})

test("paper, toolbar and clip input regions stay inside the board on every side", () => {
  for (const side of Layout.TOOLBAR_SIDES) {
    const horizontal = side === "top" || side === "bottom"
    const d = Layout.dock(side, 760, 560, 540, 48)
    const tool = { x: d.toolX, y: d.toolY, width: horizontal ? 540 : 48, height: horizontal ? 48 : 540 }
    const regions = [
      { x: d.paperX - 24, y: d.paperY - 28, width: 760 + 48, height: 560 + 56 },
      { x: tool.x - 18, y: tool.y - 18, width: tool.width + 36, height: tool.height + 36 },
      { x: d.paperX + 310 + Math.round(280 * Math.sin(0.8 * Math.PI / 180)), y: d.paperY - 26, width: 140, height: 50 }
    ]
    for (const region of regions) {
      assert.ok(region.x >= 0 && region.y >= 0, side)
      assert.ok(region.x + region.width <= d.width && region.y + region.height <= d.height, side)
    }
    const clip = regions[2], toolbar = tool
    const overlaps = clip.x < toolbar.x + toolbar.width && toolbar.x < clip.x + clip.width &&
      clip.y < toolbar.y + toolbar.height && toolbar.y < clip.y + clip.height
    assert.equal(overlaps, false, side + ": the toolbar must not cover the brass clip")
  }
})

test("docks a dragged toolbar to the nearest paper side without flickering", () => {
  const paper = { x: 28, y: 58, width: 760, height: 560 }
  assert.equal(Layout.nearestSide(860, 300, paper, "right"), "right")
  assert.equal(Layout.nearestSide(0, 300, paper, "right"), "left")
  assert.equal(Layout.nearestSide(400, 0, paper, "right"), "top")
  assert.equal(Layout.nearestSide(400, 650, paper, "left"), "bottom")
  // Exactly on the bottom-right diagonal: stay on whichever side is current.
  assert.equal(Layout.nearestSide(788, 618, paper, "right"), "right")
  assert.equal(Layout.nearestSide(788, 618, paper, "bottom"), "bottom")
  assert.equal(Layout.nearestSide(860, 300, paper, "bogus"), "right")
})

test("every sheet size fits the board with the toolbar docked on any side", () => {
  for (const [width, height] of [[520, 380], [760, 560], [1040, 760]]) {
    for (const side of Layout.TOOLBAR_SIDES) {
      const horizontal = side === "top" || side === "bottom"
      const d = Layout.dock(side, width, height, 582, 48)
      const tool = { x: d.toolX, y: d.toolY, width: horizontal ? 582 : 48, height: horizontal ? 48 : 582 }
      const label = `${width}x${height} ${side}`
      assert.ok(tool.x - 18 >= 0 && tool.y - 18 >= 0, label + ": toolbar inside the board")
      assert.ok(tool.x + tool.width + 18 <= d.width && tool.y + tool.height + 18 <= d.height, label + ": toolbar inside the board")
      assert.ok(d.paperX - 24 >= 0 && d.paperY - 28 >= 0, label + ": paper inside the board")
      assert.ok(d.paperX + width + 24 <= d.width && d.paperY + height + 28 <= d.height, label + ": paper inside the board")
      const centre = horizontal ? tool.x + tool.width / 2 - (d.paperX + width / 2) : tool.y + tool.height / 2 - (d.paperY + height / 2)
      assert.ok(Math.abs(centre) <= 1, label + ": toolbar centred on the paper")
    }
  }
})

test("the settings card fits beside the toolbar on every size and side", () => {
  // Mirrors Panel.settingsArea; the wide two-column card is 780 wide and about 500 tall.
  for (const [width, height] of [[520, 380], [760, 560], [1040, 760]]) {
    for (const side of Layout.TOOLBAR_SIDES) {
      const horizontal = side === "top" || side === "bottom"
      const d = Layout.dock(side, width, height, 624, 48)
      const tool = { x: d.toolX, y: d.toolY, width: horizontal ? 624 : 48, height: horizontal ? 48 : 624 }
      const area = { x: 12, y: 12, width: d.width - 24, height: d.height - 24 }
      if (side === "bottom") area.height = tool.y - 24
      else if (side === "top") { area.y = tool.y + tool.height + 12; area.height = d.height - area.y - 12 }
      else if (side === "left") { area.x = tool.x + tool.width + 12; area.width = d.width - area.x - 12 }
      else area.width = tool.x - 24
      const label = `${width}x${height} ${side}`
      assert.ok(area.width >= 460 && area.height >= 300, label + ": room for at least the narrow card")
      if (width >= 760)
        assert.ok(area.width >= 780 && area.height >= 500, label + ": medium and large sheets fit the two-column card unscrolled")
    }
  }
})
