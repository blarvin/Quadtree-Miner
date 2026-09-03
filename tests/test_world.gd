## The block index, void semantics, and persistence. GDD 4.1, 4.1.1, 5.1, 5.2.
extends RefCounted

var runner: SceneTree

const SAVE_PATH: String = "user://test_world_roundtrip.json"

func _templates() -> Dictionary:
	var errors: PackedStringArray = []
	var t: Dictionary = TemplateLoader.load_dir("res://data/templates", errors)
	runner.check(errors.is_empty(), "templates loaded: %s" % "\n".join(errors))
	return t

## Three blocks with a deliberate GAP between the first two (GDD 4.1: blocks
## need not be contiguous), and one size-4 pebble.
func _world() -> World:
	var w := World.new()
	w.templates = _templates()
	w.add(BlockInstance.new(Vector2i(0, 0), 16, "honest_dirt"))
	w.add(BlockInstance.new(Vector2i(32, 0), 16, "hard_stone"))
	w.add(BlockInstance.new(Vector2i(16, 16), 4, "stone"))
	return w

# ------------------------------------------------------- void is an absence

func test_a_gap_is_void_not_an_air_block() -> void:
	# GDD 4.1.1 / invariant 4. "Is this cell empty?" = "does any block cover
	# it?" -> for a gap, no. There is no void object to author or store.
	var w: World = _world()
	runner.check(w.block_at(Vector2i(20, 4)) == null, "the gap between blocks is void")
	runner.check(not w.is_solid(Vector2i(20, 4)), "and nothing is there to stand on")
	runner.check_eq(w.blocks.size(), 3, "the gap cost no storage at all")

func test_out_of_bounds_is_void_too() -> void:
	var w: World = _world()
	runner.check(w.block_at(Vector2i(9999, 9999)) == null, "past the edge is void")
	runner.check(not w.in_bounds(Vector2i(-1, 0)), "and out of bounds")

func test_block_at_finds_the_covering_block() -> void:
	var w: World = _world()
	runner.check_eq(w.block_at(Vector2i(0, 0)).template_id, "honest_dirt", "top-left corner")
	runner.check_eq(w.block_at(Vector2i(15, 15)).template_id, "honest_dirt", "bottom-right corner")
	runner.check_eq(w.block_at(Vector2i(32, 0)).template_id, "hard_stone", "the next block over")
	runner.check_eq(w.block_at(Vector2i(17, 17)).template_id, "stone", "the size-4 pebble")
	runner.check(w.block_at(Vector2i(21, 17)) == null, "and just past the pebble is void")

func test_is_solid_is_not_the_same_as_block_at() -> void:
	# A block that has been dug into HAS HOLES. Coverage is not solidity, and
	# collision wants solidity.
	var w: World = _world()
	var at := Vector2i(0, 0)
	for _i: int in 5:
		w.strike(at, 1.0)  # the GDD 4.5 five-strike sequence, mining a size-2

	runner.check(w.block_at(at) != null, "the block is still there")
	runner.check(not w.is_solid(at), "but this atom is not")
	runner.check(w.is_solid(Vector2i(15, 15)), "while the far corner still is")

# -------------------------------------------------------------- placement

func test_blocks_never_overlap() -> void:
	var w: World = _world()
	runner.check(w.find_overlap(Rect2i(Vector2i(8, 8), Vector2i(16, 16))) != null,
		"an overlapping placement is detectable before it is made")
	runner.check(w.find_overlap(Rect2i(Vector2i(20, 0), Vector2i(4, 4))) == null,
		"and a placement in the gap is fine")

func test_a_boulder_spanning_index_cells_is_found_everywhere() -> void:
	# The cell index is 16 atoms; a size-32 root spans four cells. Nothing
	# about the quadtree depends on that -- it is a lookup detail (GDD 4.2:
	# boulders are free, the tree simply starts higher).
	var w := World.new()
	w.templates = _templates()
	w.add(BlockInstance.new(Vector2i(64, 64), 32, "hard_stone"))
	for corner: Vector2i in [Vector2i(64, 64), Vector2i(95, 64), Vector2i(64, 95), Vector2i(95, 95)]:
		runner.check(w.block_at(corner) != null, "the boulder is found at %s" % corner)
	runner.check(w.block_at(Vector2i(96, 96)) == null, "and not one atom past it")

# ---------------------------------------------------------------- digging

func test_strikes_route_to_the_right_block_in_local_coordinates() -> void:
	var w: World = _world()
	# (33, 1) is one atom in from the hard_stone block's own origin.
	var dig: World.Dig = w.strike(Vector2i(33, 1), 1.0)
	runner.check(dig.hit(), "the blow landed")
	runner.check_eq(dig.block.template_id, "hard_stone", "on the hard stone")
	runner.check_eq(dig.block.root.damage, 1.0, "and 1 of its 20 HP went in")
	runner.check_eq(w.block_at(Vector2i(0, 0)).root.damage, 0.0,
		"the neighbouring block did not feel it")

func test_striking_void_hits_nothing() -> void:
	var w: World = _world()
	var dig: World.Dig = w.strike(Vector2i(20, 4), 1.0)
	runner.check(not dig.hit(), "nothing to hit in a gap")
	runner.check(dig.block == null, "and no block to blame")

func test_yields_come_back_in_world_coordinates() -> void:
	var w: World = _world()
	w.add(BlockInstance.new(Vector2i(64, 0), 16, "gift_stone"))
	# 3 + 2 + 2 + 2 strikes into the coal core at block-local (8, 4).
	var dig: World.Dig = null
	for _i: int in 9:
		dig = w.strike(Vector2i(64 + 8, 0 + 4), 1.0)

	runner.check_eq(dig.result.yields.size(), 1, "the core paid out")
	var y: Strike.Yield = dig.result.yields[0]
	runner.check_eq(y.node_origin, Vector2i(8, 4), "the yield's own origin is block-local")
	runner.check_eq(dig.world_origin_of(y), Vector2i(72, 4), "and the World places it")

func test_mining_a_root_removes_the_block_and_the_cell_becomes_void() -> void:
	# GDD 4.1.1: void is the absence of a block, consistently at every scale.
	# No air block is spawned in its place.
	var w := World.new()
	w.templates = _templates()
	w.add(BlockInstance.new(Vector2i(0, 0), 4, "sand"))
	runner.check_eq(w.blocks.size(), 1, "one sand pebble")

	# sand resists 0.25 and passes down: 1 HP bores clean through a size-4.
	var dig: World.Dig = w.strike(Vector2i(0, 0), 1.0)
	runner.check(dig.hit(), "the strike landed")
	runner.check(not dig.block_removed, "a size-4 root is not destroyed by boring a shaft")
	runner.check(not w.is_solid(Vector2i(0, 0)), "but that column is gone")
	runner.check(w.block_at(Vector2i(0, 0)) != null, "and the block itself remains")

func test_a_destroyed_root_leaves_no_trace_in_the_index() -> void:
	var w := World.new()
	w.templates = _templates()
	var res: TemplateLoader.Result = TemplateLoader.from_json_string("vanishing", """
	{ "material": "dirt",
	  "default_rule": { "resistance": 1, "on_break": "mine", "drop": null } }
	""")
	runner.check(res.ok(), "the vanishing template parsed: %s" % res.describe())
	w.templates["vanishing"] = res.template
	w.add(BlockInstance.new(Vector2i(0, 0), 16, "vanishing"))

	var dig: World.Dig = w.strike(Vector2i(5, 5), 1.0)
	runner.check(dig.block_removed, "the whole block went")
	runner.check_eq(w.blocks.size(), 0, "the flat array is empty")
	runner.check(w.block_at(Vector2i(5, 5)) == null, "and the index agrees it is void")
	runner.check(w.find_overlap(Rect2i(Vector2i(0, 0), Vector2i(16, 16))) == null,
		"and nothing is left behind in the cell index")

# ------------------------------------------------------------- persistence

func test_an_untouched_world_saves_as_one_node_per_block() -> void:
	# GDD 4.7.1: the saved tree is only ever as deep as the player has dug.
	# That is what makes persisting damage and reveal cheap (4.6.1).
	var w: World = _world()
	var d: Dictionary = WorldSave.to_dict(w)
	runner.check_eq(w.node_count(), 3, "three blocks, three nodes")
	for b: Variant in d["blocks"]:
		runner.check((b["root"] as Dictionary).is_empty(),
			"an unstruck block serialises as {} -- no damage, no reveal, no children")

func test_node_size_is_never_written() -> void:
	# GDD 5.1 / invariant 11. An unstorable value cannot be an invalid one, so
	# this is the test that keeps the derived cache honest.
	var w: World = _world()
	for _i: int in 5:
		w.strike(Vector2i(0, 0), 1.0)
	var text: String = WorldSave.to_json(w)

	var nodes: Dictionary = WorldSave.to_dict(w)["blocks"][0]["root"]
	runner.check(not nodes.has("size"), "no size on the root node")
	runner.check(not nodes.has("s"), "under any spelling")
	runner.check(text.contains("\"size\""),
		"the BLOCK still records its size -- that one is authored, not derived")

func test_dig_save_load_is_structurally_identical() -> void:
	var templates: Dictionary = _templates()
	var before := World.new()
	before.templates = templates
	before.add(BlockInstance.new(Vector2i(0, 0), 16, "liar_dirt"))
	before.add(BlockInstance.new(Vector2i(16, 0), 16, "gift_stone"))

	# Carve a wandering front: several points, several depths, one refusal.
	for _i: int in 5:
		before.strike(Vector2i(0, 0), 1.0)
	for _i: int in 3:
		before.strike(Vector2i(0, 8), 1.0)   # the liar's Q2 -- absorbs, never breaks
	for _i: int in 9:
		before.strike(Vector2i(16 + 8, 4), 1.0)

	var errors: PackedStringArray = []
	var after: World = WorldSave.from_json(WorldSave.to_json(before), templates, errors)
	runner.check(errors.is_empty(), "the save reloaded clean: %s" % "\n".join(errors))

	runner.check_eq(after.blocks.size(), before.blocks.size(), "same block count")
	runner.check_eq(after.node_count(), before.node_count(), "same node count")
	for i: int in before.blocks.size():
		var b: BlockInstance = before.blocks[i]
		var a: BlockInstance = after.blocks[i]
		runner.check_eq(a.origin, b.origin, "block %d kept its origin" % i)
		runner.check_eq(a.size, b.size, "and its size")
		runner.check_eq(a.template_id, b.template_id, "and its template")
		_check_same(a.root, b.root, "block %d root" % i)

func test_damage_and_reveal_survive_the_round_trip() -> void:
	# GDD 4.6.1 / invariant 7: fractures never heal, across sessions too. The
	# player's accumulated fractures are a map of their own knowledge.
	var templates: Dictionary = _templates()
	var before := World.new()
	before.templates = templates
	before.add(BlockInstance.new(Vector2i(0, 0), 16, "honest_dirt"))
	before.strike(Vector2i(0, 0), 1.0)  # revealed, damaged, NOT broken

	var errors: PackedStringArray = []
	var after: World = WorldSave.from_json(WorldSave.to_json(before), templates, errors)
	var root: BlockNode = after.blocks[0].root
	runner.check_eq(root.damage, 1.0, "the half-struck block remembers its damage")
	runner.check(root.revealed, "and that it has been seen")
	runner.check(root.is_leaf(), "and that it has not been broken")

func test_a_mined_quadrant_survives_as_void_not_as_a_leaf() -> void:
	# The one thing the schema had to settle: a null SLOT is a mined quadrant,
	# an absent children array is a node that never subdivided. If the save
	# blurred them, holes would heal on load.
	var templates: Dictionary = _templates()
	var before := World.new()
	before.templates = templates
	before.add(BlockInstance.new(Vector2i(0, 0), 16, "honest_dirt"))
	for _i: int in 5:
		before.strike(Vector2i(0, 0), 1.0)
	runner.check(not before.is_solid(Vector2i(0, 0)), "a size-2 hole was dug")

	var errors: PackedStringArray = []
	var after: World = WorldSave.from_json(WorldSave.to_json(before), templates, errors)
	runner.check(not after.is_solid(Vector2i(0, 0)), "and it is still a hole after loading")
	runner.check(after.is_solid(Vector2i(2, 0)), "while its sibling is still solid")

func test_the_round_trip_goes_through_a_real_file() -> void:
	var templates: Dictionary = _templates()
	var w: World = _world()
	for _i: int in 5:
		w.strike(Vector2i(0, 0), 1.0)
	runner.check(WorldSave.save_to_file(w, SAVE_PATH), "wrote the save")

	var errors: PackedStringArray = []
	var loaded: World = WorldSave.load_from_file(SAVE_PATH, templates, errors)
	runner.check(errors.is_empty(), "read it back: %s" % "\n".join(errors))
	runner.check_eq(loaded.node_count(), w.node_count(), "same tree came back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func test_a_save_naming_an_unknown_template_is_rejected_loudly() -> void:
	# Rules are template-authoritative (4.7.2), so a missing template is a
	# world whose behaviour cannot be determined. Better to say so.
	var errors: PackedStringArray = []
	var w: World = WorldSave.from_json("""
	{ "version": 1, "extent": [64, 64],
	  "blocks": [ { "origin": [0, 0], "size": 16, "template": "granite", "root": {} } ] }
	""", _templates(), errors)
	runner.check(not errors.is_empty(), "the unknown template was reported")
	runner.check(errors[0].contains("granite"), "by name")
	runner.check_eq(w.blocks.size(), 0, "and the block was not placed")

func test_a_future_save_version_is_refused() -> void:
	var errors: PackedStringArray = []
	WorldSave.from_json("""{ "version": 99, "blocks": [] }""", _templates(), errors)
	runner.check(not errors.is_empty(), "a version we do not understand is not guessed at")

# --------------------------------------------------------------------------

func _check_same(a: BlockNode, b: BlockNode, where: String) -> void:
	runner.check_eq(a.size, b.size, "%s: size recomputed correctly" % where)
	runner.check_eq(a.damage, b.damage, "%s: damage" % where)
	runner.check_eq(a.revealed, b.revealed, "%s: revealed" % where)
	runner.check_eq(a.children.size(), b.children.size(), "%s: child count" % where)
	for i: int in b.children.size():
		var bc: BlockNode = b.children[i]
		var ac: BlockNode = a.children[i]
		runner.check_eq(ac == null, bc == null, "%s Q%d: void-ness matches" % [where, i])
		if bc != null and ac != null:
			_check_same(ac, bc, "%s Q%d" % [where, i])
