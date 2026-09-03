## Parses and VALIDATES template JSON into BlockTemplate. GDD 4.7.1, 5.1.
##
## Fails loudly and collects every problem rather than stopping at the first,
## so a bad template tells you everything wrong with it in one run. Nothing
## here guesses: an unknown key is an error, not a shrug, because a silently
## ignored typo in a resistance value is a tuning bug you find days later.
##
## Size-dependent checks are NOT here -- see BlockTemplate.validate_for_root_size.
class_name TemplateLoader

const TEMPLATE_KEYS: PackedStringArray = [
	"material", "colour_class", "display_skin", "default_rule", "overrides",
]

class Result extends RefCounted:
	var template: BlockTemplate = null
	var errors: PackedStringArray = []

	func ok() -> bool:
		return errors.is_empty()

	func describe() -> String:
		return "\n".join(errors)

static func from_dict(id: String, src: Dictionary) -> Result:
	var res := Result.new()
	var t := BlockTemplate.new()
	t.id = id

	for key: String in src:
		if not TEMPLATE_KEYS.has(key):
			res.errors.append("%s: unknown template key '%s'" % [id, key])

	# material -------------------------------------------------------------
	var material: int = Materials.from_name(str(src.get("material", "")))
	if material < 0:
		res.errors.append("%s: unknown material '%s'" % [id, src.get("material")])
	else:
		t.material = material

	# colour_class ---------------------------------------------------------
	# Optional: defaults to the material's own class. Authoring it explicitly
	# is how a material lies about its family (GDD 4.6 -- the class is
	# deliberately lossy), so it is allowed to disagree with the material.
	if src.has("colour_class"):
		var cc: int = Materials.colour_from_name(str(src["colour_class"]))
		if cc < 0:
			res.errors.append("%s: unknown colour_class '%s'" % [id, src["colour_class"]])
		else:
			t.colour_class = cc
	elif material >= 0:
		t.colour_class = Materials.COLOUR_OF[material]

	t.display_skin = str(src.get("display_skin", ""))

	# default_rule ---------------------------------------------------------
	if not src.has("default_rule"):
		res.errors.append("%s: no default_rule -- every template needs one (GDD 4.7.1)" % id)
	elif typeof(src["default_rule"]) != TYPE_DICTIONARY:
		res.errors.append("%s: default_rule must be an object" % id)
	else:
		var patch: Dictionary = _parse_patch(src["default_rule"], "%s.default_rule" % id, res.errors)
		if not patch.has("resistance") or not patch.has("on_break"):
			res.errors.append("%s: default_rule must set at least resistance and on_break" % id)
		t.default_rule = Rule.new().patched(patch)

	# overrides ------------------------------------------------------------
	var overrides: Variant = src.get("overrides", {})
	if typeof(overrides) != TYPE_DICTIONARY:
		res.errors.append("%s: overrides must be an object" % id)
		overrides = {}
	for key: String in overrides:
		var ctx: String = "%s.overrides['%s']" % [id, key]
		if typeof(overrides[key]) != TYPE_DICTIONARY:
			res.errors.append("%s: must be an object" % ctx)
			continue
		var patch: Dictionary = _parse_patch(overrides[key], ctx, res.errors)
		if patch.is_empty():
			res.errors.append("%s: empty override says nothing -- delete it" % ctx)
			continue
		if BlockTemplate.is_size_key(key):
			var size: int = BlockTemplate.size_from_key(key)
			if size < 0:
				res.errors.append("%s: size key must be a power of two >= 1" % ctx)
				continue
			t.size_overrides[size] = patch
		else:
			var path: Variant = BlockTemplate.key_to_path(key)
			if path == null:
				res.errors.append("%s: malformed key -- want '', 'Q0.Q3' or 'size:4'" % ctx)
				continue
			t.path_overrides[BlockTemplate.path_to_key(path)] = patch

	res.template = t if res.ok() else null
	return res

static func from_json_string(id: String, text: String) -> Result:
	var res := Result.new()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		res.errors.append("%s: not a JSON object" % id)
		return res
	return from_dict(id, parsed)

static func from_file(path: String) -> Result:
	var res := Result.new()
	if not FileAccess.file_exists(path):
		res.errors.append("%s: no such file" % path)
		return res
	return from_json_string(path.get_file().get_basename(), FileAccess.get_file_as_string(path))

## Every *.json in `dir_path` -> {id: BlockTemplate}. Problems are appended to
## `errors`; a template that failed is simply absent from the returned map.
static func load_dir(dir_path: String, errors: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		errors.append("cannot open %s" % dir_path)
		return out
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".json"):
			continue
		var res: Result = from_file(dir_path.path_join(f))
		if res.ok():
			out[res.template.id] = res.template
		else:
			errors.append_array(res.errors)
	return out

# --------------------------------------------------------------------------

## A PARTIAL patch (GDD 4.5, 4.7.1) -- an absent key means "inherit", never
## "reset to default". Only keys actually present end up in the returned dict.
static func _parse_patch(src: Dictionary, ctx: String, errors: PackedStringArray) -> Dictionary:
	var patch: Dictionary = {}

	for key: String in src:
		if not Rule.FIELDS.has(key):
			errors.append("%s: unknown rule field '%s'" % [ctx, key])

	if src.has("resistance"):
		var r: Variant = src["resistance"]
		if typeof(r) != TYPE_INT and typeof(r) != TYPE_FLOAT:
			errors.append("%s: resistance must be a number" % ctx)
		elif float(r) < 0.0:
			errors.append("%s: resistance must be >= 0" % ctx)
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

	# An object setting BOTH on_break 'subdivide' AND a drop contradicts
	# itself -- subdividing yields children, not units (GDD 4.3). Only
	# checkable within one object; an inherited drop riding along with an
	# inherited subdivide is harmless and is deliberately not flagged.
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
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			errors.append("%s: %s must be a number" % [ctx, f])
		elif float(v) < 0.0 or float(v) > 1.0:
			errors.append("%s: %s must be within 0..1 -- propagation cannot amplify" % [ctx, f])
		else:
			patch[f] = float(v)

	return patch

## null is a legitimate authored value: a drop of null means the node vanishes
## (GDD 4.3). That is NOT the same as omitting the key, which means inherit.
static func _parse_drop(src: Variant, ctx: String, errors: PackedStringArray) -> Drop:
	if src == null:
		return null
	if typeof(src) != TYPE_DICTIONARY:
		errors.append("%s: drop must be null or an object of material and size" % ctx)
		return null
	var d: Dictionary = src
	for key: String in d:
		if key != "material" and key != "size":
			errors.append("%s.drop: unknown key '%s'" % [ctx, key])
	var material: int = Materials.from_name(str(d.get("material", "")))
	if material < 0:
		errors.append("%s.drop: unknown material '%s'" % [ctx, d.get("material")])
		return null
	var size: Variant = d.get("size")
	if typeof(size) != TYPE_INT and typeof(size) != TYPE_FLOAT:
		errors.append("%s.drop: size is required, in atoms" % ctx)
		return null
	if not Atoms.is_valid_size(int(size)):
		errors.append("%s.drop: size %s must be a power of two >= 1" % [ctx, size])
		return null
	return Drop.new(material, int(size))
