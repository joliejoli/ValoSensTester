extends SceneTree

# 全场景实例化检查：确保每个场景脚本无编译/运行时错误

var scenes := [
	"res://main.tscn",
	"res://test_select.tscn",
	"res://test_config.tscn",
	"res://test_shoot.tscn",
	"res://test_result.tscn",
	"res://history.tscn",
	"res://settings.tscn",
	"res://about.tscn",
]

var failures := 0

func _init() -> void:
	await process_frame
	for s in scenes:
		var ps := load(s)
		if ps == null:
			failures += 1
			print("FAIL 无法加载 ", s)
			continue
		var inst: Node = (ps as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame
		print("PASS 实例化 ", s)
		inst.queue_free()
		await process_frame
	print("失败数: ", failures)
	quit(1 if failures > 0 else 0)
