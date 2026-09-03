## Reads a hand-authored map into a World. GDD 4.1.0, 4.1.2.
##
## THE FORMAT IS A CHARACTER GRID PLUS A LEGEND. One character per CELL of
## `cell_atoms` (16 -- a standard block footprint), so the whole dev map is 64
## lines of 64 characters: editable in any text editor, diffable, and readable
## as a picture of the world at a glance. There is no painter yet (GDD 6) and
## this is deliberately not one.
##
## A legend entry names a template AND A BLOCK SIZE. A cell of size 16 places
## one block; a cell of size 4 places sixteen. That is the whole of GDD 4.1.2's
## mixed-size packing: the SAME template painted at a smaller size is different
## play, not different content, and it costs no new template. Reading size as
## cost is what makes the boulder-in-rubble a decision rather than a gotcha.
class_name MapLoader

const LEGEND_KEYS: PackedStringArray = ["template", "size"]

static func from_dict(src: Dictionary, templates: Dictionary,
		errors: PackedStringArray) -> World:
	var world := World.new()
	world.templates = templates

	var extent: Array = src.get("extent_atoms", [])
	if extent.size() != 2:
		errors.append("map has no extent_atoms")
		return world
	world.extent = Vector2i(int(extent[0]), int(extent[1]))

	var cell: int = int(src.get("cell_atoms", Atoms.STANDARD_BLOCK))
	if not Atoms.is_valid_size(cell):
		errors.append("cell_atoms %d is not a power of two >= 1" % cell)
		return world

	var grid: Array = src.get("grid", [])
	var want_rows: int = world.extent.y / cell
	var want_cols: int = world.extent.x / cell
	if grid.size() != want_rows:
		errors.append("grid has %d rows, extent wants %d" % [grid.size(), want_rows])
		return world

	var legend: Dictionary = _parse_legend(
		src.get("legend", {}), cell, templates, errors)
	if not errors.is_empty():
		return world

	for row: int in grid.size():
		var line: String = str(grid[row])
		if line.length() != want_cols:
			errors.append("grid row %d is %d characters, extent wants %d"
				% [row, line.length(), want_cols])
			continue
		for col: int in want_cols:
			var ch: String = line[col]
			if not legend.has(ch):
				errors.append("row %d col %d: '%s' is not in the legend" % [row, col, ch])
				continue
			var entry: Variant = legend[ch]
			if entry == null:
				continue  # void: the absence of a block, so nothing to place
			_fill_cell(world, entry, Vector2i(col * cell, row * cell), cell, errors)

	return world

static func from_file(path: String, templates: Dictionary,
		errors: PackedStringArray) -> World:
	if not FileAccess.file_exists(path):
		errors.append("%s: no such file" % path)
		return World.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: not a JSON object" % path)
		return World.new()
	return from_dict(parsed, templates, errors)

# --------------------------------------------------------------------------

## char -> null (void) or {template_id: String, size: int}. Validated ONCE per
## legend entry rather than once per cell, so a bad legend reports one problem
## instead of four thousand.
static func _parse_legend(src: Variant, cell: int, templates: Dictionary,
		errors: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	if typeof(src) != TYPE_DICTIONARY:
		errors.append("legend must be an object")
		return out

	for ch: String in src:
		if TemplateLoader.is_note(ch):
			continue
		if ch.length() != 1:
			errors.append("legend key '%s' must be exactly one character" % ch)
			continue
		var entry: Variant = src[ch]
		if entry == null:
			out[ch] = null  # void
			continue
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("legend '%s': want null or an object of template and size" % ch)
			continue
		var e: Dictionary = entry
		for key: String in e:
			if not LEGEND_KEYS.has(key) and not TemplateLoader.is_note(key):
				errors.append("legend '%s': unknown key '%s'" % [ch, key])

		var id: String = str(e.get("template", ""))
		if not templates.has(id):
			errors.append("legend '%s': unknown template '%s'" % [ch, id])
			continue
		var size: int = int(e.get("size", 0))
		if not Atoms.is_valid_size(size):
			errors.append("legend '%s': size %d is not a power of two >= 1" % [ch, size])
			continue
		if size > cell or cell % size != 0:
			errors.append("legend '%s': size %d does not tile a %d-atom cell" % [ch, size, cell])
			continue
		## The size-bound checks templates cannot make on their own, because
		## quad-paths are root-relative (GDD 4.7.1). This is where a template
		## meets an actual block size, so this is where they belong.
		var problems: PackedStringArray = templates[id].validate_for_root_size(size)
		if not problems.is_empty():
			errors.append("legend '%s': %s at size %d -- %s"
				% [ch, id, size, " ".join(problems)])
			continue
		out[ch] = {"template": id, "size": size}
	return out

## One legend character may place many blocks: a size-4 entry tiles the cell
## with sixteen. Same rules, same material, different play (GDD 4.1.2).
static func _fill_cell(world: World, entry: Dictionary, cell_origin: Vector2i,
		cell: int, errors: PackedStringArray) -> void:
	var size: int = entry["size"]
	var per_edge: int = cell / size
	for by: int in per_edge:
		for bx: int in per_edge:
			var origin: Vector2i = cell_origin + Vector2i(bx * size, by * size)
			var clash: BlockInstance = world.find_overlap(
				Rect2i(origin, Vector2i(size, size)))
			if clash != null:
				errors.append("block at %s overlaps %s -- blocks never overlap (GDD 4.1)"
					% [origin, clash])
				continue
			world.add(BlockInstance.new(origin, size, entry["template"]))
