## A SPARSE OVERRIDE TREE. GDD 4.7.1, invariant 5.
##
## Never a flat 256-cell array. A homogeneous template is a `default_rule` and
## nothing else, and an unstruck block is ONE node in memory.
##
## TWO KINDS OF OVERRIDE KEY
## -------------------------
##   "Q1.Q2"  quad-path -- POSITION. Applies to that node AND EVERYTHING
##            BELOW it, until a deeper path override supersedes. Root-relative,
##            so it names a different physical size under a size-32 root than
##            under a size-16 one (GDD 4.7.1). "" is the root.
##
##   "size:2" SIZE -- PHYSICAL FACT. Applies to any node of that edge length,
##            and does NOT inherit downward. This is GDD 4.7's "at what node
##            size the material becomes minable" given somewhere to live.
##            Without it, "every size-2 node is terminal" needs 64 path keys --
##            exactly the flat-array authoring 4.7.1 refuses.
##
## LAYERING ORDER (later wins, field by field):
##
##     default_rule  ->  size:N for this node's size  ->  path overrides,
##                                                        shallowest to deepest
##
## Path last means POSITION BEATS SIZE, which is what you want: a hand-placed
## gem at "Q1.Q2" overrules whatever the material does at size 4 generally.
## It falls out of the ordering -- there is no field-by-field bookkeeping.
##
## Note this is why GDD 4.5's fracture-before-commit is a `size:16` rule and
## not a `""` path override: `""` would push resistance 2 onto every node in
## the block, and 4.5 wants 2 at the root with 1 at every level below.
class_name BlockTemplate
extends RefCounted

const SIZE_PREFIX: String = "size:"
const ROOT_PATH: String = ""

var id: String = ""
var material: Materials.Id = Materials.Id.DIRT
var colour_class: Materials.ColourClass = Materials.ColourClass.BROWN
var display_skin: String = ""
var default_rule: Rule = null

## String canonical path -> partial patch Dictionary
var path_overrides: Dictionary = {}
## int size in atoms -> partial patch Dictionary
var size_overrides: Dictionary = {}

## Memoised resolution. Legal under GDD 4.7.2 / invariant 6: the template stays
## authoritative and nothing is copied onto a Node. Rules handed out are treated
## as immutable -- never mutate a Rule returned by rule_at().
var _cache: Dictionary = {}

# ---------------------------------------------------------------- path keys

static func path_to_key(path: Array[int]) -> String:
	if path.is_empty():
		return ROOT_PATH
	var parts: PackedStringArray = []
	for q: int in path:
		parts.append("Q%d" % q)
	return ".".join(parts)

## Empty array for the root. Returns null (not []) when the key is malformed,
## so callers can tell "root" from "garbage".
static func key_to_path(key: String) -> Variant:
	var out: Array[int] = []
	if key == ROOT_PATH:
		return out
	for part: String in key.split("."):
		if part.length() != 2 or part[0] != "Q":
			return null
		if not part[1].is_valid_int():
			return null
		var q: int = int(part[1])
		if q < 0 or q > 3:
			return null
		out.append(q)
	return out

static func is_size_key(key: String) -> bool:
	return key.begins_with(SIZE_PREFIX)

## -1 when malformed or not a valid size.
static func size_from_key(key: String) -> int:
	var tail: String = key.substr(SIZE_PREFIX.length())
	if not tail.is_valid_int():
		return -1
	var n: int = int(tail)
	return n if Atoms.is_valid_size(n) else -1

# ------------------------------------------------------------- resolution

## The rule for the node at `path` under this template, whose edge length is
## `size` atoms. Both are needed: paths address position, size addresses
## physical fact, and the two override kinds key on one each.
func rule_at(path: Array[int], size: int) -> Rule:
	var cache_key: String = "%d|%s" % [size, path_to_key(path)]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var r: Rule = default_rule.clone()
	if size_overrides.has(size):
		r = r.patched(size_overrides[size])
	## Shallowest to deepest, root included: an override applies to its node
	## and everything below, so every ancestor's patch is still in force.
	var prefix: Array[int] = []
	if path_overrides.has(ROOT_PATH):
		r = r.patched(path_overrides[ROOT_PATH])
	for q: int in path:
		prefix.append(q)
		var key: String = path_to_key(prefix)
		if path_overrides.has(key):
			r = r.patched(path_overrides[key])

	_cache[cache_key] = r
	return r

## Convenience for tests and authoring checks.
func rule_at_key(key: String, size: int) -> Rule:
	var path: Variant = key_to_path(key)
	assert(path != null, "malformed quad-path key: %s" % key)
	return rule_at(path, size)

# ------------------------------------------------------- size-bound checks

## Checks that can only be made once the template is BOUND TO A BLOCK SIZE.
## Templates are size-agnostic by design (GDD 4.7.1: paths are root-relative),
## so "is this path too deep?" and "does this drop yield more mass than the
## node held?" are questions the map loader asks, not the template loader.
##
## Returns human-readable problems; empty means clean.
func validate_for_root_size(root_size: int) -> PackedStringArray:
	var problems: PackedStringArray = []
	if not Atoms.is_valid_size(root_size):
		problems.append("root size %d is not a power of two >= 1" % root_size)
		return problems

	for key: String in path_overrides:
		var path: Array[int] = key_to_path(key)
		var node_size: int = root_size >> path.size()
		if node_size < 1:
			problems.append("override '%s' is %d levels deep, but a size-%d root bottoms out at %d"
				% [key, path.size(), root_size, Atoms.depth_of(root_size, 1)])
			continue
		_check_drop_fits(path_overrides[key], node_size, "override '%s'" % key, problems)

	for size: int in size_overrides:
		if size > root_size:
			problems.append("override 'size:%d' is larger than the size-%d root" % [size, root_size])
			continue
		_check_drop_fits(size_overrides[size], size, "override 'size:%d'" % size, problems)

	_check_drop_fits(default_rule_patch(), root_size, "default_rule", problems)
	return problems

## default_rule as a patch dict, for the shared drop check above.
func default_rule_patch() -> Dictionary:
	return {"on_break": default_rule.on_break, "drop": default_rule.drop}

static func _check_drop_fits(patch: Dictionary, node_size: int, ctx: String,
		problems: PackedStringArray) -> void:
	var drop: Variant = patch.get("drop")
	if drop == null:
		return
	var d: Drop = drop
	if d.size > node_size:
		## GDD 7: mining finer must never yield more mass than the node held.
		problems.append("%s drops size-%d units from a size-%d node" % [ctx, d.size, node_size])

func _to_string() -> String:
	return "BlockTemplate(%s, %s, %d path + %d size overrides)" % [
		id, Materials.name_of(material), path_overrides.size(), size_overrides.size(),
	]
