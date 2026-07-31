extends Node

const SETTINGS_PATH := "user://settings.cfg"

const BASE_UI_WIDTH := 1280.0
const BASE_UI_HEIGHT := 720.0
const MIN_UI_SCALE := 0.5

enum TestType { PSA_BINARY, CONSISTENCY }
enum TargetType { STATIC, MOVING }
enum TargetSize { SMALL, MEDIUM, LARGE }
enum TestMode { STANDARD, PRESSURE, TRACKING }

var test_type: int = TestType.PSA_BINARY
var sens_min: float = 20.0
var sens_max: float = 80.0
var rounds: int = 3
var target_type: int = TargetType.STATIC
var target_size: int = TargetSize.MEDIUM
var test_mode: int = TestMode.STANDARD

# 测试执行状态（Phase 3 使用）
var current_round: int = 0
var current_sens: float = 0.0
var round_results: Array = []

var ui_scale: float = 0.0  # 0 = 自动适配窗口，否则为固定缩放因子

var _settings: Dictionary = {}

func _ready() -> void:
	load_settings()
	get_tree().root.size_changed.connect(_on_window_size_changed)

func reset() -> void:
	test_type = TestType.PSA_BINARY
	sens_min = 20.0
	sens_max = 80.0
	rounds = 3
	target_type = TargetType.STATIC
	target_size = TargetSize.MEDIUM
	test_mode = TestMode.STANDARD
	current_round = 0
	current_sens = 0.0
	round_results.clear()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_settings["dpi"] = config.get_value("mouse", "dpi", 800)
	_settings["fov"] = config.get_value("game", "fov", 103.0)
	_settings["volume"] = config.get_value("audio", "volume", 100.0)
	ui_scale = config.get_value("display", "ui_scale", 0.0)
	apply_ui_scale()

func get_dpi() -> int:
	return int(_settings.get("dpi", 800))

func get_fov() -> float:
	return float(_settings.get("fov", 103.0))

func apply_ui_scale() -> void:
	var win := get_window()
	if ui_scale > 0.0:
		win.content_scale_factor = ui_scale
		return
	var auto: float = min(win.size.x / BASE_UI_WIDTH, win.size.y / BASE_UI_HEIGHT)
	win.content_scale_factor = max(auto, MIN_UI_SCALE)

func _on_window_size_changed() -> void:
	if ui_scale <= 0.0:
		apply_ui_scale()
