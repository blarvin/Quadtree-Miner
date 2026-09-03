## One placed block. GDD 4.1, 5.1.
##
## Blocks are ALWAYS SQUARE, so `size` alone gives the extent -- there is no
## separate footprint. Non-square regions are a painter concern: a brush places
## several square blocks and the runtime never knows they were one gesture.
##
## `size` here means exactly what BlockNode.size means -- edge length in atoms --
## and the two are numerically identical at the root. That is what lets
## `size >> 1` read uniformly from the block down to the atom with no special
## case at the top (GDD 5.2).
class_name BlockInstance
extends RefCounted

var origin: Vector2i  ## top-left, in atoms, +Y down
var size: int         ## edge length in atoms. 16 = standard block, 32 = boulder.
## Rules are read from here by path, ALWAYS (GDD 4.7.2, invariant 6). The
## template is never copied into the block, so retuning a material applies
## immediately to a saved world.
var template_id: String
var root: BlockNode

func _init(p_origin: Vector2i, p_size: int, p_template_id: String, p_root: BlockNode = null) -> void:
	assert(Atoms.is_valid_size(p_size), "block size %d is not a power of two >= 1" % p_size)
	origin = p_origin
	size = p_size
	template_id = p_template_id
	## The load writer for BlockNode.size (GDD 5.2): a fresh block is one node.
	root = p_root if p_root != null else BlockNode.new(p_size)
	assert(root.size == size, "root node size must equal the block size")

func rect() -> Rect2i:
	return Rect2i(origin, Vector2i(size, size))

func contains(atom: Vector2i) -> bool:
	return atom.x >= origin.x and atom.y >= origin.y \
		and atom.x < origin.x + size and atom.y < origin.y + size

## World atom -> block-local atom. Everything in Strike is block-local.
func to_local(atom: Vector2i) -> Vector2i:
	return atom - origin

func to_world(local: Vector2i) -> Vector2i:
	return local + origin

func _to_string() -> String:
	return "BlockInstance(%s size %d, %s, %d nodes)" % [
		origin, size, template_id, root.node_count(),
	]
