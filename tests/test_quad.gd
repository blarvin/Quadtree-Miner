## Locks GDD 4.0.2: 0-based row-major, +Y down.
extends RefCounted

var runner: SceneTree

func test_index_is_row_major_with_y_down() -> void:
	var o := Vector2i(0, 0)
	runner.check_eq(Quad.index_of(Vector2i(0, 0), o, 16), Quad.TL, "TL is 0")
	runner.check_eq(Quad.index_of(Vector2i(8, 0), o, 16), Quad.TR, "TR is 1")
	runner.check_eq(Quad.index_of(Vector2i(0, 8), o, 16), Quad.BL, "BL is 2 (+Y is down)")
	runner.check_eq(Quad.index_of(Vector2i(8, 8), o, 16), Quad.BR, "BR is 3")

func test_child_origin_bits_mean_right_and_bottom() -> void:
	for q: int in 4:
		var origin := Quad.child_origin(q, Vector2i(64, 128), 16)
		runner.check_eq(origin, Vector2i(64 + (q & 1) * 8, 128 + (q >> 1) * 8), "child %d origin" % q)

func test_valid_sizes_are_powers_of_two() -> void:
	for s: int in [1, 2, 16, 32]:
		runner.check(Atoms.is_valid_size(s), "%d is valid" % s)
	for s: int in [0, 12, -4]:
		runner.check(not Atoms.is_valid_size(s), "%d is invalid" % s)
