extends Node

const SETTINGS_PATH := "user://settings.cfg"

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

var _settings: Dictionary = {}

func _ready() -> void:
	load_settings()

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

func get_dpi() -> int:
	return int(_settings.get("dpi", 800))

func get_fov() -> float:
	return float(_settings.get("fov", 103.0))
