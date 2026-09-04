## Parses and validates template JSON (GDD 4.7.1, 5.1). Collects every problem
## into `errors`; an unknown key is an error, not a shrug. Any key starting
## with "_" is an authoring note and is ignored.
class_name TemplateLoader

const TEMPLATE_KEYS: PackedStringArray = [
	"material", "colour_class", "display_skin", "authored_size",
	"default_rule", "overrides",
]

static func is_note(key: String) -> bool:
	return key.begins_with("_")

## Null on any error.
static func from_dict(id: String, src: Dictionary, errors: PackedStringArray) -> BlockTemplate:
	var before: int = errors.size()
	var t := BlockTemplate.new()
	t.id = id

	for key: String in src:
		if not TEMPLATE_KEYS.has(key) and not is_note(key):
			errors.append("%s: unknown template key '%s'" % [id, key])

	var material: int = Materials.from_name(str(src.get("material", "")))
	if material < 0:
		errors.append("%s: unknown material '%s'" % [id, src.get("material")])
	else:
		t.material = material

	# Optional; defaults to the material's own class. Authoring it is how a
	# material lies about its family (GDD 4.6).
	if src.has("colour_class"):
		var cc: int = Materials.colour_from_name(str(src["colour_class"]))
		if cc < 0:
			errors.append("%s: unknown colour_class '%s'" % [id, src["colour_class"]])
		else:
			t.colour_class = cc
	elif material >= 0:
		t.colour_class = Materials.COLOUR_OF[material]

	t.display_skin = str(src.get("display_skin", ""))

	if src.has("authored_size"):
		var authored: int = int(src["authored_size"])
		if not Atoms.is_valid_size(authored):
			errors.append("%s: authored_size %s is not a power of two >= 1" % [id, src["authored_size"]])
		else:
			t.authored_size = authored

	if typeof(src.get("default_rule")) != TYPE_DICTIONARY:
		errors.append("%s: default_rule must be an object" % id)
	else:
		var patch: Dictionary = _parse_patch(src["default_rule"], "%s.default_rule" % id, errors)
		if not patch.has("resistance") or not patch.has("on_break"):
			errors.append("%s: default_rule must set at least resistance and on_break" % id)
		t.default_rule = Rule.new().patched(patch)

	var overrides: Variant = src.get("overrides", {})
	if typeof(overrides) != TYPE_DICTIONARY:
		errors.append("%s: overrides must be an object" % id)
		overrides = {}
	for key: String in overrides:
		var ctx: String = "%s.overrides['%s']" % [id, key]
		if typeof(overrides[key]) != TYPE_DICTIONARY:
			errors.append("%s: must be an object" % ctx)
			continue
		var patch: Dictionary = _parse_patch(overrides[key], ctx, errors)
		if patch.is_empty():
			errors.append("%s: empty override" % ctx)
			continue
		if BlockTemplate.is_size_key(key):
			var size: int = BlockTemplate.size_from_key(key)
			if size < 0:
				errors.append("%s: size key must be a power of two >= 1" % ctx)
				continue
			t.size_overrides[size] = patch
		else:
			var path: Variant = BlockTemplate.key_to_path(key)
			if path == null:
				errors.append("%s: malformed key -- want '', 'Q0.Q3' or 'size:4'" % ctx)
				continue
			t.path_overrides[BlockTemplate.path_to_key(path)] = patch

	# Only checkable once the whole tree is parsed (GDD 4.7.1).
	if t.authored_size > 0 and t.default_rule != null:
		for p: String in t.validate_for_root_size(t.authored_size):
			errors.append("%s: at its authored_size %d, %s" % [id, t.authored_size, p])

	return t if errors.size() == before else null

static func from_json_string(id: String, text: String, errors: PackedStringArray) -> BlockTemplate:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: not a JSON object" % id)
		return null
	return from_dict(id, parsed, errors)

static func from_file(path: String, errors: PackedStringArray) -> BlockTemplate:
	if not FileAccess.file_exists(path):
		errors.append("%s: no such file" % path)
		return null
	return from_json_string(path.get_file().get_basename(), FileAccess.get_file_as_string(path), errors)

## Every *.json in `dir_path` -> {id: BlockTemplate}. Failed templates are absent.
static func load_dir(dir_path: String, errors: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		errors.append("cannot open %s" % dir_path)
		return out
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for f: String in files:
		if f.ends_with(".json"):
			var t: BlockTemplate = from_file(dir_path.path_join(f), errors)
			if t != null:
				out[t.id] = t
	return out

## A partial patch: only keys present end up in the result.
static func _parse_patch(src: Dictionary, ctx: String, errors: PackedStringArray) -> Dictionary:
	var patch: Dictionary = {}
	for key: String in src:
		if not Rule.FIELDS.has(key) and not is_note(key):
			errors.append("%s: unknown rule field '%s'" % [ctx, key])

	if src.has("resistance"):
		var r: Variant = src["resistance"]
		if not _is_number(r) or float(r) < 0.0:
			errors.append("%s: resistance must be a number >= 0" % ctx)
		else:
			patch["resistance"] = float(r)

	if src.has("on_break"):
		var ob: int = Rule.on_break_from_name(str(src["on_break"]))
		if ob < 0:
			errors.append("%s: on_break must be 'subdivide' or 'mine'" % ctx)
		else:
			patch["on_break"] = ob

	if src.has("drop"):
		patch["drop"] = _parse_drop(src["drop"], ctx, errors)

	if patch.get("on_break") == Rule.OnBreak.SUBDIVIDE and patch.get("drop") != null:
		errors.append("%s: on_break 'subdivide' yields children, not a drop" % ctx)

	if src.has("pass_down"):
		if typeof(src["pass_down"]) != TYPE_BOOL:
			errors.append("%s: pass_down must be true or false" % ctx)
		else:
			patch["pass_down"] = bool(src["pass_down"])

	if src.has("pass_through"):
		var pt: int = Rule.pass_through_from_name(str(src["pass_through"]))
		if pt < 0:
			errors.append("%s: unknown pass_through pattern '%s'" % [ctx, src["pass_through"]])
		else:
			patch["pass_through"] = pt

	for f: String in ["pass_down_falloff", "pass_through_falloff"]:
		if not src.has(f):
			continue
		var v: Variant = src[f]
		if not _is_number(v) or float(v) < 0.0 or float(v) > 1.0:
			errors.append("%s: %s must be a number within 0..1" % [ctx, f])
		else:
			patch[f] = float(v)
	return patch

## null is a legitimate value (the node vanishes); omitting the key means inherit.
static func _parse_drop(src: Variant, ctx: String, errors: PackedStringArray) -> Drop:
	if src == null:
		return null
	if typeof(src) != TYPE_DICTIONARY:
		errors.append("%s: drop must be null or an object of material and size" % ctx)
		return null
	var d: Dictionary = src
	for key: String in d:
		if key != "material" and key != "size" and not is_note(key):
			errors.append("%s.drop: unknown key '%s'" % [ctx, key])
	var material: int = Materials.from_name(str(d.get("material", "")))
	if material < 0:
		errors.append("%s.drop: unknown material '%s'" % [ctx, d.get("material")])
		return null
	var size: Variant = d.get("size")
	if not _is_number(size) or not Atoms.is_valid_size(int(size)):
		errors.append("%s.drop: size must be a power of two >= 1, in atoms" % ctx)
		return null
	return Drop.new(material, int(size))

static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
