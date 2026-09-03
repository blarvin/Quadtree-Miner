## The Phase-0 materials (GDD 4.7). Void is not a material (GDD 4.1.1).
class_name Materials

enum Id { DIRT, STONE, HARD_STONE, SAND, COAL }

## What the player sees before the first strike (GDD 4.6). Deliberately lossy:
## a class names a family, never a material or its cost.
enum ColourClass { BROWN, GREY }

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

## -1 when unknown.
static func from_name(n: String) -> int:
	return NAMES.find_key(n) if NAMES.values().has(n) else -1

## -1 when unknown.
static func colour_from_name(n: String) -> int:
	return COLOUR_NAMES.find_key(n) if COLOUR_NAMES.values().has(n) else -1
