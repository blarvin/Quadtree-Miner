## A node in a block's quadtree (GDD 4.3, 5.2). Stores only what is true of
## this instance; its rule is looked up from the template by path.
class_name BlockNode
extends RefCounted

var damage: float = 0.0     ## HP taken (GDD 4.3.1). Persisted.
var revealed: bool = false  ## Persisted; only ever set, never cleared (GDD 4.6.1).

## Empty = leaf (never subdivided). A null slot = that quadrant was mined out.
var children: Array[BlockNode] = []

## Derived cache, never serialized (GDD 5.2). Written only here and in subdivide().
var size: int

func _init(p_size: int) -> void:
	assert(Atoms.is_valid_size(p_size), "node size %d is not a power of two >= 1" % p_size)
	size = p_size

func is_leaf() -> bool:
	return children.is_empty()

func is_void_at(q: int) -> bool:
	return not children.is_empty() and children[q] == null

## A fracture can only draw boundaries between these (GDD 4.6.3).
func live_children() -> Array[BlockNode]:
	var out: Array[BlockNode] = []
	for c: BlockNode in children:
		if c != null:
			out.append(c)
	return out

## The only way children come into existence.
func subdivide() -> void:
	assert(is_leaf(), "already subdivided")
	assert(size > 1, "an atom cannot subdivide (GDD 4.0)")
	for _i: int in 4:
		children.append(BlockNode.new(size >> 1))

func node_count() -> int:
	var n: int = 1
	for c: BlockNode in children:
		if c != null:
			n += c.node_count()
	return n

func _to_string() -> String:
	return "BlockNode(size %d, dmg %s%s%s)" % [
		size, damage,
		", revealed" if revealed else "",
		", %d children" % children.size() if not is_leaf() else "",
	]
