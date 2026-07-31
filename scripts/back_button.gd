extends Button

const SceneNav := preload("res://scripts/scene_nav.gd")

func _ready() -> void:
	pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	SceneNav.go("res://main.tscn", self)
