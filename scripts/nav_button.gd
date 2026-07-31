extends Button

@export var target_scene: String = ""

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if target_scene.is_empty():
		push_warning("nav_button: target_scene 未设置")
		return
	get_tree().change_scene_to_file(target_scene)
