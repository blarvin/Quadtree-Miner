## The character (GDD 3.1): an atom-stepped box. If the way is clear, move;
## if something blocks you, hit it. Position is in atoms; the parent Stage
## node scales atoms to pixels.
class_name Player
extends Node2D

@export_group("Body")
@export var size: int = 8              ## box edge in atoms
@export var radius: float = 4.0        ## drawn circle, atoms
@export var body_color: Color = Color(0.25, 0.55, 1.0)

@export_group("Movement (atoms per second)")
@export var walk_speed: float = 24.0
@export var fall_speed: float = 60.0
@export var climb_speed: float = 16.0
@export var air_control: bool = true   ## may walk sideways while falling

@export_group("Tool")
@export var strike_rate: float = 4.0   ## strikes per second while held
@export var tool_hp: float = 1.0       ## HP per strike (GDD 4.3.1)
@export var reach: int = 1             ## atoms past the box edge the tool line is drawn
@export var scan_reverse: bool = false ## bottom-to-top / right-to-left instead
@export var scan_restart_on_turn: bool = true
@export var tool_color: Color = Color(0.9, 0.9, 1.0)
@export var tool_width: float = 0.5    ## atoms
@export var impact_color: Color = Color(1.0, 0.85, 0.2)
@export var impact_fade: float = 0.3   ## seconds

var world: World = null
var ladders: Ladders = null
var box: Vector2i = Vector2i.ZERO      ## top-left, atoms
var facing: Vector2i = Vector2i.RIGHT
var coal: int = 0
var strikes: int = 0

var _move_t: float = 0.0
var _strike_t: float = 0.0
var _fall_t: float = 0.0
var _scan_i: int = 0
var _impact: Vector2i = Vector2i.ZERO
var _impact_age: float = 1e9
var _held: Array[Vector2i] = []        ## most recently pressed last

const DIRS: Dictionary = {
	"move_left": Vector2i.LEFT, "move_right": Vector2i.RIGHT,
	"move_up": Vector2i.UP, "move_down": Vector2i.DOWN,
}

func rect() -> Rect2i:
	return Rect2i(box, Vector2i(size, size))

func centre() -> Vector2:
	return Vector2(box) + Vector2(size, size) * 0.5

func on_ladder() -> bool:
	return ladders.overlaps(rect())

func standing() -> bool:
	return _any_solid(_edge(Vector2i.DOWN))

func _process(delta: float) -> void:
	_impact_age += delta
	var dir: Vector2i = _held_dir()
	if dir == Vector2i.ZERO:
		_move_t = 0.0
		_strike_t = 0.0
	else:
		if dir != facing:
			facing = dir
			if scan_restart_on_turn:
				_scan_i = 0
		if _blocked(dir):
			_move_t = 0.0
			_strike_t += delta
			while _strike_t >= 1.0 / strike_rate:
				_strike_t -= 1.0 / strike_rate
				_strike(dir)
		elif _may_step(dir):
			_strike_t = 0.0
			var speed: float = climb_speed if dir.y != 0 and on_ladder() else walk_speed
			_move_t += delta
			while _move_t >= 1.0 / speed:
				_move_t -= 1.0 / speed
				if _blocked(dir) or not _may_step(dir):
					break
				box += dir

	if not on_ladder() and not standing():
		_fall_t += delta
		while _fall_t >= 1.0 / fall_speed:
			_fall_t -= 1.0 / fall_speed
			if standing() or on_ladder():
				break
			box += Vector2i.DOWN
	else:
		_fall_t = 0.0

	position = Vector2(box)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	for action: String in DIRS:
		if event.is_action_pressed(action):
			_held.erase(DIRS[action])
			_held.append(DIRS[action])
			# A tap acts immediately; holding continues at the rate.
			_move_t = 1.0 / walk_speed
			_strike_t = 1.0 / strike_rate
		elif event.is_action_released(action):
			_held.erase(DIRS[action])

func _held_dir() -> Vector2i:
	for i: int in range(_held.size() - 1, -1, -1):
		if Input.is_action_pressed(DIRS.find_key(_held[i])):
			return _held[i]
	return Vector2i.ZERO

## The atoms just outside the box on side `dir`, in scan order (GDD 4.3.2).
func _edge(dir: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i: int in size:
		match dir:
			Vector2i.LEFT: out.append(Vector2i(box.x - 1, box.y + i))
			Vector2i.RIGHT: out.append(Vector2i(box.x + size, box.y + i))
			Vector2i.UP: out.append(Vector2i(box.x + i, box.y - 1))
			Vector2i.DOWN: out.append(Vector2i(box.x + i, box.y + size))
	if scan_reverse:
		out.reverse()
	return out

func _any_solid(atoms: Array[Vector2i]) -> bool:
	for a: Vector2i in atoms:
		if not world.in_bounds(a) or world.is_solid(a):
			return true
	return false

func _blocked(dir: Vector2i) -> bool:
	return _any_solid(_edge(dir))

## Clear ahead; is the step allowed? Up needs a ladder at the destination.
## Down off a ladder is gravity's job. Sideways while falling is air control.
func _may_step(dir: Vector2i) -> bool:
	var dest := Rect2i(box + dir, Vector2i(size, size))
	if dir == Vector2i.UP:
		return on_ladder() and ladders.overlaps(dest)
	if dir == Vector2i.DOWN:
		return on_ladder()
	return air_control or standing() or on_ladder()

## One strike at one atom: the next obstructing atom in the scan cycle.
func _strike(dir: Vector2i) -> void:
	var targets: Array[Vector2i] = []
	for a: Vector2i in _edge(dir):
		if world.in_bounds(a) and world.is_solid(a):
			targets.append(a)
	if targets.is_empty():
		return
	var at: Vector2i = targets[_scan_i % targets.size()]
	_scan_i += 1
	strikes += 1
	var dig: World.Dig = world.strike(at, tool_hp)
	_impact = at
	_impact_age = 0.0
	if dig.hit():
		for y: Strike.Yield in dig.result.yields:
			if y.drop.material == Materials.Id.COAL:
				coal += y.count

func _draw() -> void:
	var c := Vector2(size, size) * 0.5
	draw_circle(c, radius, body_color)
	draw_line(c, c + Vector2(facing) * (radius + float(reach)), tool_color, tool_width)
	if _impact_age < impact_fade:
		var col: Color = impact_color
		col.a = 1.0 - _impact_age / impact_fade
		draw_rect(Rect2(Vector2(_impact - box), Vector2.ONE), col, true)
