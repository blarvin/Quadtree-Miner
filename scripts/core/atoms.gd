## The atom is the fixed, physical, engine-wide bottom: the grid resolution
## and the collision unit. It never changes. GDD 4.0.
##
## Sizes everywhere in this codebase are EDGE LENGTHS IN ATOMS -- never a
## depth counted from a root. `BlockInstance.size` and `Node.size` mean
## exactly the same thing and are numerically identical at the root.
class_name Atoms

## FRAMEBUFFER pixels per atom, inside the 640x360 render target. The window
## integer-scales that to the display, so on a 1080p panel (3x) one atom is
## 9 physical px and a size-16 standard block is 144.
##
## 3 was chosen by eye against the GDD 6 legibility sheet at true game scale
## (art/legibility/, run legibility_view.tscn and press 3). Every subdivision
## of a standard block stays a whole number of pixels -- 48, 24, 12, 6, 3 --
## so there are no half-pixel seams at any depth.
const PX: int = 3

const ATOM: int = 1
const STANDARD_BLOCK: int = 16
const CHARACTER_HEIGHT: int = 8

## Phase-0 dev map. GDD 4.1.0.
const WORLD_W: int = 1024
const WORLD_H: int = 1024

static func is_valid_size(size: int) -> bool:
	return size >= 1 and (size & (size - 1)) == 0

## Tree depth is DERIVED, not an identity. GDD 4.0.
static func depth_of(block_size: int, node_size: int) -> int:
	return int(log(float(block_size) / float(node_size)) / log(2.0) + 0.5)
