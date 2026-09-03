## What comes out when a node is mined. GDD 4.3, 5.1.
##
## `drop` answers ONLY "what -- if anything -- comes out". Whether the node is
## destroyed is `Rule.on_break` (invariant 12). `drop: none` is not a different
## kind of break; it is a break that yields nothing.
class_name Drop
extends RefCounted

var material: Materials.Id
var size: int  ## edge length in atoms of ONE yielded unit

func _init(p_material: Materials.Id, p_size: int) -> void:
	material = p_material
	size = p_size

## DERIVED, never authored (GDD 4.7, invariant 12). A size-4 node dropping at
## size 1 yields 16; at size 2, 4; at size 4, one lump.
##
## The assert is GDD 7's anti-exploit: mining finer must never yield more mass
## than the node held. `drop.size > node.size` would do exactly that.
func count_from(node_size: int) -> int:
	assert(size >= 1 and size <= node_size,
		"drop.size %d out of range for a size-%d node" % [size, node_size])
	var per_edge: int = node_size / size
	return per_edge * per_edge

func equals(other: Drop) -> bool:
	if other == null:
		return false
	return material == other.material and size == other.size

func to_json() -> Dictionary:
	return {"material": Materials.name_of(material), "size": size}

func _to_string() -> String:
	return "%s x size %d" % [Materials.name_of(material), size]
