extends Node

const SETTINGS_PATH := "user://settings.cfg"

const BASE_UI_WIDTH := 1280
const BASE_UI_HEIGHT := 720

# 测试场景常量（Phase 3/4）
# 每轮靶数：信度评估结论（8 靶噪声 SD 0.083 > 信号，提到 12 靶）
# 目标存活时间：Phase 4.5 从 6s 缩短到 3s，恢复时间压力（超时=未命中，防止慢慢瞄虚高命中率）
const TARGETS_PER_ROUND := 12
const WARMUP_TARGETS := 5
const TARGET_MAX_LIFETIME := 3.0
const TARGET_DISTANCE := 8.0

enum TestType { PSA_BINARY, CONSISTENCY }
enum TargetType { STATIC, MOVING }
enum TargetSize { SMALL, MEDIUM, LARGE }
enum TestMode { STANDARD, PRESSURE, TRACKING, FLICK }

# 压力模式同时目标数（Phase 6：3-5 范围取 4）
const PRESSURE_TARGETS := 4
# 追踪速度档位（m/s）
const TRACK_SPEED_OPTIONS := [0.8, 1.8, 2.6]

# 灵敏度使用无畏契约游戏内灵敏度值（如 0.35），非 cm/360°
# VALORANT yaw = 0.07°/count，每 count 旋转 = 0.07 × 灵敏度 度
# 参考换算（800 DPI）：0.35 ≈ 46.6 cm/360，0.10 ≈ 163 cm/360，0.90 ≈ 18 cm/360
var test_type: int = TestType.PSA_BINARY
var sens_min: float = 0.10
var sens_max: float = 0.90
# PSA 默认 10 轮（粗扫 4 + BO 细化 6），Consistency 建议 3-5 轮
var rounds: int = 10
var target_type: int = TargetType.STATIC
var target_size: int = TargetSize.MEDIUM
var test_mode: int = TestMode.STANDARD
var track_speed_index: int = 1  # TRACK_SPEED_OPTIONS 下标（追踪模式速度档位）

# 测试执行状态（Phase 3 使用）
var current_round: int = 0
var current_sens: float = 0.0
var round_results: Array = []

# 优化摘要（Phase 4）：best_sens / score_mean / score_low / score_high / mode_label / dpi / edpi / samples
var opt_summary: Dictionary = {}

var ui_scale: float = 0.0  # 0 = 自动适配窗口，否则为固定缩放因子
var display_mode: int = 0  # 0=窗口化 1=全屏 2=无边框全屏
var crosshair_style: int = 1  # 0=标准十字 1=紧凑十字 2=圆点

var _settings: Dictionary = {}

func _ready() -> void:
	load_settings()
	_apply_native_icon()
	get_tree().root.size_changed.connect(_on_window_size_changed)

# 任务栏与窗口左上角图标：运行时显式应用 32px 简化版靶子图
# （config/icon 的 ico 无法被 Image 加载→Godot 默认图标；512px 大图缩放小图标
# 会糊。32px 源图经 OS 缩到 16px 仍清晰，窗口标题栏 32px 直接用原尺寸）
func _apply_native_icon() -> void:
	if DisplayServer.get_name() != "windows":
		return
	var img := Image.load_from_file("res://icon_small.png")
	if img == null:
		return
	DisplayServer.set_icon(img)
	get_window().icon = ImageTexture.create_from_image(img)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		toggle_fullscreen()

func reset() -> void:
	test_type = TestType.PSA_BINARY
	sens_min = 0.10
	sens_max = 0.90
	rounds = 10
	target_type = TargetType.STATIC
	target_size = TargetSize.MEDIUM
	test_mode = TestMode.STANDARD
	current_round = 0
	current_sens = 0.0
	round_results.clear()
	opt_summary.clear()
	track_speed_index = 1

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_settings["dpi"] = config.get_value("mouse", "dpi", 800)
	_settings["fov"] = config.get_value("game", "fov", 103.0)
	_settings["volume"] = config.get_value("audio", "volume", 100.0)
	ui_scale = config.get_value("display", "ui_scale", 0.0)
	display_mode = config.get_value("display", "mode", 0)
	crosshair_style = config.get_value("display", "crosshair_style", 1)
	apply_display_mode()
	apply_ui_scale()

func get_dpi() -> int:
	return int(_settings.get("dpi", 800))

func get_fov() -> float:
	return float(_settings.get("fov", 103.0))

func apply_ui_scale() -> void:
	var win := get_window()
	# canvas_items stretch 模式下禁止手动设置 content_scale_factor：与引擎缩放
	# 系统冲突会导致部分锚点布局不再更新（用户 4K 双屏 150% 缩放下标题栏宽度
	# 变 0、标题左移出屏被裁）。改用 content_scale_size（stretch 基尺寸）实现
	# UI 缩放：100%/自动 = 项目基尺寸 1280×720；125% = 1024×576（内容放大 1.25）
	var base_w := BASE_UI_WIDTH
	var base_h := BASE_UI_HEIGHT
	if ui_scale > 0.0 and ui_scale < 1.0:
		base_w = roundi(BASE_UI_WIDTH / ui_scale)
		base_h = roundi(BASE_UI_HEIGHT / ui_scale)
	win.content_scale_size = Vector2i(base_w, base_h)

func _on_window_size_changed() -> void:
	if ui_scale <= 0.0:
		apply_ui_scale()

func apply_display_mode() -> void:
	var win := get_window()
	win.borderless = display_mode == 2
	if display_mode == 0:
		win.mode = Window.MODE_WINDOWED
	else:
		win.mode = Window.MODE_FULLSCREEN

func toggle_fullscreen() -> void:
	var win := get_window()
	if win.mode == Window.MODE_WINDOWED:
		win.borderless = false
		win.mode = Window.MODE_FULLSCREEN
	else:
		win.borderless = false
		win.mode = Window.MODE_WINDOWED
