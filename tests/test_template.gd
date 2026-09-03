## Locks the sparse-override tree and its resolver. GDD 4.5, 4.7.1, 4.7.2.
##
## The thing under test is the LAYERING ORDER:
##     default_rule -> size:N -> path overrides shallowest to deepest
## and the fact that overrides are PARTIAL PATCHES, not whole rules.
extends RefCounted

var runner: SceneTree

func _load(text: String) -> TemplateLoader.Result:
	return TemplateLoader.from_json_string("test", text)

func _template(text: String) -> BlockTemplate:
	var res: TemplateLoader.Result = _load(text)
	runner.check(res.ok(), "template parsed cleanly, got: %s" % res.describe())
	return res.template

# ------------------------------------------------------------- path keys

func test_path_keys_round_trip() -> void:
	runner.check_eq(BlockTemplate.path_to_key([] as Array[int]), "", "root path is the empty key")
	runner.check_eq(BlockTemplate.path_to_key([1, 2] as Array[int]), "Q1.Q2", "path joins with dots")
	runner.check_eq(BlockTemplate.key_to_path("Q1.Q2"), [1, 2], "key parses back to indices")
	runner.check_eq(BlockTemplate.key_to_path(""), [], "empty key is the root, not an error")
	runner.check_eq(BlockTemplate.key_to_path("Q4"), null, "Q4 is not a quad")
	runner.check_eq(BlockTemplate.key_to_path("Q1.X2"), null, "malformed segment is rejected")
	runner.check_eq(BlockTemplate.key_to_path("1.2"), null, "the Q prefix is required")

func test_size_keys() -> void:
	runner.check(BlockTemplate.is_size_key("size:4"), "size: prefix is recognised")
	runner.check(not BlockTemplate.is_size_key("Q0"), "a quad path is not a size key")
	runner.check_eq(BlockTemplate.size_from_key("size:4"), 4, "size key parses")
	runner.check_eq(BlockTemplate.size_from_key("size:6"), -1, "6 is not a power of two")
	runner.check_eq(BlockTemplate.size_from_key("size:x"), -1, "garbage size is rejected")

# ------------------------------------------------------ the GDD 4.5 ladder

## The prototype block's RULE LADDER (the break sequence itself is Stage 2).
## Fracture-before-commit is a `size:16` rule, NOT a "" path override: a path
## override applies to its node AND BELOW, which would push resistance 2 onto
## every level, and GDD 4.5 wants 2 at the root with 1 at every level below.
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

func test_prototype_rule_ladder() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)

	var root: Rule = t.rule_at([] as Array[int], 16)
	runner.check_eq(root.resistance, 2.0, "root resists 2 -- one look before committing")
	runner.check_eq(root.on_break, Rule.OnBreak.SUBDIVIDE, "the root subdivides")

	var below: Array[Array] = [[0] as Array[int], [0, 1] as Array[int], [3, 3] as Array[int]]
	for path: Array in below:
		var size: int = 16 >> path.size()
		var r: Rule = t.rule_at(path, size)
		runner.check_eq(r.resistance, 1.0, "size %d resists 1 -- below the root it is 1 HP" % size)
		runner.check_eq(r.on_break, Rule.OnBreak.SUBDIVIDE, "size %d still subdivides" % size)

	var deep: Rule = t.rule_at([0, 1, 2] as Array[int], 2)
	runner.check_eq(deep.on_break, Rule.OnBreak.MINE, "size 2 is terminal -- the chunky payoff")
	runner.check_eq(deep.drop.size, 1, "size-2 nodes drop atoms")
	runner.check_eq(deep.drop.count_from(2), 4, "one size-2 node yields 4 atoms at once")

func test_size_override_does_not_inherit_downward() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	runner.check_eq(t.rule_at([] as Array[int], 16).resistance, 2.0, "size:16 hits the size-16 node")
	runner.check_eq(t.rule_at([2] as Array[int], 8).resistance, 1.0,
		"size:16 does NOT leak into the size-8 children")

# ------------------------------------------------- GDD 4.7.1 worked example

## The hidden chunk, verbatim from GDD 4.7.1. `gem` is beyond the Phase-0
## material list, so this uses coal -- the structure is the point.
const HIDDEN_CHUNK: String = """
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

func test_hidden_chunk_resolves_as_documented() -> void:
	var t: BlockTemplate = _template(HIDDEN_CHUNK)

	var core: Rule = t.rule_at([1, 2] as Array[int], 4)
	runner.check_eq(core.resistance, 40.0, "the core needs a better tool")
	runner.check_eq(core.on_break, Rule.OnBreak.MINE, "the core is terminal, so structurally opaque")
	runner.check_eq(core.drop.count_from(4), 1, "one 4x4 lump, not a spray")

	var neighbour: Rule = t.rule_at([1, 3] as Array[int], 4)
	runner.check_eq(neighbour.resistance, 1.0, "the surrounding stone is untouched by the override")
	runner.check_eq(neighbour.on_break, Rule.OnBreak.SUBDIVIDE, "surrounding stone subdivides")

func test_override_applies_to_that_node_and_below() -> void:
	var t: BlockTemplate = _template(HIDDEN_CHUNK)
	# Q1.Q2 is terminal so these children are never instantiated in play
	# (invariant 12) -- but inheritance is still what the resolver must say.
	runner.check_eq(t.rule_at([1, 2, 0] as Array[int], 2).resistance, 40.0,
		"an override applies to its node AND BELOW")
	runner.check_eq(t.rule_at([1] as Array[int], 8).resistance, 1.0,
		"and NOT to its ancestors")

func test_inheritance_reaches_an_unoverridden_deep_path() -> void:
	var t: BlockTemplate = _template(HIDDEN_CHUNK)
	var r: Rule = t.rule_at([0, 0, 0, 0] as Array[int], 1)
	runner.check_eq(r.resistance, 1.0, "an untouched atom still inherits the default")
	runner.check_eq(r.on_break, Rule.OnBreak.SUBDIVIDE, "and its break behaviour")

func test_deeper_override_supersedes_shallower() -> void:
	var t: BlockTemplate = _template("""
	{
	  "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide" },
	  "overrides": {
	    "Q0":    { "resistance": 5 },
	    "Q0.Q3": { "resistance": 9 }
	  }
	}
	""")
	runner.check_eq(t.rule_at([0] as Array[int], 8).resistance, 5.0, "shallow override applies")
	runner.check_eq(t.rule_at([0, 1] as Array[int], 4).resistance, 5.0, "and is inherited")
	runner.check_eq(t.rule_at([0, 3] as Array[int], 4).resistance, 9.0, "until a deeper one supersedes")
	runner.check_eq(t.rule_at([0, 3, 2] as Array[int], 2).resistance, 9.0, "the deeper one then inherits")

# --------------------------------------------------------- layering rules

func test_path_beats_size() -> void:
	# Position is more specific than physical size: a hand-placed core
	# overrules whatever the material does at that size generally.
	var t: BlockTemplate = _template("""
	{
	  "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide" },
	  "overrides": {
	    "size:4": { "resistance": 3 },
	    "Q1.Q2":  { "resistance": 40 }
	  }
	}
	""")
	runner.check_eq(t.rule_at([0, 0] as Array[int], 4).resistance, 3.0, "size rule applies generally")
	runner.check_eq(t.rule_at([1, 2] as Array[int], 4).resistance, 40.0, "a path override wins over it")

func test_size_and_path_layer_field_by_field() -> void:
	# The gift block's shape: a path override sets resistance, a size rule sets
	# the terminal break. Both must survive -- neither replaces the other.
	var t: BlockTemplate = _template("""
	{
	  "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide" },
	  "overrides": {
	    "size:2": { "on_break": "mine", "drop": { "material": "coal", "size": 1 } },
	    "Q1.Q2":  { "resistance": 8 }
	  }
	}
	""")
	var r: Rule = t.rule_at([1, 2, 0] as Array[int], 2)
	runner.check_eq(r.resistance, 8.0, "resistance came from the path override")
	runner.check_eq(r.on_break, Rule.OnBreak.MINE, "the terminal break came from the size rule")
	runner.check_eq(r.drop.material, Materials.Id.COAL, "and so did the drop")

func test_overrides_are_partial_patches() -> void:
	# GDD 4.5's root override is `resistance: 2` alone. If overrides replaced
	# whole rules, every other field would silently reset here.
	var t: BlockTemplate = _template("""
	{
	  "material": "sand",
	  "default_rule": {
	    "resistance": 1, "on_break": "subdivide",
	    "pass_down": true, "pass_down_falloff": 0.5,
	    "pass_through": "radial", "pass_through_falloff": 0.25
	  },
	  "overrides": { "Q0": { "resistance": 7 } }
	}
	""")
	var r: Rule = t.rule_at([0] as Array[int], 8)
	runner.check_eq(r.resistance, 7.0, "the patched field changed")
	runner.check_eq(r.pass_down, true, "pass_down survived the patch")
	runner.check_eq(r.pass_down_falloff, 0.5, "so did its falloff")
	runner.check_eq(r.pass_through, Rule.PassThrough.RADIAL, "and the pass_through pattern")
	runner.check_eq(r.pass_through_falloff, 0.25, "and its falloff")

func test_rules_are_template_authoritative_not_copied() -> void:
	# GDD 4.7.2 / invariant 6: retuning a material must apply immediately.
	# Resolution is memoised, so the same query must return one shared Rule --
	# proof nothing was frozen out into a per-node copy.
	var t: BlockTemplate = _template(PROTOTYPE)
	var a: Rule = t.rule_at([0, 1] as Array[int], 4)
	var b: Rule = t.rule_at([0, 1] as Array[int], 4)
	runner.check(a == b, "the same path and size resolve to the same Rule instance")

# ------------------------------------------------------- reveal comparison

func test_sibling_rule_equality_drives_reveal() -> void:
	# GDD 4.6.4: a strike reveals the node struck AND siblings sharing its
	# rule. A terminal core with a different rule stays hidden.
	var t: BlockTemplate = _template(HIDDEN_CHUNK)
	var core: Rule = t.rule_at([1, 2] as Array[int], 4)
	var sib_a: Rule = t.rule_at([1, 0] as Array[int], 4)
	var sib_b: Rule = t.rule_at([1, 1] as Array[int], 4)
	runner.check(sib_a.equals(sib_b), "plain siblings share a rule and reveal together")
	runner.check(not core.equals(sib_a), "the core does not, so it stays unrevealed")

# ------------------------------------------------------------- validation

func _errors_of(text: String) -> String:
	var res: TemplateLoader.Result = _load(text)
	runner.check(not res.ok(), "this template should have been rejected")
	runner.check(res.template == null, "a rejected template is not handed back")
	return res.describe()

func test_rejects_unknown_material() -> void:
	runner.check(_errors_of("""
		{ "material": "adamantium",
		  "default_rule": { "resistance": 1, "on_break": "subdivide" } }
	""").contains("adamantium"), "the bad material is named in the error")

func test_rejects_air_as_a_material() -> void:
	# Invariant 4: void is the absence of a block. There is no air material,
	# and authoring one must fail rather than quietly work.
	runner.check(_errors_of("""
		{ "material": "air",
		  "default_rule": { "resistance": 1, "on_break": "subdivide" } }
	""").contains("air"), "air is not a material")

func test_rejects_missing_default_rule() -> void:
	runner.check(_errors_of("""{ "material": "dirt" }""").contains("default_rule"),
		"a template without a default_rule is not sparse, it is broken")

func test_rejects_incomplete_default_rule() -> void:
	runner.check(_errors_of("""
		{ "material": "dirt", "default_rule": { "resistance": 1 } }
	""").contains("on_break"), "the default must be complete, only overrides are partial")

func test_rejects_unknown_rule_field() -> void:
	# The field this guards against by name: invariants 8 and 9.
	runner.check(_errors_of("""
		{ "material": "dirt",
		  "default_rule": { "resistance": 1, "on_break": "subdivide", "reveal_depth": 2 } }
	""").contains("reveal_depth"), "there is no reveal_depth field and never will be")

func test_rejects_non_power_of_two_drop() -> void:
	runner.check(_errors_of("""
		{ "material": "coal",
		  "default_rule": { "resistance": 1, "on_break": "mine",
		                    "drop": { "material": "coal", "size": 3 } } }
	""").contains("power of two"), "drop size must be a power of two")

func test_rejects_drop_on_subdivide() -> void:
	runner.check(_errors_of("""
		{ "material": "dirt",
		  "default_rule": { "resistance": 1, "on_break": "subdivide",
		                    "drop": { "material": "coal", "size": 1 } } }
	""").contains("yields children"), "subdividing yields children, not units")

func test_rejects_malformed_override_key() -> void:
	runner.check(_errors_of("""
		{ "material": "dirt",
		  "default_rule": { "resistance": 1, "on_break": "subdivide" },
		  "overrides": { "level3": { "resistance": 2 } } }
	""").contains("malformed"), "depth numbering is not a key -- invariant 1")

func test_rejects_amplifying_falloff() -> void:
	runner.check(_errors_of("""
		{ "material": "sand",
		  "default_rule": { "resistance": 1, "on_break": "subdivide",
		                    "pass_down": true, "pass_down_falloff": 1.5 } }
	""").contains("amplify"), "propagation loses energy, it never gains it")

func test_rejects_empty_override() -> void:
	runner.check(_errors_of("""
		{ "material": "dirt",
		  "default_rule": { "resistance": 1, "on_break": "subdivide" },
		  "overrides": { "Q0": {} } }
	""").contains("says nothing"), "an empty override is a mistake, not a no-op")

func test_accepts_explicit_null_drop() -> void:
	# `drop: null` means "vanishes" and is different from omitting the key.
	var t: BlockTemplate = _template("""
	{
	  "material": "dirt",
	  "default_rule": { "resistance": 1, "on_break": "mine", "drop": null }
	}
	""")
	runner.check(t.default_rule.drop == null, "an explicit null drop yields nothing")

# ---------------------------------------------- checks that need a root size

func test_root_size_binding_catches_too_deep_paths() -> void:
	var t: BlockTemplate = _template("""
	{
	  "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide" },
	  "overrides": { "Q0.Q1.Q2.Q3.Q0": { "resistance": 2 } }
	}
	""")
	runner.check(t.validate_for_root_size(32).is_empty(),
		"5 levels is fine under a size-32 root")
	runner.check(not t.validate_for_root_size(16).is_empty(),
		"but bottoms out below the atom under a size-16 root")

func test_root_size_binding_catches_oversized_drops() -> void:
	# GDD 7: mining finer must never yield more mass than the node held.
	var t: BlockTemplate = _template("""
	{
	  "material": "coal",
	  "default_rule": { "resistance": 1, "on_break": "subdivide" },
	  "overrides": {
	    "size:2": { "on_break": "mine", "drop": { "material": "coal", "size": 4 } }
	  }
	}
	""")
	var problems: PackedStringArray = t.validate_for_root_size(16)
	runner.check(not problems.is_empty(), "a size-2 node cannot yield a size-4 unit")

func test_prototype_is_clean_at_size_16() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	runner.check(t.validate_for_root_size(16).is_empty(),
		"the prototype binds cleanly to a standard block: %s"
			% " ".join(t.validate_for_root_size(16)))
