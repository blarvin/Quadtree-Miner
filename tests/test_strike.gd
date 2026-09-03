## Breaking, subdividing, propagating, revealing. GDD 4.3-4.6.
##
## The centrepiece is test_the_gdd_4_5_five_strike_sequence: if that ever goes
## red, the prototype block no longer behaves the way the design argues it does.
extends RefCounted

var runner: SceneTree

func _template(text: String) -> BlockTemplate:
	var res: TemplateLoader.Result = TemplateLoader.from_json_string("test", text)
	runner.check(res.ok(), "template parsed: %s" % res.describe())
	return res.template

# GDD 4.5, verbatim: fracture-before-commit at the root, 1 HP below it, and a
# terminal size-2 that yields four atoms at once.
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

# ------------------------------------------------------- the canonical walk

func test_the_gdd_4_5_five_strike_sequence() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	var at := Vector2i(0, 0)  # the top-left atom: Q0 all the way down

	# 1. Reveals the fracture pattern and the material. DOES NOT SUBDIVIDE.
	#    This one number is the difference between an action and a decision.
	var s1: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(s1.struck_size, 16, "strike 1 lands on the size-16 root")
	runner.check_eq(s1.broke, [] as Array[int], "strike 1 breaks nothing")
	runner.check_eq(s1.subdivided, 0, "strike 1 does NOT subdivide -- the look before committing")
	runner.check_eq(root.damage, 1.0, "the root has taken 1 of its 2 HP")
	runner.check(root.is_leaf(), "still one node")
	runner.check_eq(s1.revealed.size(), 1, "strike 1 reveals the block")
	runner.check(root.revealed, "and the reveal is on the node, persisted")

	# 2. The root breaks and subdivides.
	var s2: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(s2.broke, [16] as Array[int], "strike 2 breaks the size-16")
	runner.check_eq(s2.subdivided, 1, "into four size-8 children")
	runner.check_eq(root.children.size(), 4, "which now exist")
	runner.check_eq(root.children[Quad.TL].size, 8, "each of size 8")

	# 3-4. The STRUCK child breaks each time; its siblings are untouched.
	var s3: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(s3.struck_size, 8, "strike 3 lands on the size-8 under the point")
	runner.check_eq(s3.broke, [8] as Array[int], "and breaks it")

	var s4: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(s4.struck_size, 4, "strike 4 lands on the size-4")
	runner.check_eq(s4.broke, [4] as Array[int], "and breaks it")

	# 5. The size-2 is TERMINAL. Its four atoms are never instantiated as
	#    nodes -- they come out as drops, all at once. The payoff, not a chore.
	var s5: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(s5.struck_size, 2, "strike 5 lands on the size-2")
	runner.check_eq(s5.broke, [2] as Array[int], "and breaks it")
	runner.check_eq(s5.subdivided, 0, "a terminal node NEVER instantiates children")
	runner.check_eq(s5.mined, 1, "it is destroyed")
	runner.check_eq(s5.yields.size(), 1, "yielding one drop group")
	runner.check_eq(s5.yields[0].count, 4, "of FOUR atoms at once -- (2/1)^2")
	runner.check_eq(s5.yields[0].drop.material, Materials.Id.COAL, "of coal")
	runner.check_eq(s5.yields[0].drop.size, 1, "at the authored drop size")
	runner.check_eq(s5.yields[0].node_size, 2, "from the size-2 node")
	runner.check_eq(s5.yields[0].node_origin, Vector2i(0, 0), "at the block-local origin")

	# The hole is real: that quadrant is now void inside the block.
	var size_four: BlockNode = root.children[Quad.TL].children[Quad.TL]
	runner.check(size_four.is_void_at(Quad.TL), "the mined size-2 left a void slot")
	runner.check_eq(size_four.live_children().size(), 3, "three siblings remain")

func test_striking_into_a_mined_hole_hits_nothing() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	var at := Vector2i(0, 0)
	for _i: int in 5:
		Strike.apply(root, t, at, 1.0)
	var again: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check(not again.hit, "there is nothing there any more")
	runner.check_eq(again.broke, [] as Array[int], "so the blow breaks nothing")
	runner.check_eq(again.revealed.size(), 0, "and reveals nothing")

# ------------------------------------------------------ the wandering front

func test_unstruck_siblings_keep_their_own_damage_pools() -> void:
	# GDD 4.3: digging carves one quadrant-path; siblings stay intact until
	# separately hit. This is the Gem-Miner feel and it is deliberate.
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	for _i: int in 3:
		Strike.apply(root, t, Vector2i(0, 0), 1.0)

	runner.check_eq(root.children[Quad.TL].damage, 1.0, "the struck child took the blow")
	for q: int in [Quad.TR, Quad.BL, Quad.BR]:
		runner.check_eq(root.children[q].damage, 0.0,
			"sibling Q%d is untouched -- damage is per-node, not per-block" % q)
		runner.check(root.children[q].is_leaf(), "and unsubdivided")

func test_the_impact_point_chooses_the_quadrant() -> void:
	# +Y IS DOWN and indices are row-major (GDD 4.0.1-4.0.2). A blow low and
	# right must work the BR path, not the TL one.
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	Strike.apply(root, t, Vector2i(15, 15), 1.0)
	Strike.apply(root, t, Vector2i(15, 15), 1.0)
	Strike.apply(root, t, Vector2i(15, 15), 1.0)
	runner.check_eq(root.children[Quad.BR].damage, 1.0, "the bottom-right child was struck")
	runner.check_eq(root.children[Quad.TL].damage, 0.0, "the top-left was not")

# -------------------------------------------- tool power and pass_down (4.4)

const CRUMBLY: String = """
{
  "material": "sand",
  "default_rule": {
    "resistance": 1, "on_break": "subdivide", "drop": null,
    "pass_down": true, "pass_down_falloff": 1.0
  },
  "overrides": { "size:2": { "on_break": "mine", "drop": null } }
}
"""

const TOUGH: String = """
{
  "material": "stone",
  "default_rule": {
    "resistance": 1, "on_break": "subdivide", "drop": null,
    "pass_down": false
  },
  "overrides": { "size:2": { "on_break": "mine", "drop": null } }
}
"""

func test_pass_down_cascades_a_whole_block_in_one_blow() -> void:
	# GDD 4.4.1: leftover damage flows into the child under the impact point.
	# One strike, size 16 to gone.
	var t: BlockTemplate = _template(CRUMBLY)
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, t, Vector2i(0, 0), 4.0)

	runner.check_eq(res.broke, [16, 8, 4, 2] as Array[int], "one blow broke every level")
	runner.check_eq(res.subdivided, 3, "three subdivisions")
	runner.check_eq(res.mined, 1, "and one terminal break at size 2")
	runner.check(root.children[Quad.TL].children[Quad.TL].is_void_at(Quad.TL),
		"the shaft reaches the bottom")

func test_a_one_hp_tool_grinds_regardless_of_the_pass_down_flag() -> void:
	# GDD 4.3.1: pass_down only expresses itself when a tool OVERDELIVERS.
	# 1 HP into a resistance-1 node leaves ZERO surplus, so there is nothing
	# to pass down and both templates behave identically. This is why
	# resistance must be tuned against the tool ladder, never in isolation.
	var crumbly: Strike.Result = Strike.apply(BlockNode.new(16), _template(CRUMBLY), Vector2i(0, 0), 1.0)
	var tough: Strike.Result = Strike.apply(BlockNode.new(16), _template(TOUGH), Vector2i(0, 0), 1.0)

	runner.check_eq(crumbly.broke, [16] as Array[int], "the crumbly block breaks one level")
	runner.check_eq(tough.broke, [16] as Array[int], "so does the tough one")
	runner.check_eq(crumbly.subdivided, tough.subdivided, "identical -- the flag is not the cause")

func test_pass_down_false_discards_the_surplus() -> void:
	# The progressive/tough block: each level is a fresh wall.
	var t: BlockTemplate = _template(TOUGH)
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, t, Vector2i(0, 0), 40.0)
	runner.check_eq(res.broke, [16] as Array[int], "40 HP still only breaks one level")
	runner.check_eq(root.children[Quad.TL].damage, 0.0, "the surplus did not reach the child")

func test_falloff_bleeds_the_cascade_out() -> void:
	var t: BlockTemplate = _template("""
	{
	  "material": "sand",
	  "default_rule": {
	    "resistance": 1, "on_break": "subdivide", "drop": null,
	    "pass_down": true, "pass_down_falloff": 0.5
	  }
	}
	""")
	var root := BlockNode.new(16)
	# 3 HP: root takes 1, passes 2 * 0.5 = 1 -> size-8 takes 1, passes 0.
	var res: Strike.Result = Strike.apply(root, t, Vector2i(0, 0), 3.0)
	runner.check_eq(res.broke, [16, 8] as Array[int], "falloff stopped the collapse two levels in")
	runner.check_eq(root.children[Quad.TL].damage, 1.0, "the child received half the 2 HP surplus")
	runner.check(root.children[Quad.TL].children[Quad.TL].damage == 0.0,
		"and nothing survived the second hop")

# ------------------------------------------------------ terminal and atoms

const HIDDEN_CORE: String = """
{
  "material": "stone",
  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null },
  "overrides": {
    "Q1.Q2": {
      "resistance": 40,
      "on_break": "mine",
      "drop": { "material": "coal", "size": 4 }
    }
  }
}
"""

func test_a_terminal_node_absorbs_without_ever_making_children() -> void:
	# GDD 4.6.3 / invariant 12: `mine` is terminal, so the core never has
	# children, so no fracture can ever depict its interior. Opacity is
	# structural -- there is nothing to set and nothing that can contradict it.
	var t: BlockTemplate = _template(HIDDEN_CORE)
	var root := BlockNode.new(16)
	var at := Vector2i(8, 4)  # Q1 then Q2: the core, at size 4

	Strike.apply(root, t, at, 1.0)  # root breaks
	Strike.apply(root, t, at, 1.0)  # the size-8 breaks
	var core: BlockNode = root.children[Quad.TR].children[Quad.BL]
	runner.check_eq(core.size, 4, "the core is the size-4 node at Q1.Q2")

	for _i: int in 10:
		Strike.apply(root, t, at, 1.0)
	runner.check_eq(core.damage, 10.0, "it accumulates damage")
	runner.check(core.is_leaf(), "but never subdivides -- 40 HP is a tool gate, not a wall")
	runner.check_eq(core.live_children().size(), 0, "so a fracture has no boundaries to draw")

func test_the_terminal_node_yields_one_lump() -> void:
	var t: BlockTemplate = _template(HIDDEN_CORE)
	var root := BlockNode.new(16)
	var at := Vector2i(8, 4)
	# Two strikes to open the block down to the core, then 40 into the core
	# itself -- resistance is a TOOL GATE (GDD 4.3.1), and a 1 HP pickaxe pays
	# for it one strike at a time.
	for _i: int in 41:
		Strike.apply(root, t, at, 1.0)
	var core: BlockNode = root.children[Quad.TR].children[Quad.BL]
	runner.check_eq(core.damage, 39.0, "39 of 40 HP in, it still stands")

	var res: Strike.Result = Strike.apply(root, t, at, 1.0)
	runner.check_eq(res.broke, [4] as Array[int], "the 42nd strike breaks it")
	runner.check_eq(res.mined, 1, "destroying it whole")
	runner.check_eq(res.subdivided, 0, "without ever instantiating its children")
	runner.check_eq(res.yields.size(), 1, "and yielding")
	runner.check_eq(res.yields[0].count, 1, "ONE 4x4 lump -- not a spray")
	runner.check_eq(res.yields[0].drop.size, 4, "at the authored drop size")

	var parent: BlockNode = root.children[Quad.TR]
	runner.check(parent.is_void_at(Quad.BL), "leaving a size-4 void")
	runner.check(not Strike.apply(root, t, at, 1.0).hit, "and nothing left to hit")

func test_drop_counts_are_derived_from_the_two_sizes() -> void:
	# GDD 4.7 / invariant 12: count = (node.size / drop.size)^2, never authored.
	runner.check_eq(Drop.new(Materials.Id.COAL, 1).count_from(4), 16, "size-4 node -> 16 atoms")
	runner.check_eq(Drop.new(Materials.Id.COAL, 2).count_from(4), 4, "size-4 node -> four 2x2")
	runner.check_eq(Drop.new(Materials.Id.COAL, 4).count_from(4), 1, "size-4 node -> one lump")

func test_an_atom_is_destroyed_not_subdivided() -> void:
	# GDD 4.0: the atom is the natural terminator. A break at size 1 destroys
	# it whatever the rule says -- arithmetic, not a special case a template
	# could get wrong by forgetting a size:1 override.
	var t: BlockTemplate = _template("""
	{
	  "material": "dirt",
	  "default_rule": {
	    "resistance": 1, "on_break": "subdivide", "drop": null,
	    "pass_down": true, "pass_down_falloff": 1.0
	  }
	}
	""")
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, t, Vector2i(0, 0), 5.0)
	runner.check_eq(res.broke, [16, 8, 4, 2, 1] as Array[int], "the cascade reached the atom")
	runner.check_eq(res.mined, 1, "and the atom was destroyed")
	runner.check_eq(res.subdivided, 4, "nothing tried to subdivide below it")
	runner.check_eq(res.yields.size(), 0, "drop: none means it vanishes, yielding nothing")

func test_mining_the_root_destroys_the_block() -> void:
	# Void is the absence of a block (invariant 4), at every scale. The World
	# drops it from the index; no air block is spawned in its place.
	var t: BlockTemplate = _template("""
	{
	  "material": "dirt",
	  "default_rule": { "resistance": 1, "on_break": "mine", "drop": null }
	}
	""")
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, t, Vector2i(3, 9), 1.0)
	runner.check(res.block_destroyed, "the whole block is gone")
	runner.check_eq(res.mined, 1, "in one break")
	runner.check(root.is_leaf(), "and it never instantiated children on the way out")

# ------------------------------------------------------------- reveal (4.6)

func test_reveal_spreads_to_siblings_sharing_a_rule_but_not_to_the_core() -> void:
	# GDD 4.6.4. This is what makes the hidden core hold even inside a block
	# whose outer material the player already knows.
	var t: BlockTemplate = _template(HIDDEN_CORE)
	var root := BlockNode.new(16)
	var at := Vector2i(8, 0)  # Q1 then Q0 -- a plain neighbour of the core

	Strike.apply(root, t, at, 1.0)  # root breaks and subdivides
	Strike.apply(root, t, at, 1.0)  # the size-8 at Q1 breaks and subdivides
	Strike.apply(root, t, at, 1.0)  # lands on Q1.Q0, a size-4 plain node

	var q1: BlockNode = root.children[Quad.TR]
	runner.check(q1.children[Quad.TL].revealed, "the struck node is revealed")
	runner.check(q1.children[Quad.TR].revealed, "so is the sibling sharing its rule")
	runner.check(q1.children[Quad.BR].revealed, "and the other one")
	runner.check(not q1.children[Quad.BL].revealed,
		"but NOT the core -- a different rule stays unrevealed until struck itself")

func test_reveal_is_carried_by_the_cascade() -> void:
	# GDD 4.6.4: propagation is a reveal mechanic, not only a breaking one.
	# How much a strike gives away is tool HP x template propagation.
	var t: BlockTemplate = _template(CRUMBLY)
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, t, Vector2i(0, 0), 4.0)
	runner.check(res.revealed.size() > 4,
		"sand cannot keep a secret -- the collapse revealed every level it passed")
	runner.check(root.children[Quad.TL].revealed, "including the size-8 it fell through")

func test_reveal_never_heals() -> void:
	# GDD 4.6.1 / invariant 7. Persisted state, not decoration.
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	Strike.apply(root, t, Vector2i(0, 0), 1.0)
	runner.check(root.revealed, "revealed by strike 1")
	Strike.apply(root, t, Vector2i(0, 0), 1.0)
	runner.check(root.revealed, "and still revealed after it breaks")

func test_a_strike_that_does_not_break_still_reveals() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	var res: Strike.Result = Strike.apply(root, t, Vector2i(0, 0), 1.0)
	runner.check_eq(res.broke.size(), 0, "nothing broke")
	runner.check_eq(res.revealed.size(), 1, "but the price of information was paid")

# --------------------------------------------------- pass_through is inert

func test_pass_through_is_carried_in_data_but_not_routed() -> void:
	# GDD 6: Phase 0 supports pass_through in the DATA MODEL and authors `none`.
	# The field must survive resolution so retrofitting it later is wiring, not
	# a schema change -- but nothing routes damage to siblings yet.
	var t: BlockTemplate = _template("""
	{
	  "material": "stone",
	  "default_rule": {
	    "resistance": 1, "on_break": "subdivide", "drop": null,
	    "pass_through": "lateral", "pass_through_falloff": 0.5
	  }
	}
	""")
	var rule: Rule = t.rule_at([] as Array[int], 16)
	runner.check_eq(rule.pass_through, Rule.PassThrough.LATERAL, "the pattern resolves")
	runner.check_eq(rule.pass_through_falloff, 0.5, "so does its falloff")

	var root := BlockNode.new(16)
	Strike.apply(root, t, Vector2i(0, 0), 1.0)
	Strike.apply(root, t, Vector2i(0, 0), 1.0)
	for q: int in [Quad.TR, Quad.BL, Quad.BR]:
		runner.check_eq(root.children[q].damage, 0.0,
			"no damage reached sibling Q%d -- routing is not built yet" % q)
