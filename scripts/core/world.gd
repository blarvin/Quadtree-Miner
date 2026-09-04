## A flat spatial index of non-overlapping blocks (GDD 4.1). No global
## quadtree. Void is the absence of a block: block_at() == null is the answer.
class_name World
extends RefCounted

## Edge of the point-lookup index cells, in atoms. A lookup detail only.
const CELL: int = 16

var extent: Vector2i = Vector2i.ZERO
var blocks: Array[BlockInstance] = []
var templates: Dictionary = {}  ## id -> BlockTemplate

var _index: Dictionary = {}  ## Vector2i cell -> Array[BlockInstance]

class Dig extends RefCounted:
	var block: BlockInstance = null  ## null: the point was void
	var result: Strike.Result = null
	var block_removed: bool = false

	func hit() -> bool:
		return result != null and result.hit

	func world_origin_of(y: Strike.Yield) -> Vector2i:
		return block.to_world(y.node_origin)

func add(block: BlockInstance) -> void:
	assert(find_overlap(block.rect()) == null, "blocks never overlap (GDD 4.1): %s" % block)
	blocks.append(block)
	for cell: Vector2i in _cells_of(block.rect()):
		if not _index.has(cell):
			_index[cell] = [] as Array[BlockInstance]
		_index[cell].append(block)

func remove(block: BlockInstance) -> void:
	blocks.erase(block)
	for cell: Vector2i in _cells_of(block.rect()):
		if _index.has(cell):
			_index[cell].erase(block)
			if _index[cell].is_empty():
				_index.erase(cell)

func find_overlap(r: Rect2i) -> BlockInstance:
	for cell: Vector2i in _cells_of(r):
		for b: BlockInstance in _index.get(cell, [] as Array[BlockInstance]):
			if b.rect().intersects(r):
				return b
	return null

## Every block touching `r`, each once. A block spans several index cells, so
## the dedupe is the point. Culling and the painter's overlap rule both want it.
func blocks_in(r: Rect2i) -> Array[BlockInstance]:
	var out: Array[BlockInstance] = []
	var seen: Dictionary = {}
	for cell: Vector2i in _cells_of(r):
		for b: BlockInstance in _index.get(cell, [] as Array[BlockInstance]):
			if not seen.has(b) and b.rect().intersects(r):
				seen[b] = true
				out.append(b)
	return out

func block_at(atom: Vector2i) -> BlockInstance:
	for b: BlockInstance in _index.get(_cell_of(atom), [] as Array[BlockInstance]):
		if b.contains(atom):
			return b
	return null

## Is there material at this atom? A mined-out quadrant inside a block is void.
## This is the query collision wants.
func is_solid(atom: Vector2i) -> bool:
	var b: BlockInstance = block_at(atom)
	return b != null and Strike.site_at(b.root, b.to_local(atom)).node != null

func in_bounds(atom: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, extent).has_point(atom)

func template_for(block: BlockInstance) -> BlockTemplate:
	var t: BlockTemplate = templates.get(block.template_id)
	assert(t != null, "no template '%s' loaded" % block.template_id)
	return t

func node_count() -> int:
	var n: int = 0
	for b: BlockInstance in blocks:
		n += b.root.node_count()
	return n

## Deliver `hp` at a world atom.
func strike(atom: Vector2i, hp: float) -> Dig:
	var dig := Dig.new()
	var b: BlockInstance = block_at(atom)
	if b == null:
		return dig
	dig.block = b
	dig.result = Strike.apply(b.root, template_for(b), b.to_local(atom), hp)
	if dig.result.block_destroyed:
		remove(b)
		dig.block_removed = true
	return dig

static func _cell_of(atom: Vector2i) -> Vector2i:
	return Vector2i(floori(float(atom.x) / CELL), floori(float(atom.y) / CELL))

static func _cells_of(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo: Vector2i = _cell_of(r.position)
	var hi: Vector2i = _cell_of(r.end - Vector2i.ONE)
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out
