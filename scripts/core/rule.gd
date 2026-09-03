## What is true of the MATERIAL at a node. GDD 4.3, 5.1.
##
## A rule is NEVER stored on a node -- it is looked up from the template by
## quad-path at break time (GDD 4.7.2, invariant 6). The split is: does the
## value differ between two instances of the same material? `damage` does, so
## it lives on the Node. `resistance` does not, so it lives here, in one copy.
##
## Names are enums, quantities are numbers (GDD 5.3, invariant 13).
class_name Rule
extends RefCounted

enum OnBreak {
	SUBDIVIDE,  ## -> 4 children of size/2, inheriting this rule
	MINE,       ## TERMINAL -- destroyed, children never instantiated
}

## GDD 4.4.2. Damage flowing to SIBLINGS. Phase 0 authors NONE everywhere and
## the routing is not built (GDD 6) -- but the field is live in the data model
## from day one, because retrofitting it is what would be expensive.
enum PassThrough {
	NONE,
	INLINE,
	LATERAL,
	RADIAL,
	DOWNWARD,
}

## HP threshold to break this node, not a hit count (GDD 4.3.1). Continuous,
## because propagation falloff is arithmetic on surplus HP.
var resistance: float = 1.0
var on_break: OnBreak = OnBreak.SUBDIVIDE
var drop: Drop = null
## GDD 4.4.1. Leftover damage flows to the child under the impact point.
var pass_down: bool = false
var pass_down_falloff: float = 1.0
var pass_through: PassThrough = PassThrough.NONE
var pass_through_falloff: float = 1.0

const FIELDS: PackedStringArray = [
	"resistance", "on_break", "drop",
	"pass_down", "pass_down_falloff",
	"pass_through", "pass_through_falloff",
]

const ON_BREAK_NAMES: Dictionary = {
	OnBreak.SUBDIVIDE: "subdivide",
	OnBreak.MINE: "mine",
}

const PASS_THROUGH_NAMES: Dictionary = {
	PassThrough.NONE: "none",
	PassThrough.INLINE: "inline",
	PassThrough.LATERAL: "lateral",
	PassThrough.RADIAL: "radial",
	PassThrough.DOWNWARD: "downward",
}

static func on_break_from_name(n: String) -> int:
	for k: OnBreak in ON_BREAK_NAMES:
		if ON_BREAK_NAMES[k] == n:
			return k
	return -1

static func pass_through_from_name(n: String) -> int:
	for k: PassThrough in PASS_THROUGH_NAMES:
		if PASS_THROUGH_NAMES[k] == n:
			return k
	return -1

func clone() -> Rule:
	var r := Rule.new()
	r.resistance = resistance
	r.on_break = on_break
	r.drop = drop  ## Drop is treated as immutable, so sharing is safe
	r.pass_down = pass_down
	r.pass_down_falloff = pass_down_falloff
	r.pass_through = pass_through
	r.pass_through_falloff = pass_through_falloff
	return r

## OVERRIDES ARE PARTIAL PATCHES, NOT WHOLE RULES.
##
## GDD 4.5's root override is `resistance: 2` alone; GDD 4.7.1's gem omits the
## pass fields entirely. Both only mean anything if an override LAYERS onto
## what it inherits instead of replacing it. Do not "simplify" this into
## whole-rule replacement -- every authored template would then have to restate
## every field, which is the flat-array authoring GDD 4.7.1 exists to refuse.
##
## `patch` keys are the JSON field names; values are already native (Drop
## objects, enum ints), converted and validated by TemplateLoader.
func patched(patch: Dictionary) -> Rule:
	var r := clone()
	for key: String in patch:
		r.set(key, patch[key])
	return r

## What the RENDERER shows. GDD 4.6 layer 3 -- "now you know it is clay, not
## dirt". A node whose rule yields coal IS coal, so the material shown is
## derived from the authored rule and cannot disagree with it. Same discipline
## as fractures (4.6.2): not a depiction of the rules, but the rules.
##
## This is what makes GDD 6's "gift" a gift -- the coal core is visible because
## its rule yields coal, with no second authored copy of where the coal is.
func apparent_material(block_material: Materials.Id) -> Materials.Id:
	return drop.material if drop != null else block_material

## GDD 4.6.4 -- "siblings SHARING ITS RULE" are revealed together. Sharing a
## rule means BEHAVING THE SAME, so a field that cannot fire is not compared:
## on a subdividing node the drop is inert (subdividing yields children, not
## units), so two subdividing rules that differ only in drop behave identically
## and reveal together. Their difference materialises lower down, where the
## terminal rule actually fires -- which is the reveal ladder doing its job.
##
## on_break itself is always compared, so a TERMINAL core is never equal to a
## subdividing sibling. That is what keeps the hidden core of 4.6.3 dark.
func equals(other: Rule) -> bool:
	if other == null:
		return false
	if not is_equal_approx(resistance, other.resistance):
		return false
	if on_break != other.on_break:
		return false
	if on_break != OnBreak.SUBDIVIDE:
		if (drop == null) != (other.drop == null):
			return false
		if drop != null and not drop.equals(other.drop):
			return false
	if pass_down != other.pass_down:
		return false
	if not is_equal_approx(pass_down_falloff, other.pass_down_falloff):
		return false
	if pass_through != other.pass_through:
		return false
	if not is_equal_approx(pass_through_falloff, other.pass_through_falloff):
		return false
	return true

func _to_string() -> String:
	return "Rule(r=%s %s drop=%s down=%s through=%s)" % [
		resistance, ON_BREAK_NAMES[on_break],
		"none" if drop == null else str(drop),
		pass_down, PASS_THROUGH_NAMES[pass_through],
	]
