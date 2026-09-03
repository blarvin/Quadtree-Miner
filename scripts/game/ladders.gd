## Placed ladder units (GDD 3.1.1): 8x8 entities on the atom grid, not blocks.
## Engine-pure so it can be tested and saved.
class_name Ladders
extends RefCounted

var unit: int = 8
var units: Array[Rect2i] = []

func overlapping(r: Rect2i) -> Rect2i:
	for u: Rect2i in units:
		if u.intersects(r):
			return u
	return Rect2i()

func overlaps(r: Rect2i) -> bool:
	return overlapping(r).size != Vector2i.ZERO

## Place a unit for a character whose box is `body`. If the body overlaps a
## ladder, the new unit snaps to that ladder's column and stacks directly
## above or below it (whichever side the body's centre is on), so ladders
## always join. Otherwise it goes exactly where the body is.
## Returns the placed rect, or an empty Rect2i if the target is not clear void.
func place(body: Rect2i, world: World) -> Rect2i:
	var target := Rect2i(body.position, Vector2i(unit, unit))
	var over: Rect2i = overlapping(body)
	if over.size != Vector2i.ZERO:
		var above: bool = body.position.y + body.size.y / 2 <= over.position.y + over.size.y / 2
		target.position = Vector2i(over.position.x, over.position.y + (-unit if above else unit))
	if overlaps(target):
		return Rect2i()
	for y: int in range(target.position.y, target.end.y):
		for x: int in range(target.position.x, target.end.x):
			var a := Vector2i(x, y)
			if not world.in_bounds(a) or world.is_solid(a):
				return Rect2i()
	units.append(target)
	return target
