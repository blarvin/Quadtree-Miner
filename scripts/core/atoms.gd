## Every size in this codebase is an edge length in atoms (GDD 4.0).
## The atom is the grid resolution and the collision unit; no root size is special.
class_name Atoms

static func is_valid_size(size: int) -> bool:
	return size >= 1 and (size & (size - 1)) == 0
