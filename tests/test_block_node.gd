## The node model. GDD 4.3, 4.7.1, 5.2.
extends RefCounted

var runner: SceneTree

func test_an_unstruck_block_is_one_node() -> void:
	# GDD 4.7.1 -- this is the claim that makes persistence cheap. Not a
	# compression trick: children do not exist until a break creates them.
	var root := BlockNode.new(16)
	runner.check(root.is_leaf(), "a fresh block has no children")
	runner.check_eq(root.node_count(), 1, "an unstruck size-16 block is ONE node, not 256")
	runner.check_eq(root.damage, 0.0, "and no damage")
	runner.check_eq(root.revealed, false, "and is unrevealed")

func test_subdivide_halves_size_once() -> void:
	var root := BlockNode.new(16)
	root.subdivide()
	runner.check_eq(root.children.size(), 4, "four children, indexed Q0..Q3")
	for c: BlockNode in root.children:
		runner.check_eq(c.size, 8, "child.size = parent.size >> 1 -- the only writer besides load")
		runner.check(c.is_leaf(), "children are created as leaves")
	runner.check_eq(root.node_count(), 5, "one node became five")
	runner.check(not root.is_leaf(), "the parent is no longer a leaf")

func test_size_is_a_power_of_two_all_the_way_down() -> void:
	var node := BlockNode.new(16)
	var sizes: Array[int] = []
	while node.size > 1:
		sizes.append(node.size)
		node.subdivide()
		node = node.children[0]
	sizes.append(node.size)
	runner.check_eq(sizes, [16, 8, 4, 2, 1], "16 -> 8 -> 4 -> 2 -> atom (GDD 4.2)")
	for s: int in sizes:
		runner.check(Atoms.is_valid_size(s), "size %d is a valid power of two" % s)

func test_mined_slot_is_not_the_same_as_leaf() -> void:
	# The one thing GDD 5.1's `children: [Node x4] | null` leaves open: how a
	# DESTROYED child is represented. A null SLOT is void at that quadrant;
	# an EMPTY children array is a node that never subdivided. Two different
	# facts, two different fields, no new state.
	var root := BlockNode.new(16)
	runner.check(root.is_leaf(), "never subdivided")
	runner.check(not root.is_void_at(0), "an unsubdivided node has no void quadrants")

	root.subdivide()
	runner.check(not root.is_leaf(), "subdivided")
	runner.check(not root.is_void_at(0), "and nothing mined yet")

	root.children[Quad.BL] = null
	runner.check(root.is_void_at(Quad.BL), "the mined quadrant reads as void")
	runner.check(not root.is_void_at(Quad.TL), "its siblings do not")
	runner.check(not root.is_leaf(), "and the parent is still not a leaf")

func test_live_children_is_what_a_fracture_can_draw() -> void:
	# GDD 4.6.3: a fracture draws boundaries BETWEEN CHILDREN THAT EXIST.
	# That is the whole opacity rule -- there is no reveal_depth (invariant 9).
	var root := BlockNode.new(16)
	runner.check_eq(root.live_children().size(), 0,
		"a terminal or unstruck node has no child boundaries, so it is opaque")
	root.subdivide()
	runner.check_eq(root.live_children().size(), 4, "a 4-way cross is drawable")
	root.children[Quad.TR] = null
	runner.check_eq(root.live_children().size(), 3, "a mined quadrant is not a boundary")

func test_node_count_ignores_mined_slots() -> void:
	var root := BlockNode.new(16)
	root.subdivide()
	root.children[Quad.TL].subdivide()
	runner.check_eq(root.node_count(), 9, "root + 4 + 4")
	root.children[Quad.TL] = null
	runner.check_eq(root.node_count(), 4, "mining the subtree takes its nodes with it")

func test_revealed_is_only_ever_set() -> void:
	# GDD 4.6.1 / invariant 7: fractures never heal. Nothing in the engine
	# clears this flag, so it is a permanent annotation on the terrain.
	var node := BlockNode.new(4)
	node.revealed = true
	node.subdivide()
	runner.check(node.revealed, "subdividing does not un-reveal")
