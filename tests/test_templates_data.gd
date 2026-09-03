## The authored Phase-0 templates behave as GDD 6 describes.
extends RefCounted

var runner: SceneTree

const DIR: String = "res://data/templates"
const PICKAXE: float = 1.0

var _templates: Dictionary = {}

func _tpl(id: String) -> BlockTemplate:
	if _templates.is_empty():
		var errors: PackedStringArray = []
		_templates = TemplateLoader.load_dir(DIR, errors)
		runner.check(errors.is_empty(), "templates loaded clean: %s" % "\n".join(errors))
	var t: BlockTemplate = _templates.get(id)
	runner.check(t != null, "template '%s' exists" % id)
	return t

func _dig(root: BlockNode, t: BlockTemplate, at: Vector2i, n: int) -> Strike.Result:
	var res: Strike.Result = null
	for _i: int in n:
		res = Strike.apply(root, t, at, PICKAXE)
	return res

func test_every_template_binds_at_16_and_4() -> void:
	for id: String in ["honest_dirt", "liar_dirt", "stone", "gift_stone", "sand", "hard_stone"]:
		var t: BlockTemplate = _tpl(id)
		runner.check(t.validate_for_root_size(16).is_empty(), "%s at 16" % id)
		runner.check(t.validate_for_root_size(4).is_empty(), "%s at 4" % id)

func test_honest_dirt_takes_five_strikes_and_vanishes() -> void:
	var root := BlockNode.new(16)
	var t: BlockTemplate = _tpl("honest_dirt")
	runner.check_eq(_dig(root, t, Vector2i.ZERO, 1).broke, [] as Array[int], "strike 1 is a look")
	var s5: Strike.Result = _dig(root, t, Vector2i.ZERO, 4)
	runner.check(s5.mined and s5.yields.is_empty(), "strike 5 mines a size-2, no drop")

func test_the_liar_keeps_one_quadrant_back() -> void:
	var t: BlockTemplate = _tpl("liar_dirt")
	var honest: BlockTemplate = _tpl("honest_dirt")
	runner.check(t.rule_at([] as Array[int], 16).equals(honest.rule_at([] as Array[int], 16)),
		"identical to honest dirt at the root")
	var root := BlockNode.new(16)
	_dig(root, t, Vector2i.ZERO, 2)
	for q: int in [Quad.TL, Quad.TR, Quad.BR]:
		runner.check(_dig(root, t, Quad.child_origin(q, Vector2i.ZERO, 16), 1).broke == ([8] as Array[int]),
			"Q%d crumbles" % q)
	runner.check(_dig(root, t, Vector2i(0, 8), 1).broke.is_empty(), "Q2 does not")
	runner.check_eq(t.rule_at([Quad.BL, Quad.TR] as Array[int], 4).resistance, 8.0, "and lies all the way down")

func test_the_gift_shows_its_coal_before_it_can_be_reached() -> void:
	var t: BlockTemplate = _tpl("gift_stone")
	var root := BlockNode.new(16)
	_dig(root, t, Vector2i(8, 0), 6)  # strike Q1.Q0, the core's neighbour
	var core: BlockNode = root.children[Quad.TR].children[Quad.BL]
	runner.check(core.revealed and core.is_leaf(), "the core is revealed with its siblings, unbroken")
	runner.check_eq(t.rule_at([Quad.TR, Quad.BL] as Array[int], 4).apparent_material(t.material),
		Materials.Id.COAL, "and reads as coal")
	var res: Strike.Result = _dig(root, t, Vector2i(8, 4), 4)  # size-4 core: 2 to split, 2 to mine a size-2
	runner.check(res.mined and res.yields.size() == 1 and res.yields[0].drop.material == Materials.Id.COAL,
		"digging into it pays coal")

func test_sand_collapses_under_one_strike() -> void:
	var root := BlockNode.new(16)
	var res: Strike.Result = _dig(root, _tpl("sand"), Vector2i.ZERO, 1)
	runner.check_eq(res.broke, [16, 8, 4, 2] as Array[int], "one strike bores through")
	runner.check(root.children[Quad.TL].children[Quad.TL].is_void_at(Quad.TL), "leaving a shaft")

func test_the_boulder_cracks_once_and_goes_terminal() -> void:
	var t: BlockTemplate = _tpl("hard_stone")
	var root := BlockNode.new(16)
	runner.check(_dig(root, t, Vector2i.ZERO, 19).broke.is_empty() and root.is_leaf(), "nineteen strikes, nothing")
	runner.check_eq(_dig(root, t, Vector2i.ZERO, 1).broke, [16] as Array[int], "the twentieth cracks it")
	var chunk: Strike.Result = _dig(root, t, Vector2i.ZERO, 20)
	runner.check(chunk.mined and root.is_void_at(Quad.TL), "twenty more take an 8x8 out whole")

func test_two_materials_share_a_colour_class() -> void:
	runner.check_eq(_tpl("stone").colour_class, _tpl("hard_stone").colour_class, "rubble and boulder look alike")
	runner.check(_tpl("stone").material != _tpl("hard_stone").material, "but are different materials")
