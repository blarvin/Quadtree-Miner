## The node model (GDD 4.3, 5.2).
extends RefCounted

var runner: SceneTree

func test_an_unstruck_block_is_one_node() -> void:
	var root := BlockNode.new(16)
	runner.check(root.is_leaf(), "fresh node is a leaf")
	runner.check_eq(root.node_count(), 1, "one node, not 256")

func test_subdivide_halves_size_down_to_the_atom() -> void:
	var node := BlockNode.new(16)
	var sizes: Array[int] = []
	while node.size > 1:
		sizes.append(node.size)
		node.subdivide()
		runner.check_eq(node.children.size(), 4, "four children")
		node = node.children[0]
	sizes.append(node.size)
	runner.check_eq(sizes, [16, 8, 4, 2, 1], "16 -> 8 -> 4 -> 2 -> atom")

func test_mined_slot_is_not_the_same_as_leaf() -> void:
	var root := BlockNode.new(16)
	runner.check(not root.is_void_at(0), "an unsubdivided node has no void quadrants")
	root.subdivide()
	root.children[Quad.BL] = null
	runner.check(root.is_void_at(Quad.BL), "the mined quadrant reads as void")
	runner.check(not root.is_void_at(Quad.TL), "its siblings do not")
	runner.check(not root.is_leaf(), "the parent is still not a leaf")
	runner.check_eq(root.live_children().size(), 3, "three boundaries a fracture can draw")

func test_node_count_ignores_mined_slots() -> void:
	var root := BlockNode.new(16)
	root.subdivide()
	root.children[Quad.TL].subdivide()
	runner.check_eq(root.node_count(), 9, "root + 4 + 4")
	root.children[Quad.TL] = null
	runner.check_eq(root.node_count(), 4, "mining the subtree takes its nodes with it")
