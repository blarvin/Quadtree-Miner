## Draws placed ladder units in atom units.
extends Node2D

@export var rail_color: Color = Color(0.75, 0.55, 0.25)
@export var rung_color: Color = Color(0.85, 0.65, 0.30)
@export var rung_spacing: int = 2  ## atoms

var ladders: Ladders = null

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if ladders == null:
		return
	for u: Rect2i in ladders.units:
		var r := Rect2(u)
		draw_line(r.position + Vector2(1, 0), Vector2(r.position.x + 1, r.end.y), rail_color, 1.0)
		draw_line(Vector2(r.end.x - 1, r.position.y), r.end - Vector2(1, 0), rail_color, 1.0)
		var y: float = r.position.y + 1.0
		while y < r.end.y:
			draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), rung_color, -1.0)
			y += float(rung_spacing)
