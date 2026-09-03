## Phase-0 entry point: loads templates and the dev map, wires the player,
## ladders, camera and HUD. Tunables are @exports on this node and on
## Stage/Player, Stage/Terrain, Stage/Ladders in scenes/main.tscn.
extends Node2D

@export var template_dir: String = "res://data/templates"
@export var map_path: String = "res://data/maps/dev_map.json"
@export var px_per_atom: int = 3                       ## GDD 4.1.2 finding
@export var start_box: Vector2i = Vector2i(508, 56)    ## GDD 3.1.4
@export var surface_y: int = 64                        ## depth is measured from here

@onready var stage: Node2D = $Stage
@onready var terrain: Node2D = $Stage/Terrain
@onready var ladders_view: Node2D = $Stage/Ladders
@onready var player: Player = $Stage/Player
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $HUD/Label

var world: World = null
var ladders := Ladders.new()

func _ready() -> void:
	var errors: PackedStringArray = []
	var templates: Dictionary = TemplateLoader.load_dir(template_dir, errors)
	world = MapLoader.from_file(map_path, templates, errors)
	for e: String in errors:
		push_error(e)
	stage.scale = Vector2(px_per_atom, px_per_atom)
	terrain.world = world
	ladders_view.ladders = ladders
	ladders.unit = player.size
	player.world = world
	player.ladders = ladders
	player.box = start_box

func _process(_delta: float) -> void:
	var centre: Vector2 = player.centre() * float(px_per_atom)
	camera.position = centre.round()
	var span: Vector2 = get_viewport_rect().size / float(px_per_atom)
	terrain.view = Rect2(player.centre() - span * 0.5, span)
	hud.text = "\n".join([
		"box %s   depth %d character-heights   %s" % [
			player.box, (player.box.y + player.size - surface_y) / player.size,
			"on ladder" if player.on_ladder() else ("standing" if player.standing() else "falling"),
		],
		"coal %d   ladders placed %d   strikes %d" % [player.coal, ladders.units.size(), player.strikes],
		"arrows/WASD move + dig   space place ladder   R restart",
	])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_ladder"):
		if ladders.place(player.rect(), world).size == Vector2i.ZERO:
			print("cannot place a ladder here")
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_R:
		get_tree().reload_current_scene()
