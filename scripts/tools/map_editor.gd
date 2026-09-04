## THROWAWAY DEV TOOL (GDD 6, Phase 1 "terrain painter"), living inside the
## running game: keys move and dig, the mouse edits, one World underneath.
##
## A child of Stage, so its coordinates are atoms and the camera is already
## applied -- get_local_mouse_position() is the atom under the cursor. Added
## last so it draws over Terrain, Ladders and Player.
##
## Terrain redraws from world.blocks every frame (terrain_view), and World
## keeps its index on add/remove, so an edit is visible and walkable at once.
class_name MapEditor
extends Node2D

@export var painted_path: String = "res://data/maps/painted_map.json"
@export var template_dir: String = "res://data/templates"
@export var tilings: Array[int] = [1, 2, 4]

const DOOMED: Color = Color(1.0, 0.25, 0.25, 0.5)
const BRUSH_OK: Color = Color(0.4, 1.0, 0.5)
const BRUSH_BAD: Color = Color(1.0, 0.4, 0.3)
const CLASS_FILL: Dictionary = {
	Materials.ColourClass.BROWN: Color(0.44, 0.31, 0.21),
	Materials.ColourClass.GREY: Color(0.40, 0.41, 0.44),
}

var world: World = null
var player: Player = null
var templates: Dictionary = {}

var editing: bool = false
var _ids: Array[String] = []
var _template_id: String = ""
var _size: int = 16
var _tiling: int = 0
var _problem: String = ""

var _undo: Array[MapEdit] = []
var _redo: Array[MapEdit] = []
var _stroke: MapEdit.Stroke = null
var _erasing: bool = false
var _last_stamp: Vector2i = Vector2i(-99999, -99999)
var _dirty: bool = false
var _note: String = ""

var _palette: PanelContainer = null

func _ready() -> void:
	var errors: PackedStringArray = []
	templates = TemplateLoader.load_dir(template_dir, errors)
	for e: String in errors:
		push_error(e)
	_ids.assign(templates.keys())
	_ids.sort()
	if not _ids.is_empty():
		_pick(_ids[0])
	_build_palette()

func _process(_delta: float) -> void:
	if _stroke != null and not _over_ui():
		_stamp()
	queue_redraw()

# --- input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if editing:
			_mouse_button(event as InputEventMouseButton)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: InputEventKey = event
	if k.keycode == KEY_TAB:
		_set_editing(not editing)
		return
	if not editing:
		return
	match k.keycode:
		KEY_Z when k.ctrl_pressed and k.shift_pressed: _do_redo()
		KEY_Z when k.ctrl_pressed: _do_undo()
		KEY_Y when k.ctrl_pressed: _do_redo()
		KEY_S when k.ctrl_pressed: _save()
		KEY_B: _bench()
		KEY_BRACKETLEFT: _set_size(maxi(1, _size >> 1))
		KEY_BRACKETRIGHT: _set_size(mini(256, _size << 1))
		KEY_1: _tiling = 0
		KEY_2: _tiling = 1
		KEY_3: _tiling = 2

func _mouse_button(m: InputEventMouseButton) -> void:
	if m.button_index != MOUSE_BUTTON_LEFT and m.button_index != MOUSE_BUTTON_RIGHT:
		return
	if m.pressed and not _over_ui():
		_stroke = MapEdit.Stroke.new()
		_erasing = m.button_index == MOUSE_BUTTON_RIGHT
		_last_stamp = Vector2i(-99999, -99999)
	elif not m.pressed:
		_end_stroke()

func _set_editing(on: bool) -> void:
	editing = on
	if not on:
		_end_stroke()
	if _palette != null:
		_palette.visible = on

# --- edits ---------------------------------------------------------------

## Alt places freely; otherwise the block lands on its own size lattice.
func _origin() -> Vector2i:
	var atom := Vector2i(floori(get_local_mouse_position().x), floori(get_local_mouse_position().y))
	return atom if Input.is_key_pressed(KEY_ALT) else PaintOps.snap(atom, _size)

func _footprint() -> Rect2i:
	return PaintOps.footprint(_origin(), _size, tilings[_tiling])

## Erasing around the character is fine; burying it is not (GDD 3.1 has no
## rule for a box that starts inside rock).
func _blocked_by_player(fp: Rect2i) -> bool:
	return player != null and fp.intersects(player.rect())

func _stamp() -> void:
	var fp: Rect2i = _footprint()
	if not _erasing and (_template_id == "" or _problem != "" or _blocked_by_player(fp)):
		return
	if fp.position == _last_stamp:
		return
	_last_stamp = fp.position
	var n: int = tilings[_tiling]
	var e: MapEdit = PaintOps.erase(world, fp.position, _size, n) if _erasing \
		else PaintOps.stamp(world, fp.position, _size, n, _template_id)
	if e.is_empty():
		return
	e.apply(world)
	_stroke.absorb(e)

func _end_stroke() -> void:
	if _stroke == null:
		return
	if not _stroke.is_empty():
		_push(_stroke.to_edit())
	_stroke = null

func _bench() -> void:
	if _ids.is_empty():
		return
	var at: Vector2i = _origin()
	if _blocked_by_player(Rect2i(at, Vector2i(_size * 2 * _ids.size(), _size))):
		_note = "bench would bury the character"
		return
	var e: MapEdit = PaintOps.bench(world, at, _size, _ids)
	e.apply(world)
	_push(e)

func _push(e: MapEdit) -> void:
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

## Saves the map as authored, not as dug: damage and reveal are stripped.
func _save() -> void:
	if FileAccess.file_exists(painted_path):
		DirAccess.copy_absolute(painted_path, painted_path + ".bak")
	if WorldSave.save_to_file(PaintOps.pristine(world), painted_path):
		_dirty = false
		_note = "saved %d blocks, undug" % world.blocks.size()

# --- brush ---------------------------------------------------------------

func _pick(id: String) -> void:
	_template_id = id
	var t: BlockTemplate = templates[id]
	if t.authored_size > 0:
		_size = t.authored_size
	_revalidate()

func _set_size(s: int) -> void:
	_size = s
	_revalidate()

## An override tree is only meaningful under some root sizes (GDD 4.7.1).
func _revalidate() -> void:
	_problem = ""
	if _template_id == "" or not templates.has(_template_id):
		return
	var problems: PackedStringArray = templates[_template_id].validate_for_root_size(_size)
	if not problems.is_empty():
		_problem = " ".join(problems)

func _tint(id: String) -> Color:
	var t: BlockTemplate = templates.get(id)
	if t == null:
		return Color.MAGENTA
	return PaintOps.authoring_tint(id, CLASS_FILL.get(t.colour_class, Color.MAGENTA))

# --- drawing (atom units; Stage scales to pixels) ------------------------

func _draw() -> void:
	if not editing or world == null:
		return
	var fp: Rect2i = _footprint()
	for b: BlockInstance in world.blocks_in(fp):
		draw_rect(Rect2(Vector2(b.origin), Vector2(b.size, b.size)), DOOMED, true)
	var edge: Color = BRUSH_OK
	if _problem != "" or (not _erasing and _blocked_by_player(fp)):
		edge = BRUSH_BAD
	var r := Rect2(Vector2(fp.position), Vector2(fp.size))
	draw_rect(r, edge, false, -1.0)
	var n: int = tilings[_tiling]
	for i: int in n + 1:  # the brush's own block seams
		var o: float = float(i * _size)
		var faint: Color = Color(edge.r, edge.g, edge.b, 0.35)
		draw_line(r.position + Vector2(o, 0), r.position + Vector2(o, r.size.y), faint, -1.0)
		draw_line(r.position + Vector2(0, o), r.position + Vector2(r.size.x, o), faint, -1.0)

# --- ui ------------------------------------------------------------------

func _build_palette() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_palette = PanelContainer.new()
	_palette.position = Vector2(2, 56)
	_palette.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_palette.add_child(box)
	for id: String in _ids:
		var b := Button.new()
		b.text = id
		b.focus_mode = Control.FOCUS_NONE  # else TAB cycles buttons instead of toggling edit
		b.add_theme_font_size_override("font_size", 8)
		b.add_theme_color_override("font_color", _tint(id).lightened(0.45))
		b.pressed.connect(_pick.bind(id))
		box.add_child(b)
	layer.add_child(_palette)

func _over_ui() -> bool:
	return _palette != null and _palette.visible \
		and _palette.get_global_rect().has_point(get_viewport().get_mouse_position())

## Two lines for Main's HUD.
func status() -> String:
	if not editing:
		return "TAB edit map"
	var atom := Vector2i(floori(get_local_mouse_position().x), floori(get_local_mouse_position().y))
	var under: BlockInstance = world.block_at(atom) if world != null else null
	var n: int = tilings[_tiling]
	var line: String = "EDIT %s size %d x%d   atom %d,%d   %s" % [
		_template_id if _template_id != "" else "(none)", _size, n * n, atom.x, atom.y,
		str(under) if under != null else "void"]
	if _problem != "":
		line += "   INVALID: " + _problem
	if _note != "":
		line += "   " + _note
	return "\n".join([
		line,
		"LMB paint  RMB erase  alt free  [ ] size  1/2/3 x1/x4/x16  B bench  ctrl+Z  ctrl+S%s" % [
			"   UNSAVED" if _dirty else ""],
	])
