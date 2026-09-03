## A sparse override tree (GDD 4.7.1). Two kinds of key:
##   "Q1.Q2"  position -- applies to that node and everything below it
##   "size:2" physical size -- applies to any node of that edge, no inheritance
## Resolution, later wins field by field:
##   default_rule -> size:N -> path overrides shallowest to deepest
class_name BlockTemplate
extends RefCounted

const SIZE_PREFIX: String = "size:"
const ROOT_PATH: String = ""

var id: String = ""
var material: Materials.Id = Materials.Id.DIRT
var colour_class: Materials.ColourClass = Materials.ColourClass.BROWN
var display_skin: String = ""
var default_rule: Rule = null
var path_overrides: Dictionary = {}  ## canonical path key -> patch
var size_overrides: Dictionary = {}  ## size in atoms -> patch

var _cache: Dictionary = {}  ## rules handed out are treated as immutable

static func path_to_key(path: Array[int]) -> String:
	var parts: PackedStringArray = []
	for q: int in path:
		parts.append("Q%d" % q)
	return ".".join(parts)

## Empty array for the root; null when malformed.
static func key_to_path(key: String) -> Variant:
	var out: Array[int] = []
	if key == ROOT_PATH:
		return out
	for part: String in key.split("."):
		if part.length() != 2 or part[0] != "Q" or not part[1].is_valid_int():
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

## The rule for the node at `path` whose edge length is `size`.
func rule_at(path: Array[int], size: int) -> Rule:
	var cache_key: String = "%d|%s" % [size, path_to_key(path)]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var r: Rule = default_rule.clone()
	if size_overrides.has(size):
		r = r.patched(size_overrides[size])
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

## Checks that only make sense once the template is bound to a block size:
## paths deeper than the atom, and drops larger than the node (GDD 7).
func validate_for_root_size(root_size: int) -> PackedStringArray:
	var problems: PackedStringArray = []
	if not Atoms.is_valid_size(root_size):
		problems.append("root size %d is not a power of two >= 1" % root_size)
		return problems
	for key: String in path_overrides:
		var path: Array[int] = key_to_path(key)
		var node_size: int = root_size >> path.size()
		if node_size < 1:
			problems.append("override '%s' is deeper than the atom under a size-%d root" % [key, root_size])
			continue
		_check_drop_fits(path_overrides[key].get("drop"), node_size, "override '%s'" % key, problems)
	for size: int in size_overrides:
		if size <= root_size:  # a size key above the root is inert, not wrong
			_check_drop_fits(size_overrides[size].get("drop"), size, "override 'size:%d'" % size, problems)
	_check_drop_fits(default_rule.drop, root_size, "default_rule", problems)
	return problems

static func _check_drop_fits(drop: Variant, node_size: int, ctx: String,
		problems: PackedStringArray) -> void:
	if drop != null and (drop as Drop).size > node_size:
		problems.append("%s drops size-%d units from a size-%d node" % [ctx, (drop as Drop).size, node_size])

func _to_string() -> String:
	return "BlockTemplate(%s, %s, %d path + %d size overrides)" % [
		id, Materials.name_of(material), path_overrides.size(), size_overrides.size(),
	]
