## One strike = one HP at one atom (GDD 4.3.2). The blow lands on the leaf
## under the point; pass_down may cascade it into the child under the same
## point. Block-local coordinates throughout.
class_name Strike
extends RefCounted

class Yield extends RefCounted:
	var drop: Drop
	var count: int
	var node_origin: Vector2i  ## block-local
	var node_size: int

	func _init(p_drop: Drop, p_count: int, p_origin: Vector2i, p_size: int) -> void:
		drop = p_drop
		count = p_count
		node_origin = p_origin
		node_size = p_size

	func _to_string() -> String:
		return "%d x %s from size-%d node" % [count, drop, node_size]

class Result extends RefCounted:
	var hit: bool = false            ## false: the point was already mined out
	var broke: Array[int] = []       ## sizes broken, in cascade order
	var mined: bool = false          ## the last break was terminal
	var yields: Array[Yield] = []
	var block_destroyed: bool = false  ## the root was mined; World must drop the block

## The leaf under a point plus the context needed to look its rule up.
## Paths are never stored on nodes; they accumulate during descent.
class Site extends RefCounted:
	var node: BlockNode = null  ## null: void inside the block
	var parent: BlockNode = null
	var quad: int = -1
	var path: Array[int] = []
	var origin: Vector2i = Vector2i.ZERO

static func site_at(root: BlockNode, local: Vector2i) -> Site:
	var s := Site.new()
	s.node = root
	while not s.node.is_leaf():
		var q: int = Quad.index_of(local, s.origin, s.node.size)
		var child: BlockNode = s.node.children[q]
		if child == null:
			s.node = null
			return s
		s.parent = s.node
		s.quad = q
		s.origin = Quad.child_origin(q, s.origin, s.node.size)
		s.path.append(q)
		s.node = child
	return s

## Deliver `hp` at block-local atom `local`.
static func apply(root: BlockNode, template: BlockTemplate, local: Vector2i, hp: float) -> Result:
	assert(hp > 0.0, "a strike delivers HP")
	assert(Rect2i(Vector2i.ZERO, Vector2i(root.size, root.size)).has_point(local),
		"impact point %s is outside a size-%d block" % [local, root.size])

	var res := Result.new()
	var site: Site = site_at(root, local)
	if site.node == null:
		return res
	res.hit = true

	var node: BlockNode = site.node
	var parent: BlockNode = site.parent
	var quad: int = site.quad
	var path: Array[int] = site.path
	var origin: Vector2i = site.origin
	var incoming: float = hp

	while true:
		node.damage += incoming
		_reveal(node, parent, path, template)  # any damage reveals (GDD 4.5)

		var rule: Rule = template.rule_at(path, node.size)
		if node.damage < rule.resistance:
			break
		var surplus: float = node.damage - rule.resistance
		res.broke.append(node.size)

		# An atom cannot subdivide, so a break at size 1 destroys it regardless.
		if rule.on_break == Rule.OnBreak.MINE or node.size == 1:
			res.mined = true
			if rule.drop != null:
				res.yields.append(Yield.new(rule.drop, rule.drop.count_from(node.size), origin, node.size))
			if parent == null:
				res.block_destroyed = true
			else:
				parent.children[quad] = null  # parent kept: it holds persisted `revealed`
			break

		node.subdivide()
		if not rule.pass_down:
			break  # surplus discarded: each level is a fresh wall (GDD 4.4.1)
		var carried: float = surplus * rule.pass_down_falloff
		if carried <= 0.0:
			break

		var next_q: int = Quad.index_of(local, origin, node.size)
		origin = Quad.child_origin(next_q, origin, node.size)
		parent = node
		quad = next_q
		path = path.duplicate()
		path.append(next_q)
		node = parent.children[next_q]
		incoming = carried

	return res

## Reveals the node struck and any sibling sharing its rule (GDD 4.6.4).
static func _reveal(node: BlockNode, parent: BlockNode, path: Array[int], template: BlockTemplate) -> void:
	node.revealed = true
	if parent == null:
		return
	var rule: Rule = template.rule_at(path, node.size)
	var parent_path: Array[int] = path.slice(0, path.size() - 1)
	for q: int in 4:
		var sibling: BlockNode = parent.children[q]
		if sibling == null or sibling == node or sibling.revealed:
			continue
		var sibling_path: Array[int] = parent_path.duplicate()
		sibling_path.append(q)
		if template.rule_at(sibling_path, sibling.size).equals(rule):
			sibling.revealed = true
