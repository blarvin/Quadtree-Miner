## Breaking, cascading, revealing (GDD 4.3-4.6).
extends RefCounted

var runner: SceneTree

func _template(text: String) -> BlockTemplate:
	var errors: PackedStringArray = []
	var t: BlockTemplate = TemplateLoader.from_json_string("test", text, errors)
	runner.check(t != null, "template parsed: %s" % "\n".join(errors))
	return t

const PROTOTYPE: String = """
{
  "material": "dirt",
  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null },
  "overrides": {
    "size:16": { "resistance": 2 },
    "size:2":  { "on_break": "mine", "drop": { "material": "coal", "size": 1 } }
  }
}
"""

const CRUMBLY: String = """
{
  "material": "sand",
  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null, "pass_down": true },
  "overrides": { "size:2": { "on_break": "mine", "drop": null } }
}
"""

const HIDDEN_CORE: String = """
{
  "material": "stone",
  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null },
  "overrides": {
    "Q1.Q2": { "resistance": 40, "on_break": "mine", "drop": { "material": "coal", "size": 4 } }
  }
}
"""

func test_the_gdd_4_5_five_strike_sequence() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	var at := Vector2i(0, 0)

	var s1: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(s1.broke, [] as Array[int], "strike 1 breaks nothing")
	runner.check(root.is_leaf() and root.revealed, "but reveals the root")

	runner.check_eq(Strike.apply(root, t, at, 1.0).broke, [16] as Array[int], "strike 2 breaks the root")
	runner.check_eq(Strike.apply(root, t, at, 1.0).broke, [8] as Array[int], "strike 3 the size-8")
	runner.check_eq(Strike.apply(root, t, at, 1.0).broke, [4] as Array[int], "strike 4 the size-4")

	var s5: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(s5.broke, [2] as Array[int], "strike 5 the size-2")
	runner.check(s5.mined, "which is terminal")
	runner.check_eq(s5.yields.size(), 1, "and yields")
	runner.check_eq(s5.yields[0].count, 4, "four atoms of coal")
	runner.check(root.children[Quad.TL].children[Quad.TL].is_void_at(Quad.TL), "leaving a void slot")
	runner.check(not Strike.apply(root, t, at, 1.0).hit, "striking the hole hits nothing")

func test_damage_is_per_node() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	for _i: int in 3:
		Strike.apply(root, t, Vector2i(15, 15), 1.0)
	runner.check_eq(root.children[Quad.BR].damage, 1.0, "the struck child took the blow")
	for q: int in [Quad.TL, Quad.TR, Quad.BL]:
		runner.check(root.children[q].damage == 0.0 and root.children[q].is_leaf(), "sibling Q%d untouched" % q)

func test_pass_down_cascades_surplus() -> void:
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, _template(CRUMBLY), Vector2i.ZERO, 4.0)
	runner.check_eq(res.broke, [16, 8, 4, 2] as Array[int], "one 4 HP blow bores through")
	runner.check(root.children[Quad.TL].revealed, "and reveals what it passed through")

func test_no_surplus_means_no_cascade() -> void:
	var res: Strike.Result = Strike.apply(BlockNode.new(16), _template(CRUMBLY), Vector2i.ZERO, 1.0)
	runner.check_eq(res.broke, [16] as Array[int], "1 HP into resistance 1 leaves nothing to pass")

func test_pass_down_false_discards_surplus() -> void:
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, _template(PROTOTYPE), Vector2i.ZERO, 40.0)
	runner.check_eq(res.broke, [16] as Array[int], "40 HP breaks one level")
	runner.check_eq(root.children[Quad.TL].damage, 0.0, "the child got none of it")

func test_falloff_bleeds_the_cascade_out() -> void:
	var t: BlockTemplate = _template("""
	{ "material": "sand",
	  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null,
	                    "pass_down": true, "pass_down_falloff": 0.5 } }
	""")
	var root := BlockNode.new(16)
	runner.check_eq(Strike.apply(root, t, Vector2i.ZERO, 3.0).broke, [16, 8] as Array[int], "two levels")
	runner.check_eq(root.children[Quad.TL].damage, 1.0, "child received half of the 2 HP surplus")

func test_a_terminal_node_absorbs_and_yields_one_lump() -> void:
	var t: BlockTemplate = _template(HIDDEN_CORE)
	var root := BlockNode.new(16)
	var at := Vector2i(8, 4)  # Q1.Q2
	for _i: int in 41:
		Strike.apply(root, t, at, 1.0)
	var core: BlockNode = root.children[Quad.TR].children[Quad.BL]
	runner.check(core.size == 4 and core.is_leaf() and core.damage == 39.0, "39 of 40 HP in, still one node")
	var res: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check(res.mined and res.broke == ([4] as Array[int]), "breaks whole")
	runner.check(res.yields.size() == 1 and res.yields[0].count == 1 and res.yields[0].drop.size == 4, "one 4x4 lump")
	runner.check(root.children[Quad.TR].is_void_at(Quad.BL), "leaving a size-4 void")

func test_an_atom_is_destroyed_not_subdivided() -> void:
	var t: BlockTemplate = _template("""
	{ "material": "dirt",
	  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null, "pass_down": true } }
	""")
	var res: Strike.Result = Strike.apply(BlockNode.new(16), t, Vector2i.ZERO, 5.0)
	runner.check_eq(res.broke, [16, 8, 4, 2, 1] as Array[int], "cascade reached the atom")
	runner.check(res.mined and res.yields.is_empty(), "destroyed, yielding nothing")

func test_mining_the_root_destroys_the_block() -> void:
	var t: BlockTemplate = _template('{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "mine", "drop": null}}')
	var root := BlockNode.new(16)
	runner.check(Strike.apply(root, t, Vector2i(3, 9), 1.0).block_destroyed, "the whole block is gone")
	runner.check(root.is_leaf(), "with no children ever made")

func test_drop_counts_are_derived() -> void:
	runner.check_eq(Drop.new(Materials.Id.COAL, 1).count_from(4), 16, "16 atoms")
	runner.check_eq(Drop.new(Materials.Id.COAL, 2).count_from(4), 4, "four 2x2")
	runner.check_eq(Drop.new(Materials.Id.COAL, 4).count_from(4), 1, "one lump")

func test_reveal_spreads_to_siblings_sharing_a_rule_but_not_to_the_core() -> void:
	var t: BlockTemplate = _template(HIDDEN_CORE)
	var root := BlockNode.new(16)
	var at := Vector2i(8, 0)  # Q1.Q0, a plain neighbour of the core
	for _i: int in 3:
		Strike.apply(root, t, at, 1.0)
	var q1: BlockNode = root.children[Quad.TR]
	runner.check(q1.children[Quad.TL].revealed and q1.children[Quad.TR].revealed and q1.children[Quad.BR].revealed,
		"struck node and its like siblings are revealed")
	runner.check(not q1.children[Quad.BL].revealed, "the core, with a different rule, is not")

func test_pass_through_is_parsed_but_not_routed() -> void:
	var t: BlockTemplate = _template("""
	{ "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null,
	                    "pass_through": "lateral", "pass_through_falloff": 0.5 } }
	""")
	runner.check_eq(t.rule_at([] as Array[int], 16).pass_through, Rule.PassThrough.LATERAL, "resolves")
	var root := BlockNode.new(16)
	Strike.apply(root, t, Vector2i.ZERO, 1.0)
	Strike.apply(root, t, Vector2i.ZERO, 1.0)
	runner.check_eq(root.children[Quad.TR].damage, 0.0, "no sibling damage: routing is Phase 2")
