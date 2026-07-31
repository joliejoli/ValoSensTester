extends Control

@onready var dpi_spin: SpinBox = %DpiSpin
@onready var fov_spin: SpinBox = %FovSpin
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue

func _ready() -> void:
	load_settings()
	dpi_spin.value_changed.connect(_on_dpi_changed)
	fov_spin.value_changed.connect(_on_fov_changed)
	volume_slider.value_changed.connect(_on_volume_changed)
	apply_volume()

func _on_dpi_changed(_value: float) -> void:
	save_settings()

func _on_fov_changed(_value: float) -> void:
	save_settings()

func _on_volume_changed(_value: float) -> void:
	apply_volume()
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
	config.save(TestConfig.SETTINGS_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(TestConfig.SETTINGS_PATH) != OK:
		return
	dpi_spin.value = config.get_value("mouse", "dpi", dpi_spin.value)
	fov_spin.value = config.get_value("game", "fov", fov_spin.value)
	volume_slider.value = config.get_value("audio", "volume", volume_slider.value)
