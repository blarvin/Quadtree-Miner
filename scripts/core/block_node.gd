## A node in a block's quadtree. GDD 4.3, 5.2.
##
## Named BlockNode, not Node, only because Godot owns that name. Everywhere
## else -- the GDD, comments, tests -- it is "the node".
##
## A node stores ONLY what is true of THIS INSTANCE:
##   damage    HP accumulated here (GDD 4.3.1)
##   revealed  whether this node's material/fractures have been shown (4.6.1)
##   children  four children, or none -- NONE IS THE COMMON CASE (4.7.1)
##   size      derived cache, never serialized (5.2, invariant 11)
##
## Its RULE is not here. Rules are looked up from the template by quad-path at
## break time and are never copied onto a node (GDD 4.7.2, invariant 6). The
## test is: does the value differ between two instances of the same material?
## `damage` does. `resistance` does not.
class_name BlockNode
extends RefCounted

## HP, not a hit count (GDD 4.3.1). Continuous, because propagation falloff is
## arithmetic on surplus.
##
## On an INTERIOR node this is a spent record of the blow that broke it, and is
## never read again -- only leaves are struck. It is left as it fell rather
## than zeroed, because zeroing would be a tidier lie about what happened here.
var damage: float = 0.0

## Persisted world state, not decoration (GDD 4.6.1, invariant 7).
## Fractures never heal, so this is only ever set, never cleared.
var revealed: bool = false

## Four children, or empty for a leaf. Created ON BREAK only, and only for
## on_break: subdivide -- `mine` is terminal and never instantiates them
## (invariant 12). An unstruck block is ONE node.
##
## A slot holding null is a child that was MINED: void at that quadrant,
## inside a block that still exists. That is a different fact from
## `children.is_empty()`, which means this node has never subdivided at all.
var children: Array[BlockNode] = []

## DERIVED CACHE -- edge length in atoms (GDD 5.2, invariant 11).
## Single writer: this constructor (load: BlockInstance.size >> depth) and
## subdivide() (child.size = parent.size >> 1). Nothing else ever writes it.
var size: int

func _init(p_size: int) -> void:
	assert(Atoms.is_valid_size(p_size), "node size %d is not a power of two >= 1" % p_size)
	size = p_size

## No children at all -- never subdivided. NOT the same as "all four mined".
func is_leaf() -> bool:
	return children.is_empty()

## That quadrant was mined out. Only meaningful on a subdivided node.
func is_void_at(q: int) -> bool:
	return not children.is_empty() and children[q] == null

## Every child that still exists. A fracture can only draw boundaries between
## these (GDD 4.6.3) -- which is why opacity needs no field.
func live_children() -> Array[BlockNode]:
	var out: Array[BlockNode] = []
	for c: BlockNode in children:
		if c != null:
			out.append(c)
	return out

## The ONLY way children come into existence. GDD 4.3.
func subdivide() -> void:
	assert(is_leaf(), "already subdivided -- children are created exactly once")
	assert(size > Atoms.ATOM, "an atom cannot subdivide (GDD 4.0)")
	var half: int = size >> 1
	for _i: int in 4:
		children.append(BlockNode.new(half))

## Live node count, for the "an unstruck block is one node" claim (GDD 4.7.1).
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
