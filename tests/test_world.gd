## Spatial index, strike routing, save round trip (GDD 4.1, 5.1).
extends RefCounted

var runner: SceneTree

const SAVE_PATH: String = "user://test_world_roundtrip.json"

func _templates() -> Dictionary:
	var errors: PackedStringArray = []
	var t: Dictionary = TemplateLoader.load_dir("res://data/templates", errors)
	runner.check(errors.is_empty(), "templates loaded: %s" % "\n".join(errors))
	return t

func _world() -> World:
	var w := World.new()
	w.extent = Vector2i(64, 64)
	w.templates = _templates()
	w.add(BlockInstance.new(Vector2i(0, 0), 16, "honest_dirt"))
	w.add(BlockInstance.new(Vector2i(32, 0), 32, "hard_stone"))
	w.add(BlockInstance.new(Vector2i(16, 16), 4, "stone"))
	return w

func test_block_at_and_void() -> void:
	var w: World = _world()
	runner.check_eq(w.block_at(Vector2i(15, 15)).template_id, "honest_dirt", "inside the dirt")
	runner.check_eq(w.block_at(Vector2i(17, 17)).template_id, "stone", "the size-4 pebble")
	runner.check_eq(w.block_at(Vector2i(60, 30)).template_id, "hard_stone", "a size-32 spans index cells")
	runner.check(w.block_at(Vector2i(20, 4)) == null, "the gap is void")
	runner.check(w.block_at(Vector2i(9999, 9999)) == null and not w.in_bounds(Vector2i(-1, 0)), "outside is void")

func test_is_solid_sees_holes_inside_blocks() -> void:
	var w: World = _world()
	for _i: int in 5:
		w.strike(Vector2i.ZERO, 1.0)
	runner.check(w.block_at(Vector2i.ZERO) != null, "the block is still there")
	runner.check(not w.is_solid(Vector2i.ZERO), "but this atom is mined")
	runner.check(w.is_solid(Vector2i(15, 15)), "and the far corner is not")

func test_blocks_never_overlap() -> void:
	var w: World = _world()
	runner.check(w.find_overlap(Rect2i(8, 8, 16, 16)) != null, "overlap detected")
	runner.check(w.find_overlap(Rect2i(20, 0, 8, 8)) == null, "clear space is clear")

func test_strikes_route_in_local_coordinates() -> void:
	var w: World = _world()
	var dig: World.Dig = w.strike(Vector2i(19, 19), 1.0)
	runner.check(dig.hit() and dig.block.template_id == "stone", "hit the pebble")
	runner.check_eq(dig.block.root.damage, 1.0, "at its root")
	runner.check(not w.strike(Vector2i(20, 4), 1.0).hit(), "void hits nothing")

func test_mining_a_root_removes_the_block() -> void:
	var w: World = _world()
	var errors: PackedStringArray = []
	w.templates["vanish"] = TemplateLoader.from_json_string("vanish",
		'{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "mine", "drop": null}}', errors)
	w.add(BlockInstance.new(Vector2i(0, 32), 16, "vanish"))
	var dig: World.Dig = w.strike(Vector2i(5, 40), 1.0)
	runner.check(dig.block_removed, "the block was removed")
	runner.check(w.block_at(Vector2i(5, 40)) == null and w.blocks.size() == 3, "and the cell is void")

func test_yields_come_back_in_world_coordinates() -> void:
	var w := World.new()
	w.extent = Vector2i(64, 64)
	w.templates = _templates()
	w.add(BlockInstance.new(Vector2i(32, 32), 16, "gift_stone"))
	var dig: World.Dig = null
	for _i: int in 9:
		dig = w.strike(Vector2i(40, 36), 1.0)  # Q1.Q2.Q0 of the gift: coal
	runner.check_eq(dig.result.yields.size(), 1, "coal yielded")
	runner.check_eq(dig.world_origin_of(dig.result.yields[0]), Vector2i(40, 36), "at the world position")

func test_save_round_trip() -> void:
	var w: World = _world()
	runner.check_eq(WorldSave.to_dict(w)["blocks"][0]["root"], {}, "an untouched block saves as {}")
	for _i: int in 5:
		w.strike(Vector2i.ZERO, 1.0)
	w.strike(Vector2i(60, 30), 1.0)
	runner.check(WorldSave.save_to_file(w, SAVE_PATH), "saved")

	var errors: PackedStringArray = []
	var back: World = WorldSave.load_from_file(SAVE_PATH, w.templates, errors)
	runner.check(errors.is_empty(), "loaded: %s" % "\n".join(errors))
	runner.check_eq(WorldSave.to_dict(back), WorldSave.to_dict(w), "structurally identical")
	runner.check(not back.is_solid(Vector2i.ZERO), "the mined atom is still void")
	runner.check(back.block_at(Vector2i.ZERO).root.revealed, "revealed survived")
	runner.check_eq(back.block_at(Vector2i(60, 30)).root.damage, 1.0, "damage survived")
	runner.check_eq(back.block_at(Vector2i.ZERO).root.children[0].size, 8, "node size derived on load")
	runner.check(not WorldSave.to_json(w).contains('"size": 8'), "and never written")
	DirAccess.remove_absolute(SAVE_PATH)

func test_bad_saves_are_refused() -> void:
	var errors: PackedStringArray = []
	WorldSave.from_dict({"version": 99, "blocks": []}, _templates(), errors)
	runner.check(not errors.is_empty(), "future version refused")
	errors.clear()
	WorldSave.from_dict({"version": 1, "blocks": [{"origin": [0, 0], "size": 16, "template": "nope"}]}, _templates(), errors)
	runner.check(not errors.is_empty(), "unknown template refused")
