## THROWAWAY. Strike trace for one block of each template, size 16.
## Policy: always strike the first remaining solid atom, row-major. A player
## determined to clear the whole block. Delete this file.
extends SceneTree

const SIZE: int = 16

func _initialize() -> void:
	var errors: PackedStringArray = []
	var templates: Dictionary = TemplateLoader.load_dir("res://data/templates", errors)
	for e: String in errors:
		print("ERROR ", e)
	var ids: Array = templates.keys()
	ids.sort()
	for id: String in ids:
		_trace(templates[id], id)
	quit(0)

func _trace(t: BlockTemplate, id: String) -> void:
	var problems: PackedStringArray = t.validate_for_root_size(SIZE)
	if not problems.is_empty():
		print("%-12s size %d: INVALID -- %s" % [id, SIZE, " ".join(problems)])
		return
	var b := BlockInstance.new(Vector2i.ZERO, SIZE, id)
	var events: PackedStringArray = []
	var strikes: int = 0
	var fractures: int = 0
	while strikes < 500:
		var at: Variant = _first_solid(b)
		if at == null:
			break
		strikes += 1
		var r: Strike.Result = Strike.apply(b.root, t, at, 1.0)
		var parts: PackedStringArray = []
		for s: int in r.broke:
			if r.mined and s == r.broke[r.broke.size() - 1]:
				parts.append("mine%d" % s)
			else:
				parts.append("frac%d" % s)
				fractures += 1
		for y: Strike.Yield in r.yields:
			parts.append("+%dx%s" % [y.count, Materials.name_of(y.drop.material)])
		if r.block_destroyed:
			parts.append("BLOCK GONE")
		if not parts.is_empty():
			events.append("%d:%s" % [strikes, "/".join(parts)])
		if r.block_destroyed:
			break
	print("%-12s %3d strikes, %2d fractures, %2d nodes left | %s" % [
		id, strikes, fractures, b.root.node_count(), " ".join(events).left(96)])

## First atom, row-major, that still has material.
func _first_solid(b: BlockInstance) -> Variant:
	for y: int in SIZE:
		for x: int in SIZE:
			if Strike.site_at(b.root, Vector2i(x, y)).node != null:
				return Vector2i(x, y)
	return null
