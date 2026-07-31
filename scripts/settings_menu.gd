extends Control

const UI_SCALE_OPTIONS := [0.0, 1.0, 1.25, 1.5]

@onready var dpi_spin: SpinBox = %DpiSpin
@onready var fov_spin: SpinBox = %FovSpin
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue
@onready var ui_scale_option: OptionButton = %UiScaleOption

func _ready() -> void:
	load_settings()
	dpi_spin.value_changed.connect(_on_dpi_changed)
	fov_spin.value_changed.connect(_on_fov_changed)
	volume_slider.value_changed.connect(_on_volume_changed)
	ui_scale_option.item_selected.connect(_on_ui_scale_selected)
	apply_volume()

func _on_dpi_changed(_value: float) -> void:
	save_settings()

func _on_fov_changed(_value: float) -> void:
	save_settings()

func _on_volume_changed(_value: float) -> void:
	apply_volume()
	save_settings()

func _on_ui_scale_selected(index: int) -> void:
	TestConfig.ui_scale = UI_SCALE_OPTIONS[index]
	TestConfig.apply_ui_scale()
	save_settings()

func apply_volume() -> void:
	volume_value.text = "%d%%" % int(volume_slider.value)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(volume_slider.value / 100.0))

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("mouse", "dpi", int(dpi_spin.value))
	config.set_value("game", "fov", fov_spin.value)
	config.set_value("audio", "volume", volume_slider.value)
	config.set_value("display", "ui_scale", TestConfig.ui_scale)
	config.save(TestConfig.SETTINGS_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(TestConfig.SETTINGS_PATH) != OK:
		return
	dpi_spin.value = config.get_value("mouse", "dpi", dpi_spin.value)
	fov_spin.value = config.get_value("game", "fov", fov_spin.value)
	volume_slider.value = config.get_value("audio", "volume", volume_slider.value)
	var idx := UI_SCALE_OPTIONS.find(TestConfig.ui_scale)
	ui_scale_option.select(idx if idx >= 0 else 0)
