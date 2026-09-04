## Brush strokes as MapEdits (GDD 6, Phase 1 authoring). Engine-pure: no Node,
## no input, so the overlap rule is testable headless.
##
## The overlap rule: a stamp deletes every block its footprint touches, whole.
## What a deleted block covered outside the footprint becomes void, which is a
## legal state (GDD 4.1.1) -- paint over it if you don't want it.
##
## Blocks are NOT split to fit. Rules resolve by path from a block's own root
## (GDD 4.7.2), so four size-8 roots are not the size-16 root they came from:
## splitting would silently rewrite the terrain's behaviour.
class_name PaintOps

## A brush places `n` x `n` blocks of edge `size`, so the footprint is n*size
## atoms square. `origin` is its top-left in atoms; free placement is allowed.
static func footprint(origin: Vector2i, size: int, n: int) -> Rect2i:
	return Rect2i(origin, Vector2i(size * n, size * n))

static func stamp(world: World, origin: Vector2i, size: int, n: int,
		template_id: String) -> MapEdit:
	var e := MapEdit.new()
	var fp: Rect2i = footprint(origin, size, n)
	e.removed = world.blocks_in(fp)
	for by: int in n:
		for bx: int in n:
			var at: Vector2i = origin + Vector2i(bx * size, by * size)
			e.added.append(BlockInstance.new(at, size, template_id))
	return e

## Same footprint, nothing placed.
static func erase(world: World, origin: Vector2i, size: int, n: int) -> MapEdit:
	var e := MapEdit.new()
	e.removed = world.blocks_in(footprint(origin, size, n))
	return e

## One block of every template, left to right at `origin`: the bench for
## judging a new template without authoring terrain around it.
static func bench(world: World, origin: Vector2i, size: int,
		template_ids: Array) -> MapEdit:
	var e := MapEdit.new()
	var span: int = size * 2  ## a gap of one block between neighbours
	var fp := Rect2i(origin, Vector2i(span * template_ids.size(), size))
	e.removed = world.blocks_in(fp)
	for i: int in template_ids.size():
		var at: Vector2i = origin + Vector2i(i * span, 0)
		e.added.append(BlockInstance.new(at, size, str(template_ids[i])))
	return e

## The same blocks with untouched trees. Damage and reveal are play, not
## authoring (GDD 4.6.1), so a map saved mid-dig must not carry them back in.
static func pristine(world: World) -> World:
	var out := World.new()
	out.extent = world.extent
	out.templates = world.templates
	for b: BlockInstance in world.blocks:
		out.add(BlockInstance.new(b.origin, b.size, b.template_id))
	return out

## Authoring needs honest_dirt tellable from liar_dirt; the game's two colour
## classes (GDD 4.6) do not tell them apart. A stable per-id tint over the real
## class colour keeps the palette honest and the blocks distinguishable.
static func authoring_tint(id: String, base: Color, mix: float = 0.30) -> Color:
	var hue: float = float(absi(hash(id)) % 360) / 360.0
	return base.lerp(Color.from_hsv(hue, 0.55, 0.85), mix)

## Snap to the brush's own block size, so every block sits on its own lattice.
static func snap(atom: Vector2i, size: int) -> Vector2i:
	return Vector2i(_floor_to(atom.x, size), _floor_to(atom.y, size))

static func _floor_to(v: int, step: int) -> int:
	return (v / step) * step if v >= 0 else -(((-v + step - 1) / step) * step)
