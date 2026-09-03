## ONE STRIKE = ONE HP AT ONE ATOM. GDD 4.3.2, invariant 10.
##
## A strike lands at a single point and damages whichever LEAF currently sits
## under it. A tool never hits several nodes: covering the character's 8-atom
## cross-section is done TEMPORALLY, by cycling the impact point across
## successive strikes (the scan, GDD 4.3.2 -- not built yet), never by widening
## the hit region. Widening it would make a strike no longer a strike, and would
## move damage-spreading authority out of the template where it belongs.
##
## What a strike may do is CASCADE: pass_down (GDD 4.4.1) flows leftover HP into
## the child under the same impact point. That is still one blow at one point.
##
## Block-local coordinates throughout -- the block's own origin is the World's
## business (Stage 4). Everything here is engine-pure.
class_name Strike
extends RefCounted

## What a break yielded. Count is DERIVED (GDD 4.7, invariant 12), and the
## node's own origin/size ride along so the World can place the units.
class Yield extends RefCounted:
	var drop: Drop
	var count: int
	var node_origin: Vector2i  ## block-local, in atoms
	var node_size: int

	func _init(p_drop: Drop, p_count: int, p_origin: Vector2i, p_size: int) -> void:
		drop = p_drop
		count = p_count
		node_origin = p_origin
		node_size = p_size

	func _to_string() -> String:
		return "%d x %s from size-%d node" % [count, drop, node_size]

class Result extends RefCounted:
	## False when the impact point landed in a quadrant that was already mined
	## out. Picking a different target is the scan's job (GDD 4.3.2), not ours.
	var hit: bool = false
	var struck_size: int = 0
	## Sizes broken, in cascade order: [16] for one break, [16, 8, 4, 2] for a
	## sand collapse. This is the shape of the blow.
	var broke: Array[int] = []
	var subdivided: int = 0
	var mined: int = 0
	var yields: Array[Yield] = []
	var revealed: Array[BlockNode] = []
	## The block's ROOT was mined: the whole block is gone and the World must
	## drop it from the index. Void is the absence of a block (invariant 4).
	var block_destroyed: bool = false

	func describe() -> String:
		if not hit:
			return "no hit (void)"
		return "hit size %d, broke %s, %d subdivided, %d mined, %d revealed%s" % [
			struck_size, broke, subdivided, mined, revealed.size(),
			", BLOCK DESTROYED" if block_destroyed else "",
		]

## Where a blow landed: the leaf, plus the context needed to look its rule up.
## PATHS ARE NEVER STORED ON NODES -- every operation descends from the root
## anyway, so the path accumulates for free. Caching one on a node would be a
## second writer for derived state and a way for it to go stale (cf. GDD 5.2).
class Site extends RefCounted:
	var node: BlockNode = null  ## null means the point is void inside the block
	var parent: BlockNode = null
	var quad: int = -1
	var path: Array[int] = []
	var origin: Vector2i = Vector2i.ZERO  ## of `node`, block-local

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
##
## The loop: add HP -> reveal -> break if it reached resistance -> either the
## node is destroyed (terminal) or it subdivides, and only then may leftover HP
## continue into the child under the same point.
static func apply(root: BlockNode, template: BlockTemplate, local: Vector2i, hp: float) -> Result:
	assert(hp > 0.0, "a strike delivers HP")
	assert(local.x >= 0 and local.y >= 0 and local.x < root.size and local.y < root.size,
		"impact point %s is outside a size-%d block" % [local, root.size])

	var res := Result.new()
	var site: Site = site_at(root, local)
	if site.node == null:
		return res  # already mined out here

	res.hit = true
	res.struck_size = site.node.size

	var node: BlockNode = site.node
	var parent: BlockNode = site.parent
	var quad: int = site.quad
	var path: Array[int] = site.path
	var origin: Vector2i = site.origin
	var incoming: float = hp

	while true:
		node.damage += incoming
		## Reveal happens on ANY damage, not only on a break -- GDD 4.5 strike
		## one reveals the fracture pattern WITHOUT subdividing. That single
		## number is what turns digging into a decision.
		res.revealed.append_array(_reveal(node, parent, path, template))

		var rule: Rule = template.rule_at(path, node.size)
		if node.damage < rule.resistance:
			break

		var surplus: float = node.damage - rule.resistance
		res.broke.append(node.size)

		## An atom cannot subdivide (GDD 4.0), so a break at size 1 destroys it
		## whatever the rule says. Arithmetic terminator, not a special case --
		## and not something a template can get wrong.
		if rule.on_break == Rule.OnBreak.MINE or node.size == Atoms.ATOM:
			res.mined += 1
			if rule.drop != null:
				res.yields.append(Yield.new(
					rule.drop, rule.drop.count_from(node.size), origin, node.size))
			if parent == null:
				res.block_destroyed = true
			else:
				## Void at that quadrant. The parent is kept even when all four
				## go: collapsing it would discard its persisted `revealed`.
				parent.children[quad] = null
			break

		node.subdivide()
		res.subdivided += 1

		## GDD 4.4.1. Without pass_down the surplus is DISCARDED and each level
		## is a fresh wall. Note this is also what happens when pass_down is
		## true but the tool did not overdeliver: a 1 HP pickaxe into a
		## resistance-1 node leaves zero surplus, so the block grinds level by
		## level regardless of the flag (GDD 4.3.1).
		if not rule.pass_down:
			break
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

## GDD 4.6.4: a strike reveals the node struck AND any sibling SHARING ITS RULE.
## A terminal core with a different rule stays unrevealed until struck itself --
## which is what makes the hidden core (4.6.3) hold even inside a block whose
## outer material the player already knows.
##
## "Sharing its rule" is value equality: identical rules mean identical
## behaviour, so there is nothing to learn by telling them apart.
static func _reveal(node: BlockNode, parent: BlockNode, path: Array[int],
		template: BlockTemplate) -> Array[BlockNode]:
	var out: Array[BlockNode] = []
	if not node.revealed:
		node.revealed = true
		out.append(node)
	if parent == null:
		return out

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
			out.append(sibling)
	return out
