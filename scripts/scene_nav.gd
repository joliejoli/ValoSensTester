# 场景切换封装（Phase 1）：带错误检查 + 切换后淡入过渡（Phase 7 UI/UX）
# 注意：不引用 TestConfig（headless --script 编译期不可用）

static func go(scene_path: String, node: Node) -> bool:
	var tree := node.get_tree()
	if tree == null:
		push_error("SceneNav: 节点不在场景树中")
		return false
	var err := tree.change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneNav: 场景切换失败 %s (error %d)" % [scene_path, err])
		return false
	_add_fade_in(tree.current_scene)
	return true

# 切换后淡入：CanvasLayer 顶层遮罩 黑→透明 0.25s，然后自毁
static func _add_fade_in(scene: Node) -> void:
	if scene == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 1)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var tw := layer.create_tween()
	tw.tween_property(dim, "color:a", 0.0, 0.25)
	tw.tween_callback(layer.queue_free)
