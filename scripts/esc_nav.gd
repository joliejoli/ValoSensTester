extends Node

const SceneNav := preload("res://scripts/scene_nav.gd")

@export var esc_scene: String = "res://main.tscn"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneNav.go(esc_scene, self)
