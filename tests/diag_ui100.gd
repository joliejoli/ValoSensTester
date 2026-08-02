extends SceneTree

func _init() -> void:
	await process_frame
	print("before content_scale_factor=", root.content_scale_factor, " root.size=", root.size)
	root.content_scale_factor = 1.0
	await process_frame
	print("after  content_scale_factor=", root.content_scale_factor, " root.size=", root.size)
	var inst: Control = (load("res://test_select.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	for i in 8:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("M:/system/temp/opencode/shot_ui100.png")
	var lbl := inst.get_node("TopBar/TitleLabel") as Label
	print("lbl_rect=", lbl.get_global_rect())
	inst.queue_free()
	print("SAVED")
	quit(0)
