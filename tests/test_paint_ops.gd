## The painter's edit ops (GDD 6, Phase 1 authoring). These guard against
## losing authored work: the overlap rule, undo, and the flat-file round trip.
extends RefCounted

var runner: SceneTree

const TEMPLATE_DIR: String = "res://data/templates"
const A: String = "honest_dirt"
const B: String = "stone"

var _tpls: Dictionary = {}

func _templates() -> Dictionary:
	if _tpls.is_empty():
		var errors: PackedStringArray = []
		_tpls = TemplateLoader.load_dir(TEMPLATE_DIR, errors)
		runner.check(errors.is_empty(), "templates loaded: %s" % "\n".join(errors))
	return _tpls

func _world() -> World:
	var w := World.new()
	w.templates = _templates()
	w.extent = Vector2i(256, 256)
	return w

func _origins(w: World) -> Array:
	var out: Array = []
	for b: BlockInstance in w.blocks:
		out.append([b.origin, b.size, b.template_id])
	out.sort()
	return out

func test_a_stamp_places_n_squared_blocks() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(0, 0), 4, 4, A).apply(w)
	runner.check_eq(w.blocks.size(), 16, "4x4 tiling of size 4 is sixteen blocks")
	runner.check_eq(w.block_at(Vector2i(15, 15)).origin, Vector2i(12, 12), "covers 16 atoms")
	runner.check(w.block_at(Vector2i(16, 0)) == null, "and no more")

## The overlap rule (GDD 4.1.1): touched blocks die whole, leaving void.
func test_a_stamp_deletes_every_block_it_touches_whole() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(0, 0), 16, 1, A).apply(w)
	runner.check_eq(w.blocks.size(), 1, "one size-16 block")

	PaintOps.stamp(w, Vector2i(0, 0), 4, 1, B).apply(w)
	runner.check_eq(w.blocks.size(), 1, "the size-16 block is gone, not split")
	runner.check_eq(w.block_at(Vector2i(0, 0)).template_id, B, "the new block is there")
	runner.check(w.block_at(Vector2i(8, 8)) == null, "what it covered is now void")

func test_free_placement_is_allowed() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(3, 7), 4, 1, A).apply(w)
	runner.check_eq(w.block_at(Vector2i(3, 7)).origin, Vector2i(3, 7), "unaligned origin kept")
	runner.check(w.block_at(Vector2i(2, 7)) == null, "and it is only 4 wide")

func test_snap_floors_towards_negative() -> void:
	runner.check_eq(PaintOps.snap(Vector2i(19, 33), 16), Vector2i(16, 32), "snaps down")
	runner.check_eq(PaintOps.snap(Vector2i(32, 32), 16), Vector2i(32, 32), "already on lattice")

func test_undo_restores_what_a_stamp_destroyed() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(0, 0), 16, 1, A).apply(w)
	var before: Array = _origins(w)

	var e: MapEdit = PaintOps.stamp(w, Vector2i(4, 4), 4, 1, B)
	e.apply(w)
	runner.check(_origins(w) != before, "the stamp changed the world")
	e.revert(w)
	runner.check_eq(_origins(w), before, "undo is exact")

func test_erase_removes_and_undo_puts_it_back() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(0, 0), 4, 4, A).apply(w)
	var before: Array = _origins(w)
	var e: MapEdit = PaintOps.erase(w, Vector2i(0, 0), 4, 2)
	e.apply(w)
	runner.check_eq(w.blocks.size(), 12, "a 2x2 of size 4 erased four of sixteen")
	e.revert(w)
	runner.check_eq(_origins(w), before, "undo is exact")

## A drag is one undo step. A block born and buried inside the same stroke must
## not come back when the stroke is reverted.
func test_a_stroke_reverts_to_where_it_started() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(0, 0), 16, 1, A).apply(w)
	var before: Array = _origins(w)

	var stroke := MapEdit.Stroke.new()
	for i: int in 4:  # four overlapping stamps, as a drag would make
		var e: MapEdit = PaintOps.stamp(w, Vector2i(i * 2, 0), 8, 1, B)
		e.apply(w)
		stroke.absorb(e)
	runner.check(w.blocks.size() > 0, "the stroke left blocks")

	stroke.to_edit().revert(w)
	runner.check_eq(_origins(w), before, "the whole drag undid in one step")

func test_bench_lays_one_block_per_template() -> void:
	var w: World = _world()
	var ids: Array = ["honest_dirt", "stone", "sand"]
	PaintOps.bench(w, Vector2i(0, 64), 16, ids).apply(w)
	runner.check_eq(w.blocks.size(), 3, "one block each")
	runner.check_eq(w.block_at(Vector2i(0, 64)).template_id, "honest_dirt", "first")
	runner.check_eq(w.block_at(Vector2i(64, 64)).template_id, "sand", "third, one gap apart")

## The painter writes the save format; it must read back identical.
func test_a_painted_world_round_trips_through_the_flat_format() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(0, 0), 16, 2, A).apply(w)
	PaintOps.stamp(w, Vector2i(7, 3), 4, 1, B).apply(w)   # deliberately unaligned
	var before: Array = _origins(w)

	var errors: PackedStringArray = []
	var back: World = WorldSave.from_json(WorldSave.to_json(w), _templates(), errors)
	runner.check(errors.is_empty(), "round trip is clean: %s" % "\n".join(errors))
	runner.check_eq(_origins(back), before, "every block survived the round trip")
	runner.check_eq(back.extent, w.extent, "extent survived")

## Saving from inside the running game must write the map as authored, not as
## dug: damage and reveal are play state (GDD 4.6.1), not terrain.
func test_pristine_strips_play_state_but_keeps_the_blocks() -> void:
	var w: World = _world()
	PaintOps.stamp(w, Vector2i(0, 0), 16, 1, A).apply(w)
	var dug: World.Dig = w.strike(Vector2i(2, 2), 4.0)
	runner.check(dug.hit(), "the block took damage")
	runner.check(w.node_count() > w.blocks.size(), "and fractured")

	var clean: World = PaintOps.pristine(w)
	runner.check_eq(_origins(clean), _origins(w), "same blocks, same places")
	runner.check_eq(clean.node_count(), clean.blocks.size(), "one node per block: undug")
	runner.check(not clean.blocks[0].root.revealed, "and unrevealed")
