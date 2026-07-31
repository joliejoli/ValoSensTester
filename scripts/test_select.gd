extends Control

func _on_info_button_pressed() -> void:
	%InfoDialog.popup_centered()

func _on_start_button_pressed() -> void:
	if %PsaButton.button_pressed:
		TestConfig.test_type = TestConfig.TestType.PSA_BINARY
	else:
		TestConfig.test_type = TestConfig.TestType.CONSISTENCY
	get_tree().change_scene_to_file("res://test_config.tscn")
