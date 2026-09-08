## One strike = one HP at one atom (GDD 6.1). The blow lands on the leaf
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
	var mined: bool = false          ## some break in the wave was terminal
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

## Deliver `hp` at block-local atom `local`. `blow` is the direction the tool
## travelled; only the `inline` spread pattern reads it (GDD 3.2).
static func apply(root: BlockNode, template: BlockTemplate, local: Vector2i, hp: float,
		blow: Vector2i = Vector2i.ZERO) -> Result:
	assert(hp > 0.0, "a strike delivers HP")
	assert(Rect2i(Vector2i.ZERO, Vector2i(root.size, root.size)).has_point(local),
		"impact point %s is outside a size-%d block" % [local, root.size])

	var res := Result.new()
	if site_at(root, local).node == null:
		return res
	res.hit = true

	# The blow lands at one point (GDD 6.1); what the material does with the
	# surplus is a wave (GDD 3.2). A delivery is a point and an amount, resolved
	# against the tree as it stands when it is taken up. Each node takes one
	# delivery per strike and breaks at most once, so the block's own node count
	# bounds the wave -- no iteration cap is needed.
	var seen: Dictionary = {}
	var queue: Array[Array] = [[local, hp]]
	while not queue.is_empty():
		var job: Array = queue.pop_front()
		var site: Site = site_at(root, job[0])
		if site.node == null or seen.has(site.node):
			continue
		seen[site.node] = true

		var node: BlockNode = site.node
		node.damage += job[1]
		_reveal(node, site.parent, site.path, template)  # any damage reveals (GDD 4.3)

		var rule: Rule = template.rule_at(site.path, node.size)
		if node.damage < rule.resistance:
			continue
		var surplus: float = node.damage - rule.resistance
		if rule.on_break == Rule.OnBreak.SHATTER and node.size > 1:
			_shatter(node, template, site.path, res)
			continue  # a shatter has no surplus: the blow is spent fracturing
		res.broke.append(node.size)

		# An atom cannot subdivide, so a break at size 1 destroys it regardless.
		if rule.on_break == Rule.OnBreak.MINE or node.size == 1:
			res.mined = true
			if rule.drop != null:
				res.yields.append(Yield.new(rule.drop, rule.drop.count_from(node.size),
					site.origin, node.size))
			if site.parent == null:
				res.block_destroyed = true
			else:
				site.parent.children[site.quad] = null  # parent kept: it holds persisted `revealed`
		else:
			node.subdivide()
			if rule.pass_down:
				var carried: float = surplus * rule.pass_down_falloff
				if carried > 0.0:
					queue.append([_toward(local, site), carried])
			# pass_down false discards the surplus down the tree: each level is
			# a fresh wall (GDD 3.2). It may still travel sideways.
		_spread(queue, root, site, rule, surplus, blow)

	return res

## Fracture a subtree to its floor (GDD 3): every descendant instantiated
## until its own rule turns terminal, and revealed -- you watched it come
## apart, so nothing about the structure is still hidden. A terminal child is
## exposed but not opened; it has no inside to show (GDD 5.2).
static func _shatter(node: BlockNode, template: BlockTemplate, path: Array[int],
		res: Result) -> void:
	if node.size == 1 or template.rule_at(path, node.size).on_break == Rule.OnBreak.MINE:
		return
	if node.is_leaf():
		node.subdivide()
	res.broke.append(node.size)
	for q: int in 4:
		var child: BlockNode = node.children[q]
		if child == null:
			continue
		child.revealed = true
		var child_path: Array[int] = path.duplicate()
		child_path.append(q)
		_shatter(child, template, child_path, res)

## The blow's point, pulled inside a node the wave has reached sideways, so
## every node passes its surplus down toward the impact rather than nowhere.
static func _toward(local: Vector2i, site: Site) -> Vector2i:
	var span: Vector2i = Vector2i.ONE * (site.node.size - 1)
	return local.clamp(site.origin, site.origin + span)

## The surplus of a broken node -- mined or subdivided -- travelling to what
## is around it (GDD 3.2). Directions are spatial: one node-width out, resolved
## against whatever owns that point, so the wave crosses parents instead of
## being trapped among four siblings. Each neighbour is sent a copy, never a
## share: falloff is the only damping, and the diagonals are one step further.
static func _spread(queue: Array[Array], root: BlockNode, site: Site, rule: Rule,
		surplus: float, blow: Vector2i) -> void:
	var carried: float = surplus * rule.pass_through_falloff
	if rule.pass_through == Rule.PassThrough.NONE or carried <= 0.0:
		return
	var size: int = site.node.size
	var mid: Vector2i = site.origin + Vector2i.ONE * (size >> 1)
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(root.size, root.size))
	for d: Vector2i in _pattern(rule.pass_through, blow):
		var at: Vector2i = mid + d * size
		if not bounds.has_point(at):
			continue  # a block never spreads into its neighbours (GDD 2)
		var hp: float = carried * (rule.pass_through_falloff if d.x != 0 and d.y != 0 else 1.0)
		if hp > 0.0:
			queue.append([at, hp])

## Which way a pattern sends the surplus (GDD 3.2).
static func _pattern(pattern: Rule.PassThrough, blow: Vector2i) -> Array[Vector2i]:
	match pattern:
		Rule.PassThrough.INLINE:
			var axis: Vector2i = Vector2i(signi(blow.x), 0) if blow.x != 0 				else Vector2i(0, signi(blow.y))
			if axis == Vector2i.ZERO:
				axis = Vector2i.RIGHT  # blow unknown: the grain runs across
			return [axis, -axis] as Array[Vector2i]
		Rule.PassThrough.LATERAL:
			return [Vector2i.LEFT, Vector2i.RIGHT] as Array[Vector2i]
		Rule.PassThrough.DOWNWARD:
			return [Vector2i.DOWN] as Array[Vector2i]
		Rule.PassThrough.RADIAL:
			return [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
				Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)] as Array[Vector2i]
	return [] as Array[Vector2i]

## Reveals the node struck and any sibling sharing its rule (GDD 5.1).
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
