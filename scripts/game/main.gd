## Phase-0 entry point. Nothing is built yet -- see GDD 6 for the build plan.
extends Node2D

func _ready() -> void:
	print("Quadtree Miner -- scaffold. atom = %dpx, standard block = %dpx." % [
		Atoms.PX, Atoms.STANDARD_BLOCK * Atoms.PX
	])
