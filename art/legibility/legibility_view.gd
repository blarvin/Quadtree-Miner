## The GDD 6 legibility sheet ON SCREEN, at true physical pixels.
##
## No PNG, no image viewer, no browser zoom, no Windows DPI scaling in the
## path -- the three things that have each lied about this sheet already.
## Godot is DPI-aware, so a pixel here is a pixel on the panel.
##
##   godot --path . art/legibility/legibility_view.tscn
##
##   1 / 2 / 3   view at 1x / 2x / 3x framebuffer scale (3x = 1080p game)
##   arrows, wheel, drag   scroll
##   F           fullscreen
##   Esc         quit
extends Node2D

const SCROLL_SPEED: float = 900.0

var _sheet: LegibilitySheet
var _hud: Control
var _scale: int = 3
var _offset: Vector2 = Vector2(0, 0)
var _dragging: bool = false

func _ready() -> void:
	# This scene must NOT go through the game's 640x360 stretch -- the whole
	# point is 1:1 with the display.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(1600, 900)
	get_window().move_to_center()

	_sheet = LegibilitySheet.new()
	add_child(_sheet)

	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)

	_apply()

func _apply() -> void:
	var view: Vector2 = get_viewport_rect().size
	var sheet_px := Vector2(LegibilitySheet.SHEET_W, LegibilitySheet.SHEET_H) * float(_scale)
	# Clamp so the sheet cannot be scrolled entirely off screen.
	_offset.x = clampf(_offset.x, minf(0.0, view.x - sheet_px.x), 0.0)
	_offset.y = clampf(_offset.y, minf(0.0, view.y - sheet_px.y - 40.0), 0.0)
	_sheet.scale = Vector2(_scale, _scale)
	_sheet.display_scale = _scale
	_sheet.position = Vector2(_offset.x, _offset.y + 40.0)
	_hud.queue_redraw()

func _process(delta: float) -> void:
	var d := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))
	if d != Vector2.ZERO:
		_offset -= d * SCROLL_SPEED * delta
		_apply()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_F:
				var w: Window = get_window()
				w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
				await get_tree().process_frame
				_apply()
			KEY_1, KEY_2, KEY_3:
				_scale = e.keycode - KEY_0
				_apply()
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_offset.y += 90.0
			_apply()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_offset.y -= 90.0
			_apply()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
	elif e is InputEventMouseMotion and _dragging:
		_offset += e.relative
		_apply()

func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	var w: float = get_viewport_rect().size.x
	_hud.draw_rect(Rect2(0, 0, w, 40), Color("11111a"), true)
	var note: String = "  <- the real 1080p game scale" if _scale == 3 else "  (below game scale)"
	_hud.draw_string(font, Vector2(12, 26),
		"Viewing at %dx framebuffer scale%s     Physical sizes are printed under each column heading." % [
			_scale, note],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ddd6c6"))
	_hud.draw_string(font, Vector2(w - 470, 26),
		"1/2/3 scale   arrows+wheel+drag scroll   F fullscreen   Esc quit",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8c8578"))
