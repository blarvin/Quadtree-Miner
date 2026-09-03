## The Phase-0 material list. GDD 4.7, 4.1.1.
##
## Void is NOT here and never will be -- empty space is the absence of a
## block (GDD 4.1.1, invariant 4). There is no air material to add.
##
## Names are symbolic, so they are an enum (GDD 5.3, invariant 13).
class_name Materials

enum Id {
	DIRT,
	STONE,
	HARD_STONE,
	SAND,
	COAL,
}

## Layer 2 of the reveal ladder (GDD 4.6): what you learn at lamp radius.
## DELIBERATELY LOSSY -- a colour class names a family, never a material,
## and never its cost. GDD 6 requires at least two materials to share one,
## or the price of information is untested.
##
## STONE and HARD_STONE sharing GREY is the boulder-in-rubble deception
## (GDD 4.1.2): the wall cannot be priced by looking at it.
enum ColourClass {
	BROWN,
	GREY,
}

const NAMES: Dictionary = {
	Id.DIRT: "dirt",
	Id.STONE: "stone",
	Id.HARD_STONE: "hard_stone",
	Id.SAND: "sand",
	Id.COAL: "coal",
}

const COLOUR_NAMES: Dictionary = {
	ColourClass.BROWN: "brown",
	ColourClass.GREY: "grey",
}

const COLOUR_OF: Dictionary = {
	Id.DIRT: ColourClass.BROWN,
	Id.SAND: ColourClass.BROWN,
	Id.STONE: ColourClass.GREY,
	Id.HARD_STONE: ColourClass.GREY,
	Id.COAL: ColourClass.GREY,
}

static func name_of(id: Id) -> String:
	return NAMES[id]

## -1 when the name is not a material. Callers report; this does not push_error,
## because the loader wants to collect the failure with its own context.
static func from_name(n: String) -> int:
	for id: Id in NAMES:
		if NAMES[id] == n:
			return id
	return -1

static func colour_name_of(id: Id) -> String:
	return COLOUR_NAMES[COLOUR_OF[id]]

static func colour_from_name(n: String) -> int:
	for c: ColourClass in COLOUR_NAMES:
		if COLOUR_NAMES[c] == n:
			return c
	return -1
