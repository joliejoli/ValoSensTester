extends Control

func _on_test_select_button_pressed() -> void:
	get_tree().change_scene_to_file("res://test_select.tscn")

func _on_history_button_pressed() -> void:
	get_tree().change_scene_to_file("res://history.tscn")

func _on_settings_button_pressed() -> void:
	get_tree().change_scene_to_file("res://settings.tscn")

func _on_about_button_pressed() -> void:
	get_tree().change_scene_to_file("res://about.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()
