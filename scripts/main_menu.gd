extends Control

const SceneNav := preload("res://scripts/scene_nav.gd")

func _on_test_select_button_pressed() -> void:
	TestConfig.reset()
	SceneNav.go("res://test_select.tscn", self)

func _on_history_button_pressed() -> void:
	SceneNav.go("res://history.tscn", self)

func _on_settings_button_pressed() -> void:
	SceneNav.go("res://settings.tscn", self)

func _on_about_button_pressed() -> void:
	SceneNav.go("res://about.tscn", self)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
