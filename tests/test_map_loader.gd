## The dev map and the map format (GDD 4.1.0, 4.1.2).
extends RefCounted

var runner: SceneTree

const MAP: String = "res://data/maps/dev_map.json"
const CELL: int = 16

var _world: World = null
var _tpls: Dictionary = {}

func _templates() -> Dictionary:
	if _tpls.is_empty():
		var errors: PackedStringArray = []
		_tpls = TemplateLoader.load_dir("res://data/templates", errors)
		runner.check(errors.is_empty(), "templates loaded: %s" % "\n".join(errors))
	return _tpls

func _map() -> World:
	if _world == null:
		var errors: PackedStringArray = []
		_world = MapLoader.from_file(MAP, _templates(), errors)
		runner.check(errors.is_empty(), "the dev map loaded clean: %s" % "\n".join(errors))
	return _world

func _at(col: int, row: int) -> Vector2i:
	return Vector2i(col * CELL, row * CELL)

func test_the_dev_map_loads_at_gdd_dimensions() -> void:
	var w: World = _map()
	runner.check_eq(w.extent, Vector2i(1024, 1024), "1024 x 1024 atoms")
	runner.check(w.blocks.size() > 4000, "populated (%d blocks)" % w.blocks.size())
	runner.check_eq(w.node_count(), w.blocks.size(), "untouched: one node per block")
	for b: BlockInstance in w.blocks:
		if b.origin.x % b.size != 0 or b.origin.y % b.size != 0 or not w.in_bounds(b.origin + Vector2i(b.size - 1, b.size - 1)):
			runner.check(false, "block at %s is misaligned or outside" % b.origin)
			break

func test_the_sky_is_void() -> void:
	runner.check(_map().block_at(_at(10, 2)) == null, "row 2 is sky")
	runner.check(_map().block_at(_at(10, 4)) != null, "row 4 is ground")

## A legend entry smaller than its cell tiles the cell (GDD 4.1.2). Rubble size
## is an authoring dial, so the expectation comes from the map, not from here.
func test_a_sub_cell_legend_entry_tiles_its_cell() -> void:
	var w: World = _map()
	var legend: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP))["legend"]
	var size: int = int(legend["r"]["size"])
	var per_edge: int = CELL / size
	var seen: Dictionary = {}
	for y: int in per_edge:
		for x: int in per_edge:
			var b: BlockInstance = w.block_at(_at(5, 10) + Vector2i(x * size, y * size))
			runner.check(b != null and b.size == size and b.template_id == "stone",
				"rubble at (%d,%d) is a size-%d stone" % [x, y, size])
			seen[b] = true
	runner.check_eq(seen.size(), per_edge * per_edge, "%d distinct blocks" % (per_edge * per_edge))
	var boulder: BlockInstance = w.block_at(_at(12, 10))
	runner.check(boulder.size == 16 and boulder.template_id == "hard_stone", "the boulder at cell (12, 10)")

func test_every_sand_shelf_has_void_beneath_it() -> void:
	var w: World = _map()
	var shelves: int = 0
	for row: int in 64:
		for col: int in 64:
			var b: BlockInstance = w.block_at(_at(col, row))
			if b == null or b.template_id != "sand":
				continue
			shelves += 1
			var found: bool = false
			for below: int in range(row + 1, min(row + 5, 64)):
				var under: BlockInstance = w.block_at(_at(col, below))
				if under == null:
					found = true
					break
				if under.template_id != "sand":
					break
			runner.check(found, "sand at (%d, %d) has somewhere to fall" % [col, row])
	runner.check(shelves > 0, "the map has sand")

func _errors_of(text: String) -> String:
	var errors: PackedStringArray = []
	MapLoader.from_dict(JSON.parse_string(text), _templates(), errors)
	runner.check(not errors.is_empty(), "this map should have been rejected")
	return "\n".join(errors)

func test_rejections() -> void:
	runner.check(_errors_of('{"extent_atoms": [64, 64], "cell_atoms": 16, "legend": {".": null}, "grid": ["....", "...."]}')
		.contains("rows"), "row count")
	runner.check(_errors_of('{"extent_atoms": [64, 64], "cell_atoms": 16, "legend": {".": null}, "grid": ["....", "...", "....", "...."]}')
		.contains("characters"), "short row")
	runner.check(_errors_of('{"extent_atoms": [64, 64], "cell_atoms": 16, "legend": {".": null}, "grid": ["....", "..x.", "....", "...."]}')
		.contains("legend"), "unknown character")
	runner.check(_errors_of('{"extent_atoms": [64, 64], "cell_atoms": 16, "legend": {"d": {"template": "honest_dirt", "size": 32}}, "grid": ["dddd", "dddd", "dddd", "dddd"]}')
		.contains("tile"), "size larger than the cell")
	runner.check(_errors_of('{"extent_atoms": [64, 64], "cell_atoms": 16, "legend": {"d": {"template": "nope", "size": 16}}, "grid": ["dddd", "dddd", "dddd", "dddd"]}')
		.contains("unknown template"), "unknown template")
	runner.check(_errors_of('{"extent_atoms": [64, 64], "legend": {".": null}, "grid": ["....", "....", "....", "...."]}')
		.contains("cell_atoms"), "cell_atoms is required")

func test_a_clean_tiny_map_loads() -> void:
	var errors: PackedStringArray = []
	var w: World = MapLoader.from_dict(JSON.parse_string(
		'{"extent_atoms": [32, 32], "cell_atoms": 16, "legend": {".": null, "r": {"template": "stone", "size": 4}}, "grid": ["..", ".r"]}'),
		_templates(), errors)
	runner.check(errors.is_empty(), "clean: %s" % "\n".join(errors))
	runner.check_eq(w.blocks.size(), 16, "one rubble cell")
