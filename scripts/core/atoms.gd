## The atom is the fixed, physical, engine-wide bottom: the grid resolution
## and the collision unit. It never changes. GDD 4.0.
##
## Sizes everywhere in this codebase are EDGE LENGTHS IN ATOMS -- never a
## depth counted from a root. `BlockInstance.size` and `Node.size` mean
## exactly the same thing and are numerically identical at the root.
class_name Atoms

## Screen pixels per atom. A size-16 standard block is therefore 64px --
## the baseline the GDD 6 legibility test is written against. Tunable.
const PX: int = 4

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
