## One reversible change to a World's block set (GDD 6, Phase 1 authoring).
## An edit is the whole undo unit: what it removed and what it added.
##
## Order matters. apply() removes before adding, revert() the mirror, so the
## World's non-overlap assert (GDD 4.1) holds at every step.
class_name MapEdit
extends RefCounted

var removed: Array[BlockInstance] = []
var added: Array[BlockInstance] = []

func is_empty() -> bool:
	return removed.is_empty() and added.is_empty()

func apply(world: World) -> void:
	for b: BlockInstance in removed:
		world.remove(b)
	for b: BlockInstance in added:
		world.add(b)

func revert(world: World) -> void:
	for b: BlockInstance in added:
		world.remove(b)
	for b: BlockInstance in removed:
		world.add(b)

func _to_string() -> String:
	return "MapEdit(-%d +%d)" % [removed.size(), added.size()]

## A drag is many stamps but one undo step. Absorbing keeps the *net* change:
## a block this stroke added and then painted over never reaches the stack, so
## reverting cannot resurrect it.
class Stroke extends RefCounted:
	var _removed: Dictionary = {}  ## BlockInstance -> true, insertion ordered
	var _added: Dictionary = {}

	func absorb(e: MapEdit) -> void:
		for b: BlockInstance in e.removed:
			if _added.has(b):
				_added.erase(b)   # born and died inside this stroke
			else:
				_removed[b] = true
		for b: BlockInstance in e.added:
			_added[b] = true

	func is_empty() -> bool:
		return _removed.is_empty() and _added.is_empty()

	func to_edit() -> MapEdit:
		var e := MapEdit.new()
		for b: BlockInstance in _removed:
			e.removed.append(b)
		for b: BlockInstance in _added:
			e.added.append(b)
		return e
