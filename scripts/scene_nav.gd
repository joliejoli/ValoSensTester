static func go(scene_path: String, node: Node) -> bool:
	var tree := node.get_tree()
	if tree == null:
		push_error("SceneNav: 节点不在场景树中")
		return false
	var err := tree.change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneNav: 场景切换失败 %s (error %d)" % [scene_path, err])
		return false
	return true
