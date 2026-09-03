## Reads a hand-authored map into a World (GDD 4.1.0). The format is a
## character grid plus a legend: one character per `cell_atoms` cell. A legend
## entry names a template and a block size; a size smaller than the cell tiles
## it with several blocks (GDD 4.1.2).
class_name MapLoader

const LEGEND_KEYS: PackedStringArray = ["template", "size"]

static func from_dict(src: Dictionary, templates: Dictionary, errors: PackedStringArray) -> World:
	var world := World.new()
	world.templates = templates

	var extent: Array = src.get("extent_atoms", [])
	if extent.size() != 2:
		errors.append("map has no extent_atoms")
		return world
	world.extent = Vector2i(int(extent[0]), int(extent[1]))

	var cell: int = int(src.get("cell_atoms", 0))
	if not Atoms.is_valid_size(cell):
		errors.append("cell_atoms must be a power of two >= 1")
		return world

	var grid: Array = src.get("grid", [])
	var want_rows: int = world.extent.y / cell
	var want_cols: int = world.extent.x / cell
	if grid.size() != want_rows:
		errors.append("grid has %d rows, extent wants %d" % [grid.size(), want_rows])
		return world

	var legend: Dictionary = _parse_legend(src.get("legend", {}), cell, templates, errors)
	if not errors.is_empty():
		return world

	for row: int in grid.size():
		var line: String = str(grid[row])
		if line.length() != want_cols:
			errors.append("grid row %d is %d characters, extent wants %d" % [row, line.length(), want_cols])
			continue
		for col: int in want_cols:
			var ch: String = line[col]
			if not legend.has(ch):
				errors.append("row %d col %d: '%s' is not in the legend" % [row, col, ch])
				continue
			var entry: Variant = legend[ch]
			if entry != null:
				_fill_cell(world, entry, Vector2i(col * cell, row * cell), cell, errors)
	return world

static func from_file(path: String, templates: Dictionary, errors: PackedStringArray) -> World:
	if not FileAccess.file_exists(path):
		errors.append("%s: no such file" % path)
		return World.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: not a JSON object" % path)
		return World.new()
	return from_dict(parsed, templates, errors)

## char -> null (void) or {template: String, size: int}. Validated once per
## entry, not once per cell.
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
			out[ch] = null
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
		if not Atoms.is_valid_size(size) or size > cell:
			errors.append("legend '%s': size %d does not tile a %d-atom cell" % [ch, size, cell])
			continue
		var problems: PackedStringArray = templates[id].validate_for_root_size(size)
		if not problems.is_empty():
			errors.append("legend '%s': %s at size %d -- %s" % [ch, id, size, " ".join(problems)])
			continue
		out[ch] = {"template": id, "size": size}
	return out

static func _fill_cell(world: World, entry: Dictionary, cell_origin: Vector2i,
		cell: int, errors: PackedStringArray) -> void:
	var size: int = entry["size"]
	var per_edge: int = cell / size
	for by: int in per_edge:
		for bx: int in per_edge:
			var origin: Vector2i = cell_origin + Vector2i(bx * size, by * size)
			var clash: BlockInstance = world.find_overlap(Rect2i(origin, Vector2i(size, size)))
			if clash != null:
				errors.append("block at %s overlaps %s" % [origin, clash])
				continue
			world.add(BlockInstance.new(origin, size, entry["template"]))
