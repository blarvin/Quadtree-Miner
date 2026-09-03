## A flat spatial index of non-overlapping blocks. GDD 4.1, 4.1.0.
##
## THERE IS NO GLOBAL QUADTREE. Each block owns its own subdivision tree; the
## "grid" is only a placement resolution. At the dev map's 4,096 blocks this is
## a flat array with a cell index over it -- no chunking, no streaming.
##
## VOID IS THE ABSENCE OF A BLOCK (GDD 4.1.1, invariant 4). block_at() returning
## null IS the void answer. There is no air block to author, store or carve, and
## nothing here ever constructs one.
class_name World
extends RefCounted

## Cell edge for the point-lookup index, in atoms. One standard block: small
## blocks land in one cell, a size-32 boulder spans four. Nothing about the
## quadtree depends on this number -- it is a lookup detail, not a structure.
const CELL: int = Atoms.STANDARD_BLOCK

var extent: Vector2i = Vector2i(Atoms.WORLD_W, Atoms.WORLD_H)
var blocks: Array[BlockInstance] = []
## id -> BlockTemplate. Template-authoritative (GDD 4.7.2): the world stores
## which template, never a copy of what it says.
var templates: Dictionary = {}

var _index: Dictionary = {}  ## Vector2i cell -> Array[BlockInstance]

## What a dig did. Wraps the block-local Strike.Result with the one thing only
## the World knows: where the block was, so yields can be placed in the world.
class Dig extends RefCounted:
	var block: BlockInstance = null   ## null means the point was void
	var result: Strike.Result = null
	var block_removed: bool = false

	## True only if something was actually struck. A point inside a block but
	## in an already-mined quadrant is a miss with a non-null block.
	func hit() -> bool:
		return result != null and result.hit

	## Block-local yield origin -> world atoms.
	func world_origin_of(y: Strike.Yield) -> Vector2i:
		return block.to_world(y.node_origin)

# ------------------------------------------------------------- placement

func add(block: BlockInstance) -> void:
	assert(find_overlap(block.rect()) == null,
		"blocks never overlap (GDD 4.1): %s collides" % block)
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

## The first placed block whose extent intersects `r`, or null. Used by the map
## loader to report a packing mistake properly rather than tripping the assert.
func find_overlap(r: Rect2i) -> BlockInstance:
	for cell: Vector2i in _cells_of(r):
		for b: BlockInstance in _index.get(cell, [] as Array[BlockInstance]):
			if b.rect().intersects(r):
				return b
	return null

# --------------------------------------------------------------- queries

## Which block covers this atom? NULL IS VOID -- that is the whole answer, and
## it is the same query collision and neighbour-reveal need, so void costs
## nothing extra (GDD 4.1.1).
func block_at(atom: Vector2i) -> BlockInstance:
	for b: BlockInstance in _index.get(_cell_of(atom), [] as Array[BlockInstance]):
		if b.contains(atom):
			return b
	return null

## Is there material here? NOT the same as block_at() != null: a block that has
## been dug into has holes in it, and a mined-out quadrant is void inside a
## block that still exists. This is the query collision actually wants.
func is_solid(atom: Vector2i) -> bool:
	var b: BlockInstance = block_at(atom)
	if b == null:
		return false
	return Strike.site_at(b.root, b.to_local(atom)).node != null

func in_bounds(atom: Vector2i) -> bool:
	return atom.x >= 0 and atom.y >= 0 and atom.x < extent.x and atom.y < extent.y

func template_for(block: BlockInstance) -> BlockTemplate:
	var t: BlockTemplate = templates.get(block.template_id)
	assert(t != null, "no template '%s' loaded" % block.template_id)
	return t

func node_count() -> int:
	var n: int = 0
	for b: BlockInstance in blocks:
		n += b.root.node_count()
	return n

# ----------------------------------------------------------------- digging

## Deliver `hp` at a world atom. Routes to the covering block, converts to
## block-local coordinates, and drops the block from the index if its root was
## mined -- because void is the absence of a block at every scale.
func strike(atom: Vector2i, hp: float) -> Dig:
	var dig := Dig.new()
	var b: BlockInstance = block_at(atom)
	if b == null:
		return dig  # void: nothing to hit
	dig.block = b
	dig.result = Strike.apply(b.root, template_for(b), b.to_local(atom), hp)
	if dig.result.block_destroyed:
		remove(b)
		dig.block_removed = true
	return dig

# ------------------------------------------------------------------ index

static func _cell_of(atom: Vector2i) -> Vector2i:
	## floori, not integer division -- the latter rounds toward zero and would
	## fold -1 and 0 into the same cell. Origins are non-negative on the dev
	## map, but nothing in GDD 4.1 says they must be.
	return Vector2i(floori(float(atom.x) / CELL), floori(float(atom.y) / CELL))

static func _cells_of(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo: Vector2i = _cell_of(r.position)
	var hi: Vector2i = _cell_of(r.position + r.size - Vector2i.ONE)
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out
