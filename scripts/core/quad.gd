## Quad-index conventions. GDD 4.0.1-4.0.2.
##
## +Y IS DOWN. Indices are 0-based ROW-MAJOR (Z-order / Morton):
##
##          +X ->
##    +Y   Q0 = TL    Q1 = TR
##     v   Q2 = BL    Q3 = BR
##
## Bit 0 = "am I right?"   Bit 1 = "am I bottom?"
##
## Do not reintroduce depth-numbering (B1..B5, L0..L4) and do not "fix" this
## to 1-based or to winding order (TL,TR,BR,BL). Both destroy the bit
## decomposition that makes sibling selection arithmetic instead of a lookup
## table, and both break path packing. UI may label quads however it likes.
class_name Quad

const TL: int = 0
const TR: int = 1
const BL: int = 2
const BR: int = 3

const BIT_RIGHT: int = 1
const BIT_BOTTOM: int = 2

## Which child of a node at `origin` with edge length `size` contains `p`?
## All coordinates are in atoms. GDD 4.0.2.
static func index_of(p: Vector2i, origin: Vector2i, size: int) -> int:
	var half: int = size >> 1
	var right: int = 1 if p.x >= origin.x + half else 0
	var bottom: int = 1 if p.y >= origin.y + half else 0
	return right | (bottom << 1)

## Top-left corner of child `q` of a node at `origin` with edge length `size`.
static func child_origin(q: int, origin: Vector2i, size: int) -> Vector2i:
	var half: int = size >> 1
	return origin + Vector2i((q & BIT_RIGHT) * half, ((q & BIT_BOTTOM) >> 1) * half)

## Sibling patterns. GDD 4.4.2 -- these are the bit ops the convention buys.
static func sibling_lateral(q: int) -> int:
	return q ^ BIT_RIGHT

static func sibling_vertical(q: int) -> int:
	return q ^ BIT_BOTTOM

## `inline` passes along the axis of the blow.
static func sibling_inline(q: int, axis_is_horizontal: bool) -> int:
	return sibling_lateral(q) if axis_is_horizontal else sibling_vertical(q)

## `downward` -- set the bottom bit (collapsing under its own weight).
static func sibling_downward(q: int) -> int:
	return q | BIT_BOTTOM

## `radial` -- all three siblings.
static func siblings_radial(q: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in 4:
		if i != q:
			out.append(i)
	return out
