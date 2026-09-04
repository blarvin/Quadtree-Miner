## THROWAWAY DEV TOOL (GDD 6, Phase 1 "terrain painter"). Paints blocks into a
## World and writes it as a flat block list -- the save format with no damage,
## so WorldSave reads and writes it unchanged.
##
##   godot --path . scenes/map_painter.tscn
##
## The ASCII dev map is the seed, read once. Free placement means a character
## grid can no longer describe the result (GDD 4.1.0), so the painted file is
## the authored map from then on.
##
## Overlap: a stamp deletes every block it touches, whole. See PaintOps.
extends Node2D

const TEMPLATE_DIR: String = "res://data/templates"
const SEED_MAP: String = "res://data/maps/dev_map.json"
const PAINTED_MAP: String = "res://data/maps/painted_map.json"

## Framebuffer pixels per atom. 3 is true game scale (GDD 4.1.2).
const ZOOMS: Array[float] = [1.0, 2.0, 3.0, 4.0, 6.0, 8.0]
const TRUE_SCALE_ZOOM: int = 2
const PAN_ATOMS_PER_SEC: float = 220.0
const TILINGS: Array[int] = [1, 2, 4]

const VOID_FILL: Color = Color(0.05, 0.05, 0.07)
const CLASS_FILL: Dictionary = {
	Materials.ColourClass.BROWN: Color(0.44, 0.31, 0.21),
	Materials.ColourClass.GREY: Color(0.40, 0.41, 0.44),
}
## Authoring needs honest_dirt distinguishable from liar_dirt; the game's two
## colour classes do not distinguish them. A stable per-template tint over the
## real class colour keeps the palette honest and the blocks tellable apart.
const TINT_MIX: float = 0.30
const BORDER_DARKEN: float = 0.55
const DOOMED: Color = Color(1.0, 0.25, 0.25, 0.55)
const BRUSH_OK: Color = Color(0.4, 1.0, 0.5)
const BRUSH_BAD: Color = Color(1.0, 0.4, 0.3)
const LATTICE: Color = Color(1, 1, 1, 0.07)

var world: World = null
var templates: Dictionary = {}
var _ids: Array[String] = []

var _cam: Vector2 = Vector2(0, 48)
var _zoom: int = TRUE_SCALE_ZOOM
var _scale: float = ZOOMS[TRUE_SCALE_ZOOM]

var _template_id: String = ""
var _size: int = 16
var _tiling: int = 0  ## index into TILINGS
var _brush_problem: String = ""

var _undo: Array[MapEdit] = []
var _redo: Array[MapEdit] = []
var _stroke: MapEdit.Stroke = null
var _stroke_erases: bool = false
var _last_stamp: Vector2i = Vector2i(-99999, -99999)

var _hud: Label = null
var _palette: PanelContainer = null
var _tints: Dictionary = {}
var _dirty: bool = false

func _ready() -> void:
	var errors: PackedStringArray = []
	templates = TemplateLoader.load_dir(TEMPLATE_DIR, errors)
	_ids.assign(templates.keys())
	_ids.sort()

	if FileAccess.file_exists(PAINTED_MAP):
		world = WorldSave.load_from_file(PAINTED_MAP, templates, errors)
		print("painter: loaded %s" % PAINTED_MAP)
	else:
		world = MapLoader.from_file(SEED_MAP, templates, errors)
		print("painter: seeded from %s (save writes %s)" % [SEED_MAP, PAINTED_MAP])
	for e: String in errors:
		push_error(e)

	if not _ids.is_empty():
		_pick(_ids[0])
	_build_ui()
	print("painter: %d blocks, %d templates" % [world.blocks.size(), templates.size()])

# --- input ---------------------------------------------------------------

func _process(delta: float) -> void:
	var move := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"))
	if move != Vector2.ZERO:
		_cam += move * PAN_ATOMS_PER_SEC * delta / (_scale / ZOOMS[TRUE_SCALE_ZOOM])
		_clamp_camera()
	if _stroke != null and not _over_ui():
		_stamp_at_cursor()
	_update_hud()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: InputEventKey = event
	match k.keycode:
		KEY_Z when k.ctrl_pressed and k.shift_pressed: _do_redo()
		KEY_Z when k.ctrl_pressed: _do_undo()
		KEY_Y when k.ctrl_pressed: _do_redo()
		KEY_S when k.ctrl_pressed: _save()
		KEY_B: _stamp_bench()
		KEY_BRACKETLEFT: _set_size(maxi(1, _size >> 1))
		KEY_BRACKETRIGHT: _set_size(mini(256, _size << 1))
		KEY_1: _tiling = 0
		KEY_2: _tiling = 1
		KEY_3: _tiling = 2
		KEY_TAB: _set_zoom(TRUE_SCALE_ZOOM if _zoom != TRUE_SCALE_ZOOM else 0)

func _mouse_button(m: InputEventMouseButton) -> void:
	if m.button_index == MOUSE_BUTTON_WHEEL_UP and m.pressed:
		_set_zoom(_zoom + 1)
	elif m.button_index == MOUSE_BUTTON_WHEEL_DOWN and m.pressed:
		_set_zoom(_zoom - 1)
	elif m.button_index == MOUSE_BUTTON_LEFT or m.button_index == MOUSE_BUTTON_RIGHT:
		if m.pressed and not _over_ui():
			_stroke = MapEdit.Stroke.new()
			_stroke_erases = m.button_index == MOUSE_BUTTON_RIGHT
			_last_stamp = Vector2i(-99999, -99999)
		elif not m.pressed:
			_end_stroke()

## A drag is one undo step, and the net of it: see MapEdit.Stroke.
func _end_stroke() -> void:
	if _stroke == null:
		return
	if not _stroke.is_empty():
		_undo.append(_stroke.to_edit())
		_redo.clear()
		_dirty = true
	_stroke = null

func _stamp_at_cursor() -> void:
	if not _stroke_erases and (_template_id == "" or _brush_problem != ""):
		return
	var at: Vector2i = _brush_origin()
	if at == _last_stamp:
		return  # the cursor has not left the cell it already painted
	_last_stamp = at
	var n: int = TILINGS[_tiling]
	var e: MapEdit = PaintOps.erase(world, at, _size, n) if _stroke_erases \
		else PaintOps.stamp(world, at, _size, n, _template_id)
	if e.is_empty():
		return
	e.apply(world)
	_stroke.absorb(e)

func _stamp_bench() -> void:
	if _ids.is_empty():
		return
	var e: MapEdit = PaintOps.bench(world, _brush_origin(), _size, _ids)
	e.apply(world)
	_undo.append(e)
	_redo.clear()
	_dirty = true

func _do_undo() -> void:
	if _undo.is_empty():
		return
	var e: MapEdit = _undo.pop_back()
	e.revert(world)
	_redo.append(e)
	_dirty = true

func _do_redo() -> void:
	if _redo.is_empty():
		return
	var e: MapEdit = _redo.pop_back()
	e.apply(world)
	_undo.append(e)
	_dirty = true

func _save() -> void:
	if FileAccess.file_exists(PAINTED_MAP):
		DirAccess.copy_absolute(PAINTED_MAP, PAINTED_MAP + ".bak")
	if WorldSave.save_to_file(world, PAINTED_MAP):
		_dirty = false
		print("painter: wrote %d blocks to %s" % [world.blocks.size(), PAINTED_MAP])

# --- brush ---------------------------------------------------------------

## Alt paints free; otherwise the block lands on its own size lattice.
func _brush_origin() -> Vector2i:
	var atom: Vector2i = _atom_under_mouse()
	return atom if Input.is_key_pressed(KEY_ALT) else PaintOps.snap(atom, _size)

func _pick(id: String) -> void:
	_template_id = id
	var t: BlockTemplate = templates[id]
	if t.authored_size > 0:
		_size = t.authored_size
	_revalidate()

func _set_size(s: int) -> void:
	_size = s
	_revalidate()

## A template's override tree only makes sense under some root sizes
## (GDD 4.7.1); refuse the brush rather than author a block that misbehaves.
func _revalidate() -> void:
	_brush_problem = ""
	if _template_id == "" or not templates.has(_template_id):
		return
	var problems: PackedStringArray = templates[_template_id].validate_for_root_size(_size)
	if not problems.is_empty():
		_brush_problem = " ".join(problems)

func _set_zoom(z: int) -> void:
	z = clampi(z, 0, ZOOMS.size() - 1)
	if z == _zoom:
		return
	var anchor: Vector2 = _cam + _mouse() / _scale
	_zoom = z
	_scale = ZOOMS[z]
	_cam = anchor - _mouse() / _scale
	_clamp_camera()

# --- drawing -------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), VOID_FILL, true)
	if world == null:
		return
	var view: Rect2i = _view_rect()
	for b: BlockInstance in world.blocks_in(view):
		var fill: Color = _tint(b.template_id)
		var r: Rect2 = _to_screen(b.rect())
		draw_rect(r, fill, true)
		draw_rect(r, fill.darkened(BORDER_DARKEN), false, 1.0)
	_draw_lattice(view)

	var n: int = TILINGS[_tiling]
	var fp: Rect2i = PaintOps.footprint(_brush_origin(), _size, n)
	for b: BlockInstance in world.blocks_in(fp):
		draw_rect(_to_screen(b.rect()), DOOMED, true)
	var edge: Color = BRUSH_BAD if _brush_problem != "" else BRUSH_OK
	draw_rect(_to_screen(fp), edge, false, 1.0)
	for i: int in n + 1:  # the brush's own block seams
		var off: float = float(i * _size) * _scale
		var tl: Vector2 = _to_screen(fp).position
		var span: float = float(_size * n) * _scale
		draw_line(tl + Vector2(off, 0), tl + Vector2(off, span), edge * Color(1, 1, 1, 0.4), 1.0)
		draw_line(tl + Vector2(0, off), tl + Vector2(span, off), edge * Color(1, 1, 1, 0.4), 1.0)

func _draw_lattice(view: Rect2i) -> void:
	if _scale < 3.0 or _size * _scale < 12.0:
		return
	var vp: Vector2 = get_viewport_rect().size
	var x: int = PaintOps.snap(view.position, _size).x
	while float(x) < float(view.position.x + view.size.x):
		var sx: float = (float(x) - _cam.x) * _scale
		draw_line(Vector2(sx, 0), Vector2(sx, vp.y), LATTICE, 1.0)
		x += _size
	var y: int = PaintOps.snap(view.position, _size).y
	while float(y) < float(view.position.y + view.size.y):
		var sy: float = (float(y) - _cam.y) * _scale
		draw_line(Vector2(0, sy), Vector2(vp.x, sy), LATTICE, 1.0)
		y += _size

func _tint(id: String) -> Color:
	if _tints.has(id):
		return _tints[id]
	var t: BlockTemplate = templates.get(id)
	var base: Color = CLASS_FILL.get(t.colour_class, Color.MAGENTA) if t != null else Color.MAGENTA
	var hue: float = float(abs(hash(id)) % 360) / 360.0
	var c: Color = base.lerp(Color.from_hsv(hue, 0.55, 0.85), TINT_MIX)
	_tints[id] = c
	return c

# --- ui ------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_palette = PanelContainer.new()
	_palette.position = Vector2(2, 2)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_palette.add_child(box)
	for id: String in _ids:
		var b := Button.new()
		b.text = id
		b.add_theme_font_size_override("font_size", 8)
		b.add_theme_color_override("font_color", _tint(id).lightened(0.45))
		b.pressed.connect(_pick.bind(id))
		box.add_child(b)
	layer.add_child(_palette)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 9)
	_hud.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.anchor_right = 1.0
	_hud.offset_left = 4
	_hud.offset_top = 3
	_hud.offset_right = -4
	layer.add_child(_hud)

func _update_hud() -> void:
	var atom: Vector2i = _atom_under_mouse()
	var under: BlockInstance = world.block_at(atom)
	var n: int = TILINGS[_tiling]
	var brush: String = "%s  size %d  x%d (%d blocks, %d atoms)" % [
		_template_id if _template_id != "" else "(none)", _size, n, n * n, _size * n]
	if _brush_problem != "":
		brush += "  INVALID: " + _brush_problem
	_hud.text = "\n".join([
		brush,
		"atom %d,%d   %s" % [atom.x, atom.y, str(under) if under != null else "void"],
		"%d blocks   %d undo   %s%s" % [
			world.blocks.size(), _undo.size(),
			"%.0f px/atom" % _scale, "   UNSAVED" if _dirty else ""],
		"LMB paint  RMB erase  alt free  [ ] size  1/2/3 x1/x4/x16  B bench",
		"wheel zoom  TAB true scale  WASD pan  ctrl+Z undo  ctrl+S save",
	])

# --- geometry ------------------------------------------------------------

func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()

func _over_ui() -> bool:
	return _palette != null and _palette.get_global_rect().has_point(_mouse())

func _atom_under_mouse() -> Vector2i:
	var a: Vector2 = _cam + _mouse() / _scale
	return Vector2i(floori(a.x), floori(a.y))

func _to_screen(r: Rect2i) -> Rect2:
	return Rect2((Vector2(r.position) - _cam) * _scale, Vector2(r.size) * _scale)

func _view_atoms() -> Vector2:
	return get_viewport_rect().size / _scale

func _view_rect() -> Rect2i:
	var span: Vector2 = _view_atoms()
	return Rect2i(Vector2i(floori(_cam.x), floori(_cam.y)),
		Vector2i(ceili(span.x) + 1, ceili(span.y) + 1))

func _clamp_camera() -> void:
	var span: Vector2 = _view_atoms()
	_cam.x = clampf(_cam.x, 0.0, maxf(0.0, world.extent.x - span.x))
	_cam.y = clampf(_cam.y, 0.0, maxf(0.0, world.extent.y - span.y))
