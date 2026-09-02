## Locks the GDD 4.0.2 convention: 0-based row-major, +Y down.
## If these ever fail, someone "fixed" the indexing and every sibling
## pattern in GDD 4.4.2 silently changed meaning.
extends RefCounted

var runner: SceneTree

func test_index_is_row_major_with_y_down() -> void:
	var o := Vector2i(0, 0)
	runner.check_eq(Quad.index_of(Vector2i(0, 0), o, 16), Quad.TL, "TL is 0")
	runner.check_eq(Quad.index_of(Vector2i(8, 0), o, 16), Quad.TR, "TR is 1")
	runner.check_eq(Quad.index_of(Vector2i(0, 8), o, 16), Quad.BL, "BL is 2 (+Y is down)")
	runner.check_eq(Quad.index_of(Vector2i(8, 8), o, 16), Quad.BR, "BR is 3")

func test_bits_mean_right_and_bottom() -> void:
	for q: int in 4:
		var origin := Quad.child_origin(q, Vector2i(0, 0), 16)
		runner.check_eq(origin.x, (q & 1) * 8, "bit 0 is 'am I right?'")
		runner.check_eq(origin.y, ((q & 2) >> 1) * 8, "bit 1 is 'am I bottom?'")

func test_sibling_patterns_are_bit_ops() -> void:
	runner.check_eq(Quad.sibling_lateral(Quad.TL), Quad.TR, "lateral flips bit 0")
	runner.check_eq(Quad.sibling_lateral(Quad.BR), Quad.BL, "lateral flips bit 0")
	runner.check_eq(Quad.sibling_downward(Quad.TR), Quad.BR, "downward sets bit 1")
	runner.check_eq(Quad.sibling_downward(Quad.BL), Quad.BL, "downward is idempotent at bottom")
	runner.check_eq(Quad.siblings_radial(Quad.TL).size(), 3, "radial hits 3 siblings")

func test_child_origin_offsets_within_parent() -> void:
	var o := Vector2i(64, 128)
	runner.check_eq(Quad.child_origin(Quad.TL, o, 16), Vector2i(64, 128), "TL keeps origin")
	runner.check_eq(Quad.child_origin(Quad.BR, o, 16), Vector2i(72, 136), "BR offsets by half")

func test_atom_sizes() -> void:
	runner.check(Atoms.is_valid_size(1), "atom is valid")
	runner.check(Atoms.is_valid_size(16), "standard block is valid")
	runner.check(not Atoms.is_valid_size(0), "0 is not a valid size")
	runner.check(not Atoms.is_valid_size(12), "non-power-of-two is invalid")
	runner.check_eq(Atoms.depth_of(16, 1), 4, "atom is 4 levels under a size-16 root")
	runner.check_eq(Atoms.depth_of(32, 16), 1, "depth is derived, not an identity")
