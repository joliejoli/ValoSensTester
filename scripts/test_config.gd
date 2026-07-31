extends Control

@onready var sens_min_spin: SpinBox = %SensMinSpin
@onready var sens_max_spin: SpinBox = %SensMaxSpin
@onready var rounds_spin: SpinBox = %RoundsSpin
@onready var target_type_option: OptionButton = %TargetTypeOption
@onready var target_size_option: OptionButton = %TargetSizeOption
@onready var test_mode_option: OptionButton = %TestModeOption

func _ready() -> void:
	sens_min_spin.value = TestConfig.sens_min
	sens_max_spin.value = TestConfig.sens_max
	rounds_spin.value = TestConfig.rounds
	target_type_option.select(TestConfig.target_type)
	target_size_option.select(TestConfig.target_size)
	test_mode_option.select(TestConfig.test_mode)

func _on_start_button_pressed() -> void:
	TestConfig.sens_min = sens_min_spin.value
	TestConfig.sens_max = sens_max_spin.value
	TestConfig.rounds = int(rounds_spin.value)
	TestConfig.target_type = target_type_option.selected
	TestConfig.target_size = target_size_option.selected
	TestConfig.test_mode = test_mode_option.selected
	get_tree().change_scene_to_file("res://test_shoot.tscn")
