extends Control

const SceneNav := preload("res://scripts/scene_nav.gd")

func _on_info_button_pressed() -> void:
	%Popup.visible = true

func _on_dialog_ok_pressed() -> void:
	%Popup.visible = false

func _on_start_button_pressed() -> void:
	if %PsaButton.button_pressed:
		TestConfig.test_type = TestConfig.TestType.PSA_BINARY
	else:
		TestConfig.test_type = TestConfig.TestType.CONSISTENCY
	SceneNav.go("res://test_config.tscn", self)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if %Popup.visible:
			%Popup.visible = false
		else:
			SceneNav.go("res://main.tscn", self)
