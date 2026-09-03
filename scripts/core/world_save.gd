## Persisting the world (GDD 5.1, 4.6.1). Saves damage, revealed, and the
## tree's shape. Node size is not saved (derived from depth); rules are not
## saved (read from the template). An untouched node saves as {}.
class_name WorldSave

const VERSION: int = 1

const K_DAMAGE: String = "d"
const K_REVEALED: String = "r"
const K_CHILDREN: String = "c"  ## null entry = mined quadrant; absent = never subdivided

static func to_dict(world: World) -> Dictionary:
	var out: Array = []
	for b: BlockInstance in world.blocks:
		out.append({
			"origin": [b.origin.x, b.origin.y],
			"size": b.size,
			"template": b.template_id,
			"root": _node_to(b.root),
		})
	return {"version": VERSION, "extent": [world.extent.x, world.extent.y], "blocks": out}

static func to_json(world: World) -> String:
	return JSON.stringify(to_dict(world), "  ")

static func from_dict(src: Dictionary, templates: Dictionary, errors: PackedStringArray) -> World:
	var world := World.new()
	world.templates = templates

	var version: int = int(src.get("version", 0))
	if version != VERSION:
		errors.append("save version %d, expected %d" % [version, VERSION])
		return world

	var extent: Array = src.get("extent", [])
	if extent.size() == 2:
		world.extent = Vector2i(int(extent[0]), int(extent[1]))

	for entry: Variant in src.get("blocks", []):
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("a block entry is not an object")
			continue
		var b: Dictionary = entry
		var origin: Array = b.get("origin", [])
		if origin.size() != 2:
			errors.append("block has no origin")
			continue
		var size: int = int(b.get("size", 0))
		if not Atoms.is_valid_size(size):
			errors.append("block at %s has size %d" % [origin, size])
			continue
		var template_id: String = str(b.get("template", ""))
		if not templates.has(template_id):
			errors.append("block at %s wants unknown template '%s'" % [origin, template_id])
			continue
		var root: BlockNode = _node_from(b.get("root", {}), size)
		world.add(BlockInstance.new(Vector2i(int(origin[0]), int(origin[1])), size, template_id, root))
	return world

static func from_json(text: String, templates: Dictionary, errors: PackedStringArray) -> World:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("save is not a JSON object")
		return World.new()
	return from_dict(parsed, templates, errors)

static func save_to_file(world: World, path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return false
	f.store_string(to_json(world))
	return true

static func load_from_file(path: String, templates: Dictionary, errors: PackedStringArray) -> World:
	if not FileAccess.file_exists(path):
		errors.append("%s: no such file" % path)
		return World.new()
	return from_json(FileAccess.get_file_as_string(path), templates, errors)

static func _node_to(node: BlockNode) -> Dictionary:
	var out: Dictionary = {}
	if node.damage != 0.0:
		out[K_DAMAGE] = node.damage
	if node.revealed:
		out[K_REVEALED] = true
	if not node.is_leaf():
		var kids: Array = []
		for c: BlockNode in node.children:
			kids.append(null if c == null else _node_to(c))
		out[K_CHILDREN] = kids
	return out

## `size` is passed down, never read from the file (GDD 5.2).
static func _node_from(src: Variant, size: int) -> BlockNode:
	var node := BlockNode.new(size)
	if typeof(src) != TYPE_DICTIONARY:
		return node
	var d: Dictionary = src
	node.damage = float(d.get(K_DAMAGE, 0.0))
	node.revealed = bool(d.get(K_REVEALED, false))
	if d.has(K_CHILDREN):
		var kids: Array = d[K_CHILDREN]
		for i: int in 4:
			var child: Variant = kids[i] if i < kids.size() else null
			node.children.append(null if child == null else _node_from(child, size >> 1))
	return node
