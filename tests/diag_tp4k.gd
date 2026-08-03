extends SceneTree

func _init() -> void:
	await process_frame
	var inst: Control = (load("res://history.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	inst._on_trend_pressed()
	for i in 6:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("M:/system/temp/opencode/shot_trend_4k.png")
	var tp: Control = inst.trend_popup
	print("TrendPopup visible=", tp.visible, " size=", tp.size)
	var card := inst.get_node("TrendPopup/Center/TrendCard")
	print("TrendCard size=", card.size, " global=", card.get_global_rect())
	for c in inst.trend_box.get_children():
		print("Chart size=", c.size, " global=", c.get_global_rect())
	inst.queue_free()
	quit(0)
