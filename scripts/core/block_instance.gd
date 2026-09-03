## One placed block (GDD 4.1, 5.1). Always square; `size` is its whole extent
## and equals the root node's size.
class_name BlockInstance
extends RefCounted

var origin: Vector2i  ## top-left, in atoms
var size: int         ## edge length in atoms
var template_id: String  ## rules are always read from here (GDD 4.7.2)
var root: BlockNode

func _init(p_origin: Vector2i, p_size: int, p_template_id: String, p_root: BlockNode = null) -> void:
	assert(Atoms.is_valid_size(p_size), "block size %d is not a power of two >= 1" % p_size)
	origin = p_origin
	size = p_size
	template_id = p_template_id
	root = p_root if p_root != null else BlockNode.new(p_size)
	assert(root.size == size, "root node size must equal the block size")

func rect() -> Rect2i:
	return Rect2i(origin, Vector2i(size, size))

func contains(atom: Vector2i) -> bool:
	return rect().has_point(atom)

func to_local(atom: Vector2i) -> Vector2i:
	return atom - origin

func to_world(local: Vector2i) -> Vector2i:
	return local + origin

func _to_string() -> String:
	return "BlockInstance(%s size %d, %s, %d nodes)" % [origin, size, template_id, root.node_count()]
