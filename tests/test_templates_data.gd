## The authored Phase-0 templates. GDD 6.
##
## This is the stage where the question stops being "does the engine work?"
## and starts being "is this fun?". Uniform subdivision is the least
## interesting thing the system does; these tests exist to prove the SAME
## INPUT PRODUCES DIFFERENT EXPERIENCES.
extends RefCounted

var runner: SceneTree

const DIR: String = "res://data/templates"
const PICKAXE: float = 1.0  ## the starting tool: 1 HP per strike (GDD 4.5)

var _templates: Dictionary = {}

func _all() -> Dictionary:
	if _templates.is_empty():
		var errors: PackedStringArray = []
		_templates = TemplateLoader.load_dir(DIR, errors)
		runner.check(errors.is_empty(), "templates loaded clean: %s" % "\n".join(errors))
	return _templates

func _tpl(id: String) -> BlockTemplate:
	var t: BlockTemplate = _all().get(id)
	runner.check(t != null, "template '%s' exists" % id)
	return t

## Strike the same point n times and hand back the last result.
func _dig(root: BlockNode, t: BlockTemplate, at: Vector2i, n: int) -> Strike.Result:
	var res: Strike.Result = null
	for _i: int in n:
		res = Strike.apply(root, t, at, PICKAXE)
	return res

# ---------------------------------------------------------------- the set

func test_every_authored_template_loads_and_binds() -> void:
	var all: Dictionary = _all()
	for id: String in ["honest_dirt", "liar_dirt", "stone", "gift_stone", "sand", "hard_stone"]:
		runner.check(all.has(id), "%s is authored" % id)
	for id: String in all:
		var t: BlockTemplate = all[id]
		var problems: PackedStringArray = t.validate_for_root_size(16)
		runner.check(problems.is_empty(), "%s binds to a standard block: %s"
			% [id, " ".join(problems)])

func test_the_granularity_dial_is_not_more_templates() -> void:
	# GDD 4.1.2: block size is an authoring dial that costs no new templates.
	# A size-4 dirt block and a size-16 dirt block are the same rules and
	# different play -- pebble versus boulder.
	var dirt: BlockTemplate = _tpl("honest_dirt")
	runner.check(dirt.validate_for_root_size(4).is_empty(),
		"the same template binds at size 4 -- its size:16 rule is simply inert")
	runner.check_eq(dirt.rule_at([] as Array[int], 16).resistance, 2.0,
		"at size 16 the root gets the look before committing")
	runner.check_eq(dirt.rule_at([] as Array[int], 4).resistance, 1.0,
		"at size 4 there is nothing to deliberate about -- rubble is cheap")

# ------------------------------------------------------ 1. the honest block

func test_honest_dirt_is_the_gdd_4_5_baseline() -> void:
	var t: BlockTemplate = _tpl("honest_dirt")
	var root := BlockNode.new(16)

	runner.check_eq(_dig(root, t, Vector2i(0, 0), 1).subdivided, 0,
		"strike 1 reveals without subdividing")
	runner.check_eq(_dig(root, t, Vector2i(0, 0), 1).broke, [16] as Array[int],
		"strike 2 breaks the root")
	var s5: Strike.Result = _dig(root, t, Vector2i(0, 0), 3)
	runner.check_eq(s5.mined, 1, "strike 5 reaches the terminal size-2")
	runner.check_eq(s5.yields.size(), 0, "dirt vanishes -- drop: none (GDD 4.5)")

# --------------------------------------------------------------- 2. the liar

func test_the_liar_is_indistinguishable_from_the_honest_block() -> void:
	# GDD 6: "identical when untouched". If any of this diverges, the player
	# can price the block by looking at it and the whole trick is off.
	var honest: BlockTemplate = _tpl("honest_dirt")
	var liar: BlockTemplate = _tpl("liar_dirt")

	runner.check_eq(liar.material, honest.material, "same material")
	runner.check_eq(liar.colour_class, honest.colour_class, "same colour class")
	runner.check_eq(liar.display_skin, honest.display_skin, "same skin")
	runner.check(liar.rule_at([] as Array[int], 16).equals(honest.rule_at([] as Array[int], 16)),
		"and the SAME ROOT RULE -- the first strike costs the same and tells you nothing")

func test_the_liar_keeps_one_quadrant_back() -> void:
	# GDD 6: strike each quadrant once -- three crumble, one does not.
	# The player's "huh?" is the game.
	var t: BlockTemplate = _tpl("liar_dirt")
	var root := BlockNode.new(16)
	_dig(root, t, Vector2i(0, 0), 2)  # break the root open

	_dig(root, t, Vector2i(0, 0), 1)   # Q0 top-left
	_dig(root, t, Vector2i(8, 0), 1)   # Q1 top-right
	_dig(root, t, Vector2i(8, 8), 1)   # Q3 bottom-right
	var q2: Strike.Result = _dig(root, t, Vector2i(0, 8), 1)  # Q2 bottom-left

	for q: int in [Quad.TL, Quad.TR, Quad.BR]:
		runner.check(not root.children[q].is_leaf(), "quadrant Q%d crumbled" % q)
	runner.check_eq(q2.broke, [] as Array[int], "and Q2 did not")
	runner.check(root.children[Quad.BL].is_leaf(), "it is still one node")
	runner.check_eq(root.children[Quad.BL].damage, 1.0, "with 1 of its 8 HP taken")

func test_the_liars_quadrant_lies_all_the_way_down() -> void:
	# The override applies to that node AND BELOW, so the cost is not a
	# one-off toll at size 8 -- the whole bottom-left quarter is expensive.
	var t: BlockTemplate = _tpl("liar_dirt")
	runner.check_eq(t.rule_at([Quad.BL] as Array[int], 8).resistance, 8.0, "at size 8")
	runner.check_eq(t.rule_at([Quad.BL, Quad.TR] as Array[int], 4).resistance, 8.0, "at size 4")
	runner.check_eq(t.rule_at([Quad.TL, Quad.BL] as Array[int], 4).resistance, 1.0,
		"but a BL that is not under the top-level Q2 is ordinary -- paths are positions")

# --------------------------------------------------------------- 3. the gift

func test_the_gift_shows_its_coal_before_you_can_reach_it() -> void:
	# GDD 6: "You can see the coal and must work for it."
	var t: BlockTemplate = _tpl("gift_stone")
	var root := BlockNode.new(16)
	var near_core := Vector2i(8, 0)  # Q1.Q0 -- the core's neighbour, not the core

	# 3 strikes to break the size-16 root, 2 more to break the size-8 at Q1 --
	# only then does the core exist as a node at all.
	_dig(root, t, near_core, 5)
	var core: BlockNode = root.children[Quad.TR].children[Quad.BL]
	runner.check_eq(core.size, 4, "the core is the size-4 node at Q1.Q2")
	runner.check(not core.revealed, "nothing has touched that region yet")

	_dig(root, t, near_core, 1)  # strike the NEIGHBOUR, never the core
	runner.check(core.revealed,
		"the core reveals with its siblings -- at size 4 it behaves identically")
	runner.check_eq(t.rule_at([Quad.TR, Quad.BL] as Array[int], 4).apparent_material(t.material),
		Materials.Id.COAL, "and it shows as COAL, derived from the rule that yields it")
	runner.check_eq(t.rule_at([Quad.TR, Quad.TL] as Array[int], 4).apparent_material(t.material),
		Materials.Id.STONE, "while its neighbours are still stone")

func test_the_gift_is_not_terminal_so_a_fracture_can_depict_it() -> void:
	# GDD 4.6.3 contrast: a terminal core never subdivides, so no fracture can
	# ever show its interior. This one does subdivide -- that is the difference
	# between a gift and a secret, and it is structural, not a setting.
	var t: BlockTemplate = _tpl("gift_stone")
	runner.check_eq(t.rule_at([Quad.TR, Quad.BL] as Array[int], 4).on_break,
		Rule.OnBreak.SUBDIVIDE, "the core subdivides")

	var root := BlockNode.new(16)
	_dig(root, t, Vector2i(8, 4), 7)  # 3 + 2 + 2: straight into the core this time
	var core: BlockNode = root.children[Quad.TR].children[Quad.BL]
	runner.check_eq(core.live_children().size(), 4,
		"so it has real child boundaries a fracture can draw")

func test_the_gift_actually_pays_out() -> void:
	var t: BlockTemplate = _tpl("gift_stone")
	var root := BlockNode.new(16)
	# 3 + 2 + 2 to open the core, then 2 more for one of its size-2 children.
	var res: Strike.Result = _dig(root, t, Vector2i(8, 4), 9)

	runner.check_eq(res.mined, 1, "the ninth strike takes a size-2 out of the core")
	runner.check_eq(res.yields.size(), 1, "and it yields")
	runner.check_eq(res.yields[0].drop.material, Materials.Id.COAL, "coal")
	runner.check_eq(res.yields[0].count, 4, "four atoms of it")

func test_the_gifts_coal_is_one_override() -> void:
	# GDD 4.7.1: "a dirt shell with a coal core is a default plus ~two
	# overrides". The core changes ONLY the drop; the terminal break and the
	# root's resistance are the template's ordinary size rules.
	var t: BlockTemplate = _tpl("gift_stone")
	runner.check_eq(t.path_overrides.size(), 1, "exactly one positional override")
	runner.check(t.path_overrides.has("Q1.Q2"), "and it is the core")

# ---------------------------------------------------------------- the trap

func test_sand_collapses_under_a_single_strike() -> void:
	# GDD 6: one strike drops you somewhere you did not choose. Not
	# punishment -- consequence. Most digging games have no way to dig wrong.
	var t: BlockTemplate = _tpl("sand")
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, t, Vector2i(0, 0), PICKAXE)

	runner.check_eq(res.broke, [16, 8, 4, 2] as Array[int],
		"ONE strike from a 1 HP pickaxe bores clean through every level")
	runner.check_eq(res.mined, 1, "and takes the bottom out")
	runner.check(root.children[Quad.TL].children[Quad.TL].is_void_at(Quad.TL),
		"leaving a hole you are standing over")

func test_sand_cannot_keep_a_secret() -> void:
	# GDD 4.6.4: propagation is a reveal mechanic too. How much a strike gives
	# away is tool HP x template propagation -- and sand gives away everything.
	var sand: Strike.Result = Strike.apply(BlockNode.new(16), _tpl("sand"), Vector2i(0, 0), PICKAXE)
	var stone: Strike.Result = Strike.apply(BlockNode.new(16), _tpl("stone"), Vector2i(0, 0), PICKAXE)
	runner.check(sand.revealed.size() > stone.revealed.size(),
		"one strike tells you far more about sand than about stone")

# --------------------------------------------------- the packing test (4.1.2)

func test_the_boulder_cracks_once_and_no_further() -> void:
	# GDD 4.6.2: hard stone is "a single clean cross -- solid, 4-way, this
	# will take work". Terminal at size 8, so there is no finer structure to
	# show and no finer structure to dig.
	var t: BlockTemplate = _tpl("hard_stone")
	var root := BlockNode.new(16)

	var nineteen: Strike.Result = _dig(root, t, Vector2i(0, 0), 19)
	runner.check_eq(nineteen.broke, [] as Array[int], "nineteen strikes, nothing")
	runner.check(root.is_leaf(), "the boulder has not moved")

	var twentieth: Strike.Result = _dig(root, t, Vector2i(0, 0), 1)
	runner.check_eq(twentieth.broke, [16] as Array[int], "the twentieth cracks it")
	runner.check_eq(root.live_children().size(), 4, "into a single clean cross")

	var chunk: Strike.Result = _dig(root, t, Vector2i(0, 0), 20)
	runner.check_eq(chunk.mined, 1, "and twenty more take a whole 8x8 out at once")
	runner.check_eq(chunk.subdivided, 0, "terminal -- it never cracks finer than that")
	runner.check(root.is_void_at(Quad.TL), "leaving a size-8 hole")

func test_the_boulder_hides_in_rubble_of_its_own_colour() -> void:
	# GDD 4.1.2's whole point: the wall must read CHEAP from outside, and the
	# only channel saying otherwise is the block BORDER. If colour gave it
	# away the packing axis would be decoration.
	var rubble: BlockTemplate = _tpl("stone")
	var boulder: BlockTemplate = _tpl("hard_stone")
	runner.check_eq(rubble.colour_class, boulder.colour_class,
		"rubble and boulder share a colour class -- the lamp cannot tell them apart")
	runner.check(rubble.material != boulder.material, "though they are different materials")
	runner.check_eq(rubble.colour_class, Materials.ColourClass.GREY, "both grey")

func test_size_reads_as_cost() -> void:
	# The prerequisite of GDD 4.1.2: size must be readable as rough cost
	# BEFORE the first strike, or the boulder-in-rubble is a gotcha rather
	# than a decision. This test states the cost gap the picture has to carry.
	var rubble_first_break: float = _tpl("stone").rule_at([] as Array[int], 4).resistance
	var boulder_first_break: float = _tpl("hard_stone").rule_at([] as Array[int], 16).resistance

	runner.check_eq(rubble_first_break, 2.0, "a size-4 rubble block gives way in two strikes")
	runner.check_eq(boulder_first_break, 20.0, "the size-16 boulder takes twenty")
	runner.check(boulder_first_break >= 10.0 * rubble_first_break,
		"a tenfold difference in commitment, announced by nothing but the border")

func test_first_break_costs_are_ordered() -> void:
	# GDD 8 lists resistance values as expected to move under playtest. What
	# must NOT move is the ordering -- if sand is not the cheapest and the
	# boulder is not the dearest, the terrain vocabulary has no gradient.
	var costs: Array[float] = []
	for id: String in ["sand", "honest_dirt", "stone", "hard_stone"]:
		costs.append(_tpl(id).rule_at([] as Array[int], 16).resistance)
	for i: int in costs.size() - 1:
		runner.check(costs[i] < costs[i + 1],
			"cost rises strictly across sand < dirt < stone < hard stone (%s)" % [costs])

func test_at_least_two_materials_share_a_colour_class() -> void:
	# GDD 6 requires this explicitly: without it the lossiness -- and
	# therefore the price of information -- is untested.
	var seen: Dictionary = {}
	var shared: bool = false
	for id: String in _all():
		var t: BlockTemplate = _all()[id]
		var c: int = t.colour_class
		if seen.has(c) and seen[c] != t.material:
			shared = true
		seen[c] = t.material
	runner.check(shared, "two different materials look the same at lamp radius")

# --------------------------------------------------- heterogeneity, the point

func test_the_same_strike_produces_three_different_experiences() -> void:
	# GDD 6: "A slice built from one homogeneous template is four identical
	# strikes producing four similar subdivisions -- a progress bar with extra
	# steps." One strike, one point, one tool. The templates must diverge.
	var at := Vector2i(0, 0)
	var shapes: Dictionary = {}
	for id: String in ["honest_dirt", "sand", "hard_stone", "gift_stone"]:
		shapes[id] = Strike.apply(BlockNode.new(16), _tpl(id), at, PICKAXE).broke

	runner.check_eq(shapes["honest_dirt"], [] as Array[int], "dirt: a look, no commitment")
	runner.check_eq(shapes["sand"], [16, 8, 4, 2] as Array[int], "sand: the floor goes")
	runner.check_eq(shapes["hard_stone"], [] as Array[int], "hard stone: nothing, and nothing for a while")
	runner.check(shapes["honest_dirt"] == shapes["hard_stone"],
		"dirt and hard stone are identical after one strike -- the cost is what differs")
