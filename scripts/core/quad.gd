## Quad-index convention (GDD 4.0.2). +Y is down. 0-based row-major:
##   Q0 = TL   Q1 = TR
##   Q2 = BL   Q3 = BR
## Bit 0 = right, bit 1 = bottom. Locked by tests/test_quad.gd.
class_name Quad

const TL: int = 0
const TR: int = 1
const BL: int = 2
const BR: int = 3

## Which child of the node at `origin` (edge `size`) contains atom `p`?
static func index_of(p: Vector2i, origin: Vector2i, size: int) -> int:
	var half: int = size >> 1
	var right: int = 1 if p.x >= origin.x + half else 0
	var bottom: int = 1 if p.y >= origin.y + half else 0
	return right | (bottom << 1)

## Top-left corner of child `q` of the node at `origin` (edge `size`).
static func child_origin(q: int, origin: Vector2i, size: int) -> Vector2i:
	var half: int = size >> 1
	return origin + Vector2i((q & 1) * half, (q >> 1) * half)
