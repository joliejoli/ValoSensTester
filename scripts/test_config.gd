extends Control

const SceneNav := preload("res://scripts/scene_nav.gd")

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
	if TestConfig.test_type == TestConfig.TestType.CONSISTENCY:
		%SensMaxLabel.visible = false
		%SensMaxSpin.visible = false
		%SensMinLabel.text = "灵敏度 (cm/360°)"
	sens_min_spin.value_changed.connect(_on_sens_changed)
	sens_max_spin.value_changed.connect(_on_sens_changed)

func _on_sens_changed(_value: float) -> void:
	%ErrorLabel.visible = false

func _on_start_button_pressed() -> void:
	TestConfig.sens_min = sens_min_spin.value
	TestConfig.sens_max = sens_max_spin.value
	TestConfig.rounds = int(rounds_spin.value)
	TestConfig.target_type = target_type_option.selected
	TestConfig.target_size = target_size_option.selected
	TestConfig.test_mode = test_mode_option.selected
	if TestConfig.test_type == TestConfig.TestType.CONSISTENCY:
		TestConfig.sens_max = sens_min_spin.value
	if TestConfig.sens_min >= TestConfig.sens_max:
		%ErrorLabel.visible = true
		return
	SceneNav.go("res://test_shoot.tscn", self)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneNav.go("res://test_select.tscn", self)
