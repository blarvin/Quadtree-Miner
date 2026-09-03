## Ladder placement and stacking (GDD 3.1.1).
extends RefCounted

var runner: SceneTree

func _world() -> World:
	var w := World.new()
	w.extent = Vector2i(64, 64)
	var errors: PackedStringArray = []
	w.templates = TemplateLoader.load_dir("res://data/templates", errors)
	w.add(BlockInstance.new(Vector2i(0, 48), 16, "stone"))  # floor at y 48
	return w

func test_first_ladder_goes_where_the_body_is() -> void:
	var l := Ladders.new()
	runner.check_eq(l.place(Rect2i(3, 40, 8, 8), _world()), Rect2i(3, 40, 8, 8), "placed at the body")

func test_a_second_ladder_snaps_and_stacks() -> void:
	var l := Ladders.new()
	var w: World = _world()
	l.place(Rect2i(3, 40, 8, 8), w)
	runner.check_eq(l.place(Rect2i(5, 33, 8, 8), w), Rect2i(3, 32, 8, 8), "body near the top: stacks above, same column")
	runner.check_eq(l.place(Rect2i(5, 33, 8, 8), w), Rect2i(), "occupied: refused")
	runner.check_eq(l.place(Rect2i(3, 46, 8, 8), w), Rect2i(), "below would be inside stone: refused")

func test_ladders_need_void() -> void:
	var l := Ladders.new()
	runner.check_eq(l.place(Rect2i(0, 44, 8, 8), _world()), Rect2i(), "overlaps the floor")
	runner.check_eq(l.place(Rect2i(-2, 0, 8, 8), _world()), Rect2i(), "out of bounds")
