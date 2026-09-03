## What comes out when a node is mined (GDD 4.3, 5.1). Whether the node is
## destroyed is Rule.on_break; a null Drop means it vanishes.
class_name Drop
extends RefCounted

var material: Materials.Id
var size: int  ## edge length in atoms of one yielded unit

func _init(p_material: Materials.Id, p_size: int) -> void:
	material = p_material
	size = p_size

## Count is derived, never authored: (node.size / drop.size)^2.
func count_from(node_size: int) -> int:
	assert(size >= 1 and size <= node_size,
		"drop.size %d out of range for a size-%d node" % [size, node_size])
	var per_edge: int = node_size / size
	return per_edge * per_edge

func equals(other: Drop) -> bool:
	return other != null and material == other.material and size == other.size

func _to_string() -> String:
	return "%s x size %d" % [Materials.name_of(material), size]
