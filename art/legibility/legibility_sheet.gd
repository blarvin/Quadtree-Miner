## The GDD 6 legibility test. "Draw one block at actual pixel size,
## subdivided 1, 2, 3, and 4 levels deep, plus the three channels of 4.1.2
## (colour class, border, fracture) overlaid. Find where it stops reading."
##
## This is a MEASUREMENT, not a renderer. It draws idealised subdivision
## grids -- it deliberately does not go through the template engine, because
## the question is about pixels, not rules.
##
##   godot --path . art/legibility/legibility.tscn
##
## Writes TWO files and quits:
##
##   sheet.png        1:1 with the 640x360 framebuffer. The px/atom labels
##                    are literal here. This is NOT what you see on screen.
##   sheet_screen.png the same sheet upscaled by DISPLAY_SCALE with
##                    nearest-neighbour -- i.e. actual physical pixels on a
##                    1080p panel, where the game integer-scales 640x360 by 3.
##                    View THIS one at 100% zoom to judge legibility.
extends Node

const SHEET_W: int = LegibilitySheet.SHEET_W
const SHEET_H: int = LegibilitySheet.SHEET_H

## Integer scale the game gets on the target display:
##   640x360 -> 1920x1080 is exactly 3x. A 720p panel would be 2x.
const DISPLAY_SCALE: int = 3

func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SHEET_W, SHEET_H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(LegibilitySheet.new())
	add_child(vp)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	var err: int = img.save_png(ProjectSettings.globalize_path("res://art/legibility/sheet.png"))
	print("1:1 framebuffer  -> sheet.png (%dx%d)" % [SHEET_W, SHEET_H])

	# Nearest-neighbour: an upscaled pixel must stay a hard square, or we are
	# measuring the resampler instead of the artwork.
	img.resize(SHEET_W * DISPLAY_SCALE, SHEET_H * DISPLAY_SCALE, Image.INTERPOLATE_NEAREST)
	var err2: int = img.save_png(ProjectSettings.globalize_path("res://art/legibility/sheet_screen.png"))
	print("%dx on-screen     -> sheet_screen.png (%dx%d)  <- judge legibility here" % [
		DISPLAY_SCALE, SHEET_W * DISPLAY_SCALE, SHEET_H * DISPLAY_SCALE])
	get_tree().quit(0 if err == OK and err2 == OK else 1)
