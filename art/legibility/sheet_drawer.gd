## The GDD 6 legibility sheet, as drawable content. Shared by the PNG
## exporter (legibility_sheet.gd) and the on-screen viewer (legibility_view.gd)
## so the two can never disagree.
##
## All coordinates here are FRAMEBUFFER pixels -- the 640x360 render target.
## Multiply by the display's integer scale for physical pixels.
class_name LegibilitySheet
extends Node2D

const SHEET_W: int = 828
const SHEET_H: int = 1180

## Integer scale the framebuffer gets on the target display. Used ONLY to
## label physical sizes -- every column has its own px/atom, so a single
## global "atom = N px" readout would be a lie.
var display_scale: int = 3:
	set(v):
		display_scale = v
		queue_redraw()

const BLOCK: int = 16                       ## atoms across = standard block
const SCALES: Array = [2, 3, 4, 6, 8]       ## screen px per atom
const CELL: int = 150
const LABEL_W: int = 78

## Channel 1: colour class (GDD 4.6) -- LOSSY family, brown = dirt|clay|...
const FILL := Color("6b533b")
## Channel 2: block border -- reads SIZE, therefore rough cost (GDD 4.1.2)
const BORDER := Color("241a12")
## Channel 3: fracture -- the crack is a shadowed crevice
const CRACK := Color("241a12")

const BG := Color("1b1b21")
const INK := Color("ddd6c6")
const DIM := Color("8c8578")

var _font: Font = ThemeDB.fallback_font

func _draw() -> void:
	draw_rect(Rect2(0, 0, SHEET_W, SHEET_H), BG, true)
	_calibration()

	for i: int in SCALES.size():
		var s: int = SCALES[i]
		_text(Vector2(LABEL_W + i * CELL, 20),
			"%d px/atom" % s, INK, 13)
		_text(Vector2(LABEL_W + i * CELL, 34),
			"ON SCREEN  atom %dpx, block %dpx" % [
				s * display_scale, BLOCK * s * display_scale], DIM, 11)

	# ---- Band A: uniform subdivision, depth 1..4 -------------------
	_text(Vector2(8, 60), "UNIFORM DEPTH  -- where does the grid become noise?", INK, 13)
	for d: int in range(1, 5):
		var y: int = 76 + (d - 1) * CELL
		_text(Vector2(8, y + 30), "depth %d" % d, INK, 12)
		_text(Vector2(8, y + 44), _spacing_note(d), DIM, 10)
		for i: int in SCALES.size():
			_block(Vector2(LABEL_W + i * CELL, y), SCALES[i], d)

	# ---- Band B: the GDD 4.6.2 silhouettes -------------------------
	var y0: int = 76 + 4 * CELL + 16
	_text(Vector2(8, y0), "SILHOUETTES (GDD 4.6.2) -- are these three telling apart in one frame?", INK, 13)
	var cases: Array = [
		["hard stone", "one clean cross", 1],
		["deep core Q0", "dense one corner", {0: 3, 1: 1, 2: 1, 3: 1}],
		["sand", "fine lines everywhere", 4],
	]
	for r: int in cases.size():
		var y: int = y0 + 16 + r * CELL
		_text(Vector2(8, y + 30), str(cases[r][0]), INK, 12)
		_text(Vector2(8, y + 44), str(cases[r][1]), DIM, 10)
		for i: int in SCALES.size():
			_block(Vector2(LABEL_W + i * CELL, y), SCALES[i], cases[r][2])

## 128 framebuffer px = 384 physical px at 3x = exactly 1/5 of a 1920px
## panel. If it does not measure a fifth of your screen, you are not at 100%.
func _calibration() -> void:
	var y: float = float(SHEET_H) - 26.0
	draw_rect(Rect2(8, y, 128, 8), INK, true)
	for t: int in 6:
		var x: float = 8.0 + float(t) * 128.0 / 5.0
		draw_line(Vector2(x, y - 5), Vector2(x, y + 13), INK, 1.0)
	_text(Vector2(148, y + 9),
		"RULER  %d physical px at %dx. At 3x that is one fifth of a 1920px screen." % [
			128 * display_scale, display_scale],
		DIM, 11)


func _spacing_note(d: int) -> String:
	var parts: PackedStringArray = []
	for s: int in SCALES:
		parts.append(str((BLOCK * s) >> d))
	return "gap: " + ", ".join(parts) + "px"

## Draw one standard block: fill, border, then fracture. Three channels.
func _block(at: Vector2, scale: int, spec: Variant) -> void:
	var px: int = BLOCK * scale
	draw_rect(Rect2(at.x, at.y, px, px), FILL, true)
	_fracture(at, float(px), spec)
	# Border last so it survives crack overdraw. 2px reads as "edge",
	# distinct from the 1px hairline of a crack.
	draw_rect(Rect2(at.x, at.y, px, px), BORDER, false, 2.0)

## spec: int = uniform remaining depth. Dictionary = subdivide once, then
## each child q follows spec[q]. Mirrors an override tree (GDD 4.7.1)
## without pretending to be one.
func _fracture(o: Vector2, px: float, spec: Variant) -> void:
	var depth: int = spec if spec is int else 1
	if depth <= 0 or px < 2.0:
		return
	var half: float = px * 0.5
	draw_line(Vector2(o.x + half, o.y), Vector2(o.x + half, o.y + px), CRACK, 1.0)
	draw_line(Vector2(o.x, o.y + half), Vector2(o.x + px, o.y + half), CRACK, 1.0)
	for q: int in 4:
		var child := Vector2(
			o.x + float(q & 1) * half,
			o.y + float((q & 2) >> 1) * half)
		var sub: Variant = spec[q] if spec is Dictionary else depth - 1
		_fracture(child, half, sub)

func _text(at: Vector2, s: String, c: Color, size: int) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
