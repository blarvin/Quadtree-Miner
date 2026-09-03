## Draws the world in atom units (the parent Stage scales to pixels).
## Three channels (GDD 4.1.2): colour class, block border, fracture.
## Fractures are the tree, rendered (GDD 4.6.2): a subdivided node draws its
## cross; a revealed leaf that would subdivide draws it faintly.
extends Node2D

@export var void_color: Color = Color(0.05, 0.05, 0.07)
@export var class_colors: Dictionary = {
	Materials.ColourClass.BROWN: Color(0.44, 0.31, 0.21),
	Materials.ColourClass.GREY: Color(0.40, 0.41, 0.44),
}
## Shown once a node is revealed (GDD 4.6 layer 3).
@export var material_colors: Dictionary = {
	Materials.Id.DIRT: Color(0.55, 0.38, 0.24),
	Materials.Id.SAND: Color(0.80, 0.70, 0.40),
	Materials.Id.STONE: Color(0.50, 0.51, 0.55),
	Materials.Id.HARD_STONE: Color(0.30, 0.31, 0.36),
	Materials.Id.COAL: Color(0.12, 0.12, 0.13),
}
@export var border_darken: float = 0.55
@export var crack_color: Color = Color(0.05, 0.04, 0.04)
@export var crack_preview_alpha: float = 0.35  ## revealed-but-unbroken cross
@export var damage_tint: Color = Color(1.0, 0.5, 0.2, 0.25)  ## overlay scaled by damage/resistance

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
		_draw_node(b.root, Vector2(b.origin), t, path)
		draw_rect(r, class_colors[t.colour_class].darkened(border_darken), false, -1.0)

func _draw_node(node: BlockNode, origin: Vector2, t: BlockTemplate, path: Array[int]) -> void:
	var s: float = float(node.size)
	var r := Rect2(origin, Vector2(s, s))
	if node.is_leaf():
		var rule: Rule = t.rule_at(path, node.size)
		var fill: Color = class_colors[t.colour_class]
		if node.revealed:
			fill = material_colors[rule.apparent_material(t.material)]
		draw_rect(r, fill, true)
		if node.damage > 0.0 and rule.resistance > 0.0:
			var tint: Color = damage_tint
			tint.a *= clampf(node.damage / rule.resistance, 0.0, 1.0)
			draw_rect(r, tint, true)
		if node.revealed and node.size > 1 and rule.on_break == Rule.OnBreak.SUBDIVIDE:
			var c: Color = crack_color
			c.a = crack_preview_alpha
			_cross(r, c)
		return
	for q: int in 4:
		var child: BlockNode = node.children[q]
		if child == null:
			continue
		var child_path: Array[int] = path.duplicate()
		child_path.append(q)
		_draw_node(child, Vector2(Quad.child_origin(q, Vector2i(origin), node.size)), t, child_path)
	_cross(r, crack_color)

func _cross(r: Rect2, c: Color) -> void:
	var mid: Vector2 = r.get_center()
	draw_line(Vector2(mid.x, r.position.y), Vector2(mid.x, r.end.y), c, -1.0)
	draw_line(Vector2(r.position.x, mid.y), Vector2(r.end.x, mid.y), c, -1.0)
