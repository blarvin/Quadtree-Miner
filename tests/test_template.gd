## Override trees: parsing, resolution order, validation (GDD 4.7.1).
extends RefCounted

var runner: SceneTree

func _template(text: String) -> BlockTemplate:
	var errors: PackedStringArray = []
	var t: BlockTemplate = TemplateLoader.from_json_string("test", text, errors)
	runner.check(t != null, "template parsed: %s" % "\n".join(errors))
	return t

func _errors_of(text: String) -> String:
	var errors: PackedStringArray = []
	var t: BlockTemplate = TemplateLoader.from_json_string("bad", text, errors)
	runner.check(t == null, "should have been rejected")
	return "\n".join(errors)

func _rule(t: BlockTemplate, key: String, size: int) -> Rule:
	return t.rule_at(BlockTemplate.key_to_path(key), size)

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

func test_path_keys_round_trip() -> void:
	runner.check_eq(BlockTemplate.key_to_path(""), [] as Array[int], "'' is the root")
	runner.check_eq(BlockTemplate.key_to_path("Q1.Q2.Q0"), [1, 2, 0] as Array[int], "parses")
	runner.check_eq(BlockTemplate.path_to_key([1, 2, 0] as Array[int]), "Q1.Q2.Q0", "formats")
	for bad: String in ["Q4", "q1", "Q1.", "1.2", "Q12"]:
		runner.check(BlockTemplate.key_to_path(bad) == null, "'%s' is malformed" % bad)
	runner.check_eq(BlockTemplate.size_from_key("size:4"), 4, "size key parses")
	runner.check_eq(BlockTemplate.size_from_key("size:3"), -1, "non-power-of-two rejected")

func test_prototype_rule_ladder() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	runner.check_eq(_rule(t, "", 16).resistance, 2.0, "root resists 2")
	runner.check_eq(_rule(t, "Q0", 8).resistance, 1.0, "size 8 resists 1")
	runner.check_eq(_rule(t, "Q0.Q0.Q0", 2).on_break, Rule.OnBreak.MINE, "size 2 is terminal")
	runner.check_eq(_rule(t, "Q0.Q0", 4).on_break, Rule.OnBreak.SUBDIVIDE, "size key does not inherit downward or upward")

func test_path_override_applies_to_that_node_and_below() -> void:
	var t: BlockTemplate = _template("""
	{ "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null },
	  "overrides": { "Q2": { "resistance": 8 }, "Q2.Q1": { "resistance": 3 } } }
	""")
	runner.check_eq(_rule(t, "Q2", 8).resistance, 8.0, "the node itself")
	runner.check_eq(_rule(t, "Q2.Q3.Q0", 2).resistance, 8.0, "and everything below")
	runner.check_eq(_rule(t, "Q2.Q1.Q0", 2).resistance, 3.0, "until a deeper override supersedes")
	runner.check_eq(_rule(t, "Q0.Q2", 4).resistance, 1.0, "a Q2 elsewhere is ordinary")

func test_position_beats_size_and_patches_layer_field_by_field() -> void:
	var t: BlockTemplate = _template("""
	{ "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null, "pass_down": true },
	  "overrides": {
	    "size:4": { "resistance": 5, "on_break": "mine" },
	    "Q1.Q2":  { "resistance": 40 } } }
	""")
	var r: Rule = _rule(t, "Q1.Q2", 4)
	runner.check_eq(r.resistance, 40.0, "path wins on resistance")
	runner.check_eq(r.on_break, Rule.OnBreak.MINE, "size key's on_break still applies")
	runner.check(r.pass_down, "default's pass_down still applies")

func test_rules_are_not_copied_onto_nodes() -> void:
	var t: BlockTemplate = _template(PROTOTYPE)
	var root := BlockNode.new(16)
	Strike.apply(root, t, Vector2i.ZERO, 1.0)
	t.default_rule.resistance = 100.0
	t._cache.clear()
	runner.check_eq(_rule(t, "Q0", 8).resistance, 100.0, "retuning applies immediately")

func test_sibling_rule_equality_ignores_inert_drop() -> void:
	var a := Rule.new()
	var b := Rule.new()
	b.drop = Drop.new(Materials.Id.COAL, 1)
	runner.check(a.equals(b), "drop is inert on a subdividing rule")
	a.on_break = Rule.OnBreak.MINE
	b.on_break = Rule.OnBreak.MINE
	runner.check(not a.equals(b), "but decisive on a terminal one")

func test_rejections() -> void:
	runner.check(_errors_of('{"material": "air", "default_rule": {"resistance": 1, "on_break": "subdivide"}}')
		.contains("unknown material"), "void is not a material")
	runner.check(_errors_of('{"material": "dirt"}').contains("default_rule"), "default_rule required")
	runner.check(_errors_of('{"material": "dirt", "default_rule": {"resistance": 1}}')
		.contains("on_break"), "default_rule needs on_break")
	runner.check(_errors_of('{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "subdivide", "hp": 3}}')
		.contains("unknown rule field"), "unknown field")
	runner.check(_errors_of('{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "mine", "drop": {"material": "coal", "size": 3}}}')
		.contains("power of two"), "drop size must be a power of two")
	runner.check(_errors_of('{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "subdivide", "drop": {"material": "coal", "size": 1}}}')
		.contains("yields children"), "subdivide with a drop")
	runner.check(_errors_of('{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "subdivide"}, "overrides": {"Q5": {"resistance": 2}}}')
		.contains("malformed key"), "bad override key")
	runner.check(_errors_of('{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "subdivide", "pass_down_falloff": 2}}')
		.contains("0..1"), "falloff cannot amplify")
	runner.check(_errors_of('{"material": "dirt", "default_rule": {"resistance": 1, "on_break": "subdivide"}, "overrides": {"Q0": {}}}')
		.contains("empty"), "empty override")

func test_notes_are_ignored() -> void:
	var t: BlockTemplate = _template('{"_": "note", "material": "dirt", "default_rule": {"_why": "x", "resistance": 1, "on_break": "subdivide"}}')
	runner.check_eq(t.default_rule.resistance, 1.0, "parsed around the notes")

func test_root_size_binding() -> void:
	var t: BlockTemplate = _template("""
	{ "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "subdivide", "drop": null },
	  "overrides": {
	    "Q0.Q0.Q0": { "resistance": 2 },
	    "size:4": { "on_break": "mine", "drop": { "material": "coal", "size": 4 } } } }
	""")
	runner.check(t.validate_for_root_size(16).is_empty(), "clean at size 16")
	var at4: String = " ".join(t.validate_for_root_size(4))
	runner.check(at4.contains("deeper than the atom"), "a 3-deep path under a size-4 root")
	var at2: String = " ".join(t.validate_for_root_size(2))
	runner.check(not at2.contains("size:4"), "a size key above the root is inert, not wrong")
	var big := _template("""
	{ "material": "stone",
	  "default_rule": { "resistance": 1, "on_break": "mine", "drop": { "material": "coal", "size": 8 } } }
	""")
	runner.check(" ".join(big.validate_for_root_size(4)).contains("drops size-8"), "drop larger than the node")
