## The hand-authored dev map and its loader. GDD 4.1.0, 4.1.2.
extends RefCounted

var runner: SceneTree

const MAP: String = "res://data/maps/dev_map.json"
const CELL: int = 16

var _world: World = null

func _templates() -> Dictionary:
	var errors: PackedStringArray = []
	var t: Dictionary = TemplateLoader.load_dir("res://data/templates", errors)
	runner.check(errors.is_empty(), "templates loaded: %s" % "\n".join(errors))
	return t

func _map() -> World:
	if _world == null:
		var errors: PackedStringArray = []
		_world = MapLoader.from_file(MAP, _templates(), errors)
		## The loader checks overlap on every insert, so a clean load is also
		## the proof that no two blocks occupy the same atom (GDD 4.1).
		runner.check(errors.is_empty(), "the dev map loaded clean: %s" % "\n".join(errors))
	return _world

## Cell (col, row) -> the atom at its top-left corner.
func _at(col: int, row: int) -> Vector2i:
	return Vector2i(col * CELL, row * CELL)

# ---------------------------------------------------------------- the map

func test_the_dev_map_is_the_gdd_4_1_0_dimensions() -> void:
	var w: World = _map()
	runner.check_eq(w.extent, Vector2i(1024, 1024), "1024 x 1024 atoms")
	runner.check_eq(w.extent.x / CELL, 64, "64 standard-block cells across")
	runner.check_eq(w.extent.y / Atoms.CHARACTER_HEIGHT, 128, "128 character-heights deep")

func test_every_block_is_snapped_and_inside_the_world() -> void:
	# Six thousand blocks, three claims each -- collected and reported once,
	# so the tally stays readable and a failure names the block that broke it.
	var w: World = _map()
	runner.check(w.blocks.size() > 4000, "the map is populated (%d blocks)" % w.blocks.size())

	var bad_size: PackedStringArray = []
	var unaligned: PackedStringArray = []
	var outside: PackedStringArray = []
	for b: BlockInstance in w.blocks:
		if not Atoms.is_valid_size(b.size):
			bad_size.append(str(b.origin))
		if b.origin.x % b.size != 0 or b.origin.y % b.size != 0:
			unaligned.append(str(b.origin))
		if not (w.in_bounds(b.origin) and w.in_bounds(b.origin + Vector2i(b.size - 1, b.size - 1))):
			outside.append(str(b.origin))

	runner.check(bad_size.is_empty(), "every size is a power of two: %s" % " ".join(bad_size))
	runner.check(unaligned.is_empty(), "every block is aligned to its own size: %s" % " ".join(unaligned))
	runner.check(outside.is_empty(), "every block is inside the world: %s" % " ".join(outside))

func test_the_sky_is_void_and_costs_nothing() -> void:
	# GDD 4.1.1 / invariant 4: '.' places NO BLOCK. There is no air to author.
	var w: World = _map()
	for col: int in [0, 31, 63]:
		runner.check(w.block_at(_at(col, 0)) == null, "row 0 col %d is sky" % col)
		runner.check(not w.is_solid(_at(col, 2)), "and nothing to stand on")
	runner.check(w.block_at(_at(0, 4)) != null, "but row 4 is ground")

# --------------------------------------------- the granularity dial (4.1.2)

func test_a_size_4_cell_places_sixteen_blocks() -> void:
	var w: World = _map()
	var cell: Vector2i = _at(11, 10)  # inside the rubble band, beside a boulder
	var seen: Dictionary = {}
	for by: int in 4:
		for bx: int in 4:
			var origin: Vector2i = cell + Vector2i(bx * 4, by * 4)
			var b: BlockInstance = w.block_at(origin)
			if b != null and b.origin == origin and b.size == 4:
				seen[b] = true
	runner.check_eq(seen.size(), 16,
		"sixteen distinct size-4 blocks tile the one cell, each at its own origin")

func test_the_rubble_and_the_fill_are_the_same_template() -> void:
	# GDD 4.1.2: 20 templates x 5 sizes is not 100 templates. It is 20
	# templates and a granularity dial. If the rubble needed its own file,
	# the size axis has been misunderstood.
	var w: World = _map()
	var rubble: BlockInstance = w.block_at(_at(11, 10))
	var fill: BlockInstance = w.block_at(_at(0, 20))
	runner.check_eq(rubble.template_id, "stone", "the rubble is stone")
	runner.check_eq(fill.template_id, "stone", "and so is the fill")
	runner.check_eq(rubble.size, 4, "at size 4")
	runner.check_eq(fill.size, 16, "and size 16 -- pebble versus boulder, one template")

# ------------------------------------------------- the packing test (GDD 6)

func test_the_boulder_is_embedded_in_rubble_of_its_own_colour() -> void:
	var w: World = _map()
	for col: int in [12, 28, 44]:
		var boulder: BlockInstance = w.block_at(_at(col, 10))
		runner.check_eq(boulder.template_id, "hard_stone", "a boulder sits at cell %d" % col)
		runner.check_eq(boulder.size, 16, "at full standard-block size")

		var before: BlockInstance = w.block_at(_at(col - 1, 10))
		runner.check_eq(before.size, 4, "with size-4 rubble leading up to it")
		runner.check_eq(
			w.template_for(before).colour_class,
			w.template_for(boulder).colour_class,
			"and the SAME COLOUR CLASS -- only the border says the wall is dear")

func test_boring_into_the_boulder_costs_what_the_rubble_did_not() -> void:
	# The point of the packing test: it reads cheap from outside, and it is not.
	# Air spent, tunnel behind you.
	var w: World = _map()
	var rubble_at: Vector2i = _at(11, 10) + Vector2i(0, 8)
	var boulder_at: Vector2i = _at(12, 10) + Vector2i(0, 8)

	var rubble: World.Dig = w.strike(rubble_at, 1.0)
	runner.check_eq(rubble.result.struck_size, 4, "the rubble is a size-4 node")

	for _i: int in 19:
		w.strike(boulder_at, 1.0)
	runner.check(w.block_at(boulder_at).root.is_leaf(),
		"nineteen strikes into the boulder and it has not moved")

# ----------------------------------------------------- the trap (GDD 6)

func test_every_sand_shelf_sits_over_something_to_fall_into() -> void:
	# Sand is CONSEQUENCE, not decoration -- a collapse has to drop you
	# somewhere. A sand cell with solid ground under it is a wasted trap.
	var w: World = _map()
	var shelves: int = 0
	var wasted: PackedStringArray = []
	for row: int in 64:
		for col: int in 64:
			var b: BlockInstance = w.block_at(_at(col, row))
			if b == null or b.template_id != "sand":
				continue
			## Look below the whole sand column for a void cell.
			var found: bool = false
			for below: int in range(row + 1, min(row + 5, 64)):
				var under: BlockInstance = w.block_at(_at(col, below))
				if under == null:
					found = true
					break
				if under.template_id != "sand":
					break
			if not found:
				wasted.append("(%d, %d)" % [col, row])
			shelves += 1
	runner.check(shelves > 0, "the map has sand in it at all (%d cells)" % shelves)
	runner.check(wasted.is_empty(), "no sand shelf has solid ground under it: %s" % " ".join(wasted))

func test_one_strike_on_the_shelf_opens_a_shaft() -> void:
	var w: World = _map()
	var shelf: Vector2i = _at(20, 18)
	runner.check_eq(w.block_at(shelf).template_id, "sand", "the shelf is sand")
	var dig: World.Dig = w.strike(shelf, 1.0)
	runner.check_eq(dig.result.broke, [16, 8, 4, 2] as Array[int],
		"and one strike from a 1 HP pickaxe takes it all the way down")
	runner.check(not w.is_solid(shelf), "the floor under that atom is gone")

# ---------------------------------------------------------- loader errors

func _errors_of(text: String) -> String:
	var errors: PackedStringArray = []
	var parsed: Variant = JSON.parse_string(text)
	runner.check(parsed != null, "the test fixture is valid JSON")
	MapLoader.from_dict(parsed, _templates(), errors)
	runner.check(not errors.is_empty(), "this map should have been rejected")
	return "\n".join(errors)

func test_a_grid_that_disagrees_with_the_extent_is_rejected() -> void:
	runner.check(_errors_of("""
	{ "extent_atoms": [64, 64], "cell_atoms": 16,
	  "legend": { ".": null },
	  "grid": ["....", "...."] }
	""").contains("rows"), "two rows where the extent wants four")

func test_a_short_row_is_rejected() -> void:
	runner.check(_errors_of("""
	{ "extent_atoms": [64, 64], "cell_atoms": 16,
	  "legend": { ".": null },
	  "grid": ["....", "....", "..", "...."] }
	""").contains("characters"), "a row that does not reach the right edge")

func test_a_character_missing_from_the_legend_is_rejected() -> void:
	runner.check(_errors_of("""
	{ "extent_atoms": [32, 32], "cell_atoms": 16,
	  "legend": { ".": null },
	  "grid": ["..", ".X"] }
	""").contains("legend"), "an unlegended character is a typo, not a guess")

func test_a_size_that_does_not_tile_the_cell_is_rejected() -> void:
	runner.check(_errors_of("""
	{ "extent_atoms": [32, 32], "cell_atoms": 16,
	  "legend": { ".": null, "x": { "template": "stone", "size": 32 } },
	  "grid": ["..", ".x"] }
	""").contains("tile"), "a size-32 block cannot live in a 16-atom cell")

func test_an_unknown_template_is_rejected_by_name() -> void:
	runner.check(_errors_of("""
	{ "extent_atoms": [32, 32], "cell_atoms": 16,
	  "legend": { ".": null, "x": { "template": "granite", "size": 16 } },
	  "grid": ["..", ".x"] }
	""").contains("granite"), "named, so you can find the typo")

func test_the_legend_validates_templates_against_their_painted_size() -> void:
	# Templates are size-agnostic (GDD 4.7.1: quad-paths are root-relative),
	# so this is the first place a template meets an actual block size --
	# and therefore the first place a too-deep path can be caught.
	var errors: PackedStringArray = []
	var res: TemplateLoader.Result = TemplateLoader.from_json_string("too_deep", """
	{ "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide" },
	  "overrides": { "Q0.Q1.Q2": { "resistance": 5 } } }
	""")
	runner.check(res.ok(), "the template itself is fine: %s" % res.describe())

	var templates: Dictionary = _templates()
	templates["too_deep"] = res.template
	MapLoader.from_dict(JSON.parse_string("""
	{ "extent_atoms": [32, 32], "cell_atoms": 16,
	  "legend": { ".": null, "x": { "template": "too_deep", "size": 4 } },
	  "grid": ["..", ".x"] }
	"""), templates, errors)
	runner.check(not errors.is_empty(), "but a 3-deep path under a size-4 root is not")

func test_a_clean_tiny_map_loads() -> void:
	var errors: PackedStringArray = []
	var w: World = MapLoader.from_dict(JSON.parse_string("""
	{ "extent_atoms": [32, 32], "cell_atoms": 16,
	  "legend": { ".": null,
	              "d": { "template": "honest_dirt", "size": 16 },
	              "r": { "template": "stone", "size": 4 } },
	  "grid": [".d", "r."] }
	"""), _templates(), errors)
	runner.check(errors.is_empty(), "loaded: %s" % "\n".join(errors))
	runner.check_eq(w.blocks.size(), 17, "one size-16 block plus sixteen size-4 ones")
	runner.check(w.block_at(Vector2i(0, 0)) == null, "and the void cell stayed void")
