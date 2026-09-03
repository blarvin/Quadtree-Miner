## What is true of the material at a node (GDD 4.3, 5.1). Never stored on a
## node; looked up from the template by path (GDD 4.7.2).
class_name Rule
extends RefCounted

enum OnBreak { SUBDIVIDE, MINE }

## Sibling propagation (GDD 4.4.2). In the data model now; routing is Phase 2.
enum PassThrough { NONE, INLINE, LATERAL, RADIAL, DOWNWARD }

var resistance: float = 1.0  ## HP threshold, not a hit count (GDD 4.3.1)
var on_break: OnBreak = OnBreak.SUBDIVIDE
var drop: Drop = null
var pass_down: bool = false  ## leftover HP flows to the child under the impact (GDD 4.4.1)
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
	return ON_BREAK_NAMES.find_key(n) if ON_BREAK_NAMES.values().has(n) else -1

static func pass_through_from_name(n: String) -> int:
	return PASS_THROUGH_NAMES.find_key(n) if PASS_THROUGH_NAMES.values().has(n) else -1

func clone() -> Rule:
	var r := Rule.new()
	for f: String in FIELDS:
		r.set(f, get(f))
	return r

## Overrides are partial patches (GDD 4.7.1): only keys present are applied.
## Values are already native (Drop objects, enum ints) from TemplateLoader.
func patched(patch: Dictionary) -> Rule:
	var r := clone()
	for key: String in patch:
		r.set(key, patch[key])
	return r

## What the renderer shows once revealed. A node whose rule yields coal is coal.
func apparent_material(block_material: Materials.Id) -> Materials.Id:
	return drop.material if drop != null else block_material

## Siblings sharing a rule reveal together (GDD 4.6.4). Drop is ignored on a
## subdividing node because it cannot fire there.
func equals(other: Rule) -> bool:
	if other == null:
		return false
	if not is_equal_approx(resistance, other.resistance) or on_break != other.on_break:
		return false
	if on_break == OnBreak.MINE:
		if (drop == null) != (other.drop == null):
			return false
		if drop != null and not drop.equals(other.drop):
			return false
	return pass_down == other.pass_down \
		and is_equal_approx(pass_down_falloff, other.pass_down_falloff) \
		and pass_through == other.pass_through \
		and is_equal_approx(pass_through_falloff, other.pass_through_falloff)

func _to_string() -> String:
	return "Rule(r=%s %s drop=%s down=%s through=%s)" % [
		resistance, ON_BREAK_NAMES[on_break],
		"none" if drop == null else str(drop),
		pass_down, PASS_THROUGH_NAMES[pass_through],
	]
