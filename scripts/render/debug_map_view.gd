## THROWAWAY. Delete this when the real renderer arrives.
##
## It exists to answer one question, which GDD 4.1.2 calls a prerequisite and
## GDD 6 calls the risk this phase is least equipped to notice going wrong:
##
##     ARE BLOCK BORDERS LEGIBLE ON UNTOUCHED TERRAIN?
##
## If a player cannot read SIZE as cost before striking, the boulder-in-rubble
## is a gotcha rather than a decision, and half the terrain vocabulary of
## 4.1.2 is unreachable. That is an art question, not an engineering one, so no
## test can answer it -- you have to look.
##
## So this draws exactly two of the three channels of 4.1.2 and no more:
##   colour class  (GDD 4.6 layer 2 -- deliberately lossy, family only)
##   block border  (size, and therefore rough cost)
## and NOT fractures, which are the third channel and belong to the renderer.
## Everything is drawn at true game scale, Atoms.PX, because the whole point
## is whether it reads at the size it will actually be played at.
extends Node2D

const TEMPLATE_DIR: String = "res://data/templates"
const MAP_PATH: String = "res://data/maps/dev_map.json"

const PAN_ATOMS_PER_SEC: float = 220.0

## Colour-class palette. Two families, chosen to be clearly different from each
## other and clearly NOT a material identity -- brown is dirt OR sand, grey is
## stone OR hard stone OR coal. If these ever start naming materials, the
## reveal ladder has been flattened and the price of information is gone.
const VOID_FILL: Color = Color(0.05, 0.05, 0.07)
const FILL: Dictionary = {
	Materials.ColourClass.BROWN: Color(0.44, 0.31, 0.21),
	Materials.ColourClass.GREY: Color(0.40, 0.41, 0.44),
}
## The channel under test. Darker than the fill so a border reads as a seam
## rather than as a highlight.
const BORDER_DARKEN: float = 0.55

var world: World = null
var _cam: Vector2 = Vector2(0, 48)   ## top-left of the view, in atoms
var _scale: float = float(Atoms.PX)  ## framebuffer pixels per atom
var _overview: bool = false
var _hud: Label = null
var _visible_blocks: int = 0

## Somewhere to look. The set pieces are the reason the map exists, and
## panning 64 cells to find one is not an experiment, it is a chore.
const LANDMARKS: Array[Dictionary] = [
	## Atom coordinates, straight from the map's own cell landmarks.
	{"key": KEY_1, "name": "packing test: boulder at cell (12, 10)", "at": Vector2(200, 168)},
	{"key": KEY_2, "name": "the trap: sand shelf over a cave, cell (20, 18)", "at": Vector2(344, 304)},
	{"key": KEY_3, "name": "second rubble band, row 28", "at": Vector2(392, 456)},
	{"key": KEY_4, "name": "the deep gates, rows 42-55", "at": Vector2(640, 688)},
]

func _ready() -> void:
	var errors: PackedStringArray = []
	var templates: Dictionary = TemplateLoader.load_dir(TEMPLATE_DIR, errors)
	world = MapLoader.from_file(MAP_PATH, templates, errors)
	for e: String in errors:
		push_error(e)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 10)
	_hud.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	_hud.position = Vector2(4, 3)
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	add_child(layer)

	print("debug map view: %d blocks, %d nodes, %d templates%s" % [
		world.blocks.size(), world.node_count(), templates.size(),
		"" if errors.is_empty() else " (%d PROBLEMS -- see errors above)" % errors.size(),
	])

func _process(delta: float) -> void:
	var move := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"))
	if move != Vector2.ZERO:
		_cam += move * PAN_ATOMS_PER_SEC * delta
		_clamp_camera()
	_update_hud()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = (event as InputEventKey).keycode
	if key == KEY_TAB:
		## Overview is for checking the map you authored, NOT for judging
		## legibility -- that question only means anything at true scale.
		_overview = not _overview
		_apply_scale()
	for l: Dictionary in LANDMARKS:
		if key == l["key"]:
			_overview = false
			_apply_scale()
			_cam = l["at"] - _view_atoms() * 0.5
			_clamp_camera()

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), VOID_FILL, true)
	if world == null:
		return

	var view := Rect2(_cam, _view_atoms())
	var drawn: int = 0
	for b: BlockInstance in world.blocks:
		var extent := Rect2(Vector2(b.origin), Vector2(b.size, b.size))
		if not view.intersects(extent):
			continue
		var fill: Color = FILL[world.template_for(b).colour_class]
		var screen := Rect2((Vector2(b.origin) - _cam) * _scale, Vector2(b.size, b.size) * _scale)
		draw_rect(screen, fill, true)
		## One framebuffer pixel, whatever the scale. At Atoms.PX = 3 a size-16
		## block is 48px with a 1px seam, and a size-4 block is 12px with the
		## same seam -- which is precisely the comparison being judged.
		draw_rect(screen, fill.darkened(BORDER_DARKEN), false, 1.0)
		drawn += 1
	_visible_blocks = drawn

func _view_atoms() -> Vector2:
	return get_viewport_rect().size / _scale

func _apply_scale() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if _overview:
		_scale = minf(vp.x / float(world.extent.x), vp.y / float(world.extent.y))
	else:
		_scale = float(Atoms.PX)
	_clamp_camera()

func _clamp_camera() -> void:
	var span: Vector2 = _view_atoms()
	_cam.x = clampf(_cam.x, 0.0, maxf(0.0, world.extent.x - span.x))
	_cam.y = clampf(_cam.y, 0.0, maxf(0.0, world.extent.y - span.y))

func _update_hud() -> void:
	var cell: Vector2i = Vector2i(_cam) / Atoms.STANDARD_BLOCK
	_hud.text = "\n".join([
		"atom %d,%d   cell %d,%d   depth %d character-heights" % [
			int(_cam.x), int(_cam.y), cell.x, cell.y,
			int(_cam.y) / Atoms.CHARACTER_HEIGHT,
		],
		"%d of %d blocks   %s   1 atom = %s px" % [
			_visible_blocks, world.blocks.size(),
			"OVERVIEW" if _overview else "true scale",
			("%.2f" % _scale) if _overview else str(Atoms.PX),
		],
		"WASD/arrows pan   TAB overview   1-4 landmarks",
		"brown = dirt or sand   grey = stone, hard stone or coal",
	])
