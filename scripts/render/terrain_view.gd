## Draws the world in atom units (the parent Stage scales to pixels).
## Three channels (GDD 2): colour class, block border, fracture.
## Fractures are the tree, rendered (GDD 5.2): a subdivided node draws its
## full cross; a revealed leaf that would subdivide draws one as far as its
## damage has carried it (GDD 5.3). Damage has no channel of its own.
extends Node2D

@export var void_color: Color = Color(0.05, 0.05, 0.07)
@export var class_colors: Dictionary = {
	Materials.ColourClass.BROWN: Color(0.44, 0.31, 0.21),
	Materials.ColourClass.GREY: Color(0.40, 0.41, 0.44),
}
## Shown once a node is revealed (GDD 5 layer 3).
@export var material_colors: Dictionary = {
	Materials.Id.DIRT: Color(0.55, 0.38, 0.24),
	Materials.Id.SAND: Color(0.80, 0.70, 0.40),
	Materials.Id.STONE: Color(0.50, 0.51, 0.55),
	Materials.Id.HARD_STONE: Color(0.30, 0.31, 0.36),
	Materials.Id.COAL: Color(0.12, 0.12, 0.13),
}
@export var border_darken: float = 0.55
@export var crack_color: Color = Color(0.05, 0.04, 0.04)
@export var crack_min_alpha: float = 0.35  ## a promise just opening (GDD 5.2)
## How far a crack spreads before the break, per material (GDD 5.3, 4.9.5).
## 0 keeps a material silent until it breaks; 1 draws the whole cross just
## before it does. Untuned.
@export var fracture_tell: Dictionary = {
	Materials.Id.DIRT: 0.6,
	Materials.Id.SAND: 1.0,
	Materials.Id.STONE: 0.35,
	Materials.Id.HARD_STONE: 0.0,
	Materials.Id.COAL: 0.8,
}

var world: World = null
var view: Rect2 = Rect2()  ## visible area in atoms, set by Main

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(view.grow(2.0), void_color, true)
	if world == null:
		return
	for b: BlockInstance in world.blocks:
		var r := Rect2(Vector2(b.origin), Vector2(b.size, b.size))
		if not view.intersects(r):
			continue
		var t: BlockTemplate = world.template_for(b)
		var path: Array[int] = []
		_draw_node(b.root, Vector2(b.origin), t, path, r,
			class_colors[t.colour_class].darkened(border_darken))

func _draw_node(node: BlockNode, origin: Vector2, t: BlockTemplate, path: Array[int],
		bounds: Rect2, border: Color) -> void:
	var s: float = float(node.size)
	var r := Rect2(origin, Vector2(s, s))
	if node.is_leaf():
		var rule: Rule = t.rule_at(path, node.size)
		var fill: Color = class_colors[t.colour_class]
		if node.revealed:
			fill = material_colors[rule.apparent_material(t.material)]
		draw_rect(r, fill, true)
		_outline(r, bounds, border)
		if node.revealed and node.size > 1 and rule.on_break == Rule.OnBreak.SUBDIVIDE:
			_promise(r, node, rule, t)
		return
	for q: int in 4:
		var child: BlockNode = node.children[q]
		if child == null:
			continue
		var child_path: Array[int] = path.duplicate()
		child_path.append(q)
		_draw_node(child, Vector2(Quad.child_origin(q, Vector2i(origin), node.size)), t,
			child_path, bounds, border)
	_fracture(r, node, crack_color)

## The block border, drawn by the leaves that still reach it: a mined-out
## quadrant leaves no line behind on the void (GDD 2).
func _outline(r: Rect2, bounds: Rect2, c: Color) -> void:
	if is_equal_approx(r.position.x, bounds.position.x):
		draw_line(r.position, Vector2(r.position.x, r.end.y), c, -1.0)
	if is_equal_approx(r.end.x, bounds.end.x):
		draw_line(Vector2(r.end.x, r.position.y), r.end, c, -1.0)
	if is_equal_approx(r.position.y, bounds.position.y):
		draw_line(r.position, Vector2(r.end.x, r.position.y), c, -1.0)
	if is_equal_approx(r.end.y, bounds.end.y):
		draw_line(Vector2(r.position.x, r.end.y), r.end, c, -1.0)

## The cross of a subdivided node: only the arms that still bound a live
## child. An arm between two mined-out quadrants would be a line in void
## (GDD 5.2).
func _fracture(r: Rect2, node: BlockNode, c: Color) -> void:
	var mid: Vector2 = r.get_center()
	var live: Array[bool] = []
	for q: int in 4:
		live.append(node.children[q] != null)
	if live[0] or live[1]:
		draw_line(Vector2(mid.x, r.position.y), mid, c, -1.0)
	if live[2] or live[3]:
		draw_line(mid, Vector2(mid.x, r.end.y), c, -1.0)
	if live[0] or live[2]:
		draw_line(Vector2(r.position.x, mid.y), mid, c, -1.0)
	if live[1] or live[3]:
		draw_line(mid, Vector2(r.end.x, mid.y), c, -1.0)

## The cross a revealed leaf would subdivide into, inked as far as its damage
## has carried it: extent = tell x damage / resistance (GDD 5.3). Arms grow
## from the centre outward -- the symmetric case, which needs no impact point
## (GDD 5.3).
func _promise(r: Rect2, node: BlockNode, rule: Rule, t: BlockTemplate) -> void:
	if rule.resistance <= 0.0:
		return  # breaks on any damage; never sits here damaged
	var tell: float = fracture_tell[rule.apparent_material(t.material)]
	var extent: float = tell * clampf(node.damage / rule.resistance, 0.0, 1.0)
	if extent <= 0.0:
		return
	var c: Color = crack_color
	c.a = lerpf(crack_min_alpha, 1.0, extent)
	_cross(r, c, extent)

## `extent` is the fraction of each arm, from the centre out, that is inked.
func _cross(r: Rect2, c: Color, extent: float = 1.0) -> void:
	var mid: Vector2 = r.get_center()
	var reach: Vector2 = r.size * 0.5 * extent
	draw_line(Vector2(mid.x, mid.y - reach.y), Vector2(mid.x, mid.y + reach.y), c, -1.0)
	draw_line(Vector2(mid.x - reach.x, mid.y), Vector2(mid.x + reach.x, mid.y), c, -1.0)
