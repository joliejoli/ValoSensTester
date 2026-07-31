extends Button

const SceneNav := preload("res://scripts/scene_nav.gd")

@export var target_scene: String = ""

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if target_scene.is_empty():
		push_warning("nav_button: target_scene 未设置")
		return
	SceneNav.go(target_scene, self)
