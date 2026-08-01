extends Node3D

const SceneNav := preload("res://scripts/scene_nav.gd")
const TargetScene := preload("res://target.tscn")
const Sfx := preload("res://scripts/sfx.gd")
const TestPlan := preload("res://scripts/test_plan.gd")

enum State { WARMUP, BANNER, ACTIVE, FINISHED }

# 轨迹微调/空枪归属参数（附录 D P2：魔法数字提为常量）
const AIM_ENTER_ANGLE := deg_to_rad(12.0)
const AIM_TRACK_ANGLE := deg_to_rad(25.0)
const AIM_MOTION_DEAD_ZONE := deg_to_rad(0.05)
const MISS_ASSIGN_ANGLE := deg_to_rad(15.0)
const MISS_ASSIGN_ANGLE_PRESSURE := deg_to_rad(8.0)

@onready var camera: Camera3D = %Camera
@onready var target_root: Node3D = %TargetRoot
@onready var crosshair: Control = %Crosshair
@onready var round_label: Label = %RoundLabel
@onready var sens_label: Label = %SensLabel
@onready var timer_label: Label = %TimerLabel
@onready var stats_label: Label = %StatsLabel
@onready var banner_label: Label = %BannerLabel
@onready var warmup_label: Label = %WarmupLabel
@onready var facing_hint: Label = %FacingHint
@onready var pause_menu: Control = %PauseMenu
@onready var shot_player: AudioStreamPlayer = %ShotPlayer
@onready var hit_player: AudioStreamPlayer = %HitPlayer
@onready var miss_player: AudioStreamPlayer = %MissPlayer

var state := State.WARMUP
var paused := false

var current_sens := 40.0
var deg_per_pixel := 0.0

# FPS 相机：yaw 绕世界 Y 累积、pitch 绕局部 X 累积（标准做法，避免局部轴旋转的横滚漂移）
var _yaw := 0.0
var _pitch := 0.0

var round_index := 0
var targets_spawned := 0
var targets_done := 0
var warmup_done := 0
var shot_count := 0
var hit_count := 0
var round_start_ms := 0
var _last_yaw := 0.0
var _last_pitch := 0.0

var active_targets: Array[Node3D] = []
var round_data: Dictionary = {}
var test_plan := TestPlan.new()
# 目标对象池（Phase 7 性能：复用节点减少 instantiate/free）
var _target_pool: Array[Node3D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera.fov = _vertical_fov(TestConfig.get_fov())
	# YXZ 顺序：先绕世界 Y 偏航，再绕局部 X 俯仰（FPS 标准）
	# YXZ 顺序（先绕世界 Y 偏航，再绕局部 X 俯仰，FPS 标准；枚举值 2 = YXZ）
	camera.rotation_order = 2
	shot_player.stream = Sfx.shot()
	hit_player.stream = Sfx.hit()
	miss_player.stream = Sfx.miss()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	test_plan.begin(
		TestConfig.test_type == TestConfig.TestType.CONSISTENCY,
		TestConfig.sens_min,
		TestConfig.sens_max,
		TestConfig.rounds,
	)
	_apply_sens(test_plan.next_sens(0))
	warmup_label.text = "热身阶段（数据不计入成绩）"
	banner_label.visible = false
	_spawn_single_target()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_toggle_pause()
		return
	if paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_shoot()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_mouse_motion(event.relative)

# FPS 相机旋转：yaw 绕世界 Y（YXZ 顺序）累积，pitch 绕局部 X 累积并 clamp，全量赋值防漂移
func _apply_mouse_motion(relative: Vector2) -> void:
	_yaw += deg_to_rad(-relative.x * deg_per_pixel)
	_pitch = clampf(_pitch + deg_to_rad(-relative.y * deg_per_pixel), deg_to_rad(-89.0), deg_to_rad(89.0))
	camera.rotation = Vector3(_pitch, _yaw, 0.0)

func _process(_delta: float) -> void:
	if paused:
		return
	# 朝向提示由朝向状态统一驱动（回正自动隐藏）
	facing_hint.visible = not _facing_forward() and (state == State.WARMUP or state == State.ACTIVE)
	if state == State.ACTIVE:
		timer_label.text = "%.1fs" % ((Time.get_ticks_msec() - round_start_ms) / 1000.0)
		# 面向回正后自动补生成（转身暂停生成时的重试）
		if active_targets.is_empty() and targets_done < TestConfig.TARGETS_PER_ROUND:
			_spawn_round_targets()
	if state == State.WARMUP or state == State.ACTIVE:
		_update_micro_adjust_detection()
		_update_track_time(get_process_delta_time())

# 跟枪精度（附录 D P2）：每帧对移动靶累计"准星在命中区内"的停留时间，
# 命中时按 停留/存活 比例计入轮数据（追踪/移动靶模式的独立评估维度）
func _update_track_time(delta: float) -> void:
	for t in active_targets:
		if float(t.get("move_speed")) <= 0.0:
			continue
		var ang := _angle_to_target(t)
		var hit_angle := atan(float(t.get("radius")) / TestConfig.TARGET_DISTANCE)
		if ang < hit_angle:
			t.track_time += delta

# 轨迹级微调检测（手测反馈：不开火玩家无空枪数据，微调指标失真）：
# 跟踪准星方向的每帧变化符号，对最近目标靶累计"方向反转"次数（来回摆动），与是否开火无关
func _update_micro_adjust_detection() -> void:
	var yaw_delta := _yaw - _last_yaw
	var pitch_delta := _pitch - _last_pitch
	_last_yaw = _yaw
	_last_pitch = _pitch
	# 死区：小于 0.05°/帧视为静止，排除像素级抖动
	if absf(yaw_delta) < AIM_MOTION_DEAD_ZONE and absf(pitch_delta) < AIM_MOTION_DEAD_ZONE:
		return
	var yaw_sign := signf(yaw_delta)
	var pitch_sign := signf(pitch_delta)
	var closest: Node3D = null
	var best := AIM_TRACK_ANGLE
	for t in active_targets:
		# 移动靶/追踪：追枪反转是跟随修正不是定位微调（附录 D P1-1），不计入
		if float(t.get("move_speed")) > 0.0:
			continue
		var ang := _angle_to_target(t)
		if ang < best:
			best = ang
			closest = t
	if closest == null:
		return
	var entered := best < AIM_ENTER_ANGLE
	var rev := 0
	if entered:
		# 首次进入瞄准区只记录方向，不计数（附录 D P0-2：初始符号 0 会误计 1 次）
		if closest._aim_entered:
			if int(yaw_sign) != 0 and int(yaw_sign) != int(closest._aim_yaw_sign):
				rev += 1
			if int(pitch_sign) != 0 and int(pitch_sign) != int(closest._aim_pitch_sign):
				rev += 1
		else:
			closest._aim_entered = true
		closest._aim_yaw_sign = yaw_sign
		closest._aim_pitch_sign = pitch_sign
	closest.micro_adjusts += rev

func _angle_to_target(t: Node3D) -> float:
	var forward := -camera.global_transform.basis.z
	var dir := (t.global_position - camera.global_position).normalized()
	return acos(clampf(dir.dot(forward), -1.0, 1.0))

func _shoot() -> void:
	shot_player.play()
	if state == State.ACTIVE:
		shot_count += 1
		round_data["shot_timestamps"].append((Time.get_ticks_msec() - round_start_ms) / 1000.0)
	var ray := _cast_ray()
	if ray.is_empty():
		_record_miss_shot(Time.get_ticks_msec())
		_on_miss()
		return
	var col: Object = ray["collider"]
	if col is Area3D:
		var t: Node = col.get_parent()
		if t.has_method("mark_shot"):
			t.mark_shot(Time.get_ticks_msec())
			t.register_hit()
			hit_player.play()
			crosshair.flash()
			return
	_record_miss_shot(Time.get_ticks_msec())
	_on_miss()

# 打空枪：归属到准星方向最近的活动靶，
# 使 first_shot_ms/微调耗时数据真实（否则 first_shot_ms=命中时刻，修正恒为 0）
# 多目标（PRESSURE）时归属不可靠，阈值收紧（附录 D P1-4）
func _record_miss_shot(now_ms: int) -> void:
	var forward := -camera.global_transform.basis.z
	var best_ang := MISS_ASSIGN_ANGLE_PRESSURE if TestConfig.test_mode == TestConfig.TestMode.PRESSURE else MISS_ASSIGN_ANGLE
	var best_target: Node3D = null
	for t in active_targets:
		var dir := (t.global_position - camera.global_position).normalized()
		var ang := acos(clampf(dir.dot(forward), -1.0, 1.0))
		if ang < best_ang:
			best_ang = ang
			best_target = t
	if best_target != null:
		best_target.mark_shot(now_ms)

func _on_miss() -> void:
	miss_player.play()

func _cast_ray() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 100.0
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 1
	return space.intersect_ray(params)

func _spawn_single_target() -> void:
	# 面向容差：转身时暂停生成，避免靶子在背后超时（提示由 _process 统一驱动）
	if not _facing_forward():
		return
	var t: Node3D
	if _target_pool.is_empty():
		t = TargetScene.instantiate()
		target_root.add_child(t)
		t.hit.connect(_on_target_hit)
		t.expired.connect(_on_target_expired)
	else:
		t = _target_pool.pop_back()
		target_root.add_child(t)
		t.reset_for_pool()
	var moving: bool = TestConfig.target_type == TestConfig.TargetType.MOVING \
		or TestConfig.test_mode == TestConfig.TestMode.TRACKING
	var speed := 0.0
	if moving:
		speed = TestConfig.TRACK_SPEED_OPTIONS[TestConfig.track_speed_index] \
			if TestConfig.test_mode == TestConfig.TestMode.TRACKING else 0.8
	# 追踪模式：正弦摆动跟枪（Phase 6），非追踪保持直线移动
	var track_sine: bool = TestConfig.test_mode == TestConfig.TestMode.TRACKING
	var pos := _spawn_position()
	var tries := 0
	while tries < 8:
		var overlap := false
		for existing in active_targets:
			if existing.global_position.distance_to(pos) < 2.0:
				overlap = true
				break
		if not overlap:
			break
		pos = _spawn_position()
		tries += 1
	# 命中角距 θ = spawn 时相对相机朝向的角距（附录 D P0-1：
	# 世界 -Z 角在玩家 yaw 漂移时失真，speed 归一化分母轮间不公平）
	var forward := -camera.global_transform.basis.z
	var angle := acos(clampf((pos - camera.global_position).normalized().dot(forward), -1.0, 1.0))
	t.setup(_target_radius(), pos, speed, Vector3.RIGHT if randi() % 2 == 0 else Vector3.LEFT, angle)
	t.track_sine = track_sine
	active_targets.append(t)
	targets_spawned += 1

# 靶子固定在世界正前方扇形（手测反馈：不做 360° 方向随机，
# 参照 VALORANT 靶场机器人固定方向，避免转身找靶分散注意力与引入无关转身变量）
# 水平 ±30° / 垂直 ±15°；长距 18-30°（0.10 sens 时 3s 内物理可达，取消 sens_min 联动）
# Flick 模式（Phase 6）：全部长距靶（18-30° 扇形边缘），专测快速拉枪
func _spawn_position() -> Vector3:
	var cam_pos := camera.global_position
	var yaw_off := 0.0
	var pitch_off := 0.0
	var flick: bool = TestConfig.test_mode == TestConfig.TestMode.FLICK
	if flick or randf() < 0.35:
		# 长距/Flick：18-30° 环形，pitch 不 clamp（≤30° 仍在垂直半 FOV 33° 内，避免截断总角距）
		var dist := deg_to_rad(randf_range(18.0, 30.0))
		var angle := randf() * TAU
		yaw_off = clampf(rad_to_deg(sin(angle) * dist), -30.0, 30.0)
		pitch_off = rad_to_deg(cos(angle) * dist)
	else:
		# 短距 6-14° 环形
		var dist := deg_to_rad(randf_range(6.0, 14.0))
		var angle := randf() * TAU
		yaw_off = rad_to_deg(sin(angle) * dist)
		pitch_off = rad_to_deg(cos(angle) * dist)
		yaw_off = clampf(yaw_off, -30.0, 30.0)
		pitch_off = clampf(pitch_off, -15.0, 15.0)
	var moving: bool = TestConfig.target_type == TestConfig.TargetType.MOVING \
		or TestConfig.test_mode == TestConfig.TestMode.TRACKING
	if moving:
		yaw_off = clampf(yaw_off, -15.0, 15.0)
	var rel := Vector3(
		tan(deg_to_rad(yaw_off)),
		tan(deg_to_rad(pitch_off)),
		-1.0,
	) * TestConfig.TARGET_DISTANCE
	# 世界固定方向（不旋转到相机朝向）：玩家保持面向正前方扇形
	return cam_pos + rel

# 朝向容差：玩家严重转身时不生成靶子并提示回正（避免转身超时被误判为灵敏度差）
func _facing_forward() -> bool:
	return absf(_yaw) < deg_to_rad(55.0) and absf(_pitch) < deg_to_rad(35.0)

func _spawn_round_targets() -> void:
	if TestConfig.test_mode == TestConfig.TestMode.PRESSURE:
		var remaining := TestConfig.TARGETS_PER_ROUND - targets_spawned
		for i in mini(TestConfig.PRESSURE_TARGETS, remaining):
			_spawn_single_target()
	else:
		_spawn_single_target()

func _despawn_target(t: Node3D) -> void:
	active_targets.erase(t)
	# 回收对象池（保留节点复用）；池上限 8 个，超出释放
	if _target_pool.size() < 8:
		target_root.remove_child(t)
		t.reset_for_pool()
		_target_pool.append(t)
	else:
		t.queue_free()

func _on_target_hit(t: Node3D) -> void:
	_despawn_target(t)
	if state == State.WARMUP:
		_advance_warmup()
		return
	if state != State.ACTIVE:
		return
	hit_count += 1
	var now_ms := Time.get_ticks_msec()
	var dt := (now_ms - round_start_ms) / 1000.0
	if round_data.get("first_hit_time", 0.0) <= 0.0:
		round_data["first_hit_time"] = dt
	round_data["hit_times"].append((now_ms - int(t.spawn_ms)) / 1000.0)
	round_data["hit_angles"].append(float(t.angle_rad))
	# 命中时刻（相对轮开始，切换效率数据源；Phase 6）
	round_data["hit_timestamps"].append(dt)
	# 越靶统计（复审 P0-5）：命中前多余开火数（含打空枪归属），无伪信号
	round_data["overshoots"] = int(round_data.get("overshoots", 0)) + int(t.shots_against) - 1
	# 一次性定位率：一枪命中的靶数
	if int(t.shots_against) <= 1:
		round_data["first_shot_hits"] = int(round_data.get("first_shot_hits", 0)) + 1
	# 轨迹级微调（准星方向反转，与开火无关）
	round_data["micro_adjusts"] = int(round_data.get("micro_adjusts", 0)) + int(t.micro_adjusts)
	# 跟枪精度（移动靶）：准星停留/存活比例
	if float(t.move_speed) > 0.0:
		var lifetime := float(t.lifetime)
		if lifetime > 0.1:
			round_data["track_scores"].append(clampf(float(t.track_time) / lifetime, 0.0, 1.0))
	var fsm: Variant = t.get("first_shot_ms")
	if fsm != null and int(fsm) >= 0:
		# 修正时间：该靶首次开火 → 命中的耗时（复审 P1-3，数组化避免只存最后一靶）
		round_data["correction_times"].append((now_ms - int(fsm)) / 1000.0)
	targets_done += 1
	_update_stats_ui()
	_advance_round()

func _on_target_expired(t: Node3D) -> void:
	_despawn_target(t)
	# 记录超时靶角度（一致性灵敏度方向分析数据源；Phase 6 补充）
	if state == State.ACTIVE:
		round_data["expired_angles"].append(float(t.angle_rad))
	if state == State.WARMUP:
		_advance_warmup()
	elif state == State.ACTIVE:
		targets_done += 1
		_update_stats_ui()
		_advance_round()

func _advance_warmup() -> void:
	warmup_done += 1
	warmup_label.text = "热身 %d/%d" % [warmup_done, TestConfig.WARMUP_TARGETS]
	if warmup_done >= TestConfig.WARMUP_TARGETS:
		_finish_warmup()
	else:
		_spawn_single_target()

func _finish_warmup() -> void:
	state = State.BANNER
	warmup_label.visible = false
	_show_banner("热身完成，正式测试开始")
	await _banner_wait()
	if state == State.BANNER and not paused:
		_begin_test()

func _advance_round() -> void:
	if targets_done >= TestConfig.TARGETS_PER_ROUND:
		_end_round()
	else:
		_spawn_round_targets()

func _begin_test() -> void:
	state = State.ACTIVE
	round_index = 0
	_start_round()

func _start_round() -> void:
	state = State.ACTIVE
	current_sens = test_plan.next_sens(round_index)
	_apply_sens(current_sens)
	round_data = {
		"round": round_index + 1,
		"sens": current_sens,
		"shots": 0,
		"hits": 0,
		"overshoots": 0,
		"first_shot_hits": 0,
		"micro_adjusts": 0,
		"track_scores": [],
		"first_hit_time": 0.0,
		"total_time_ms": 0,
		"shot_timestamps": [],
		"hit_times": [],
		"hit_angles": [],
		"hit_timestamps": [],
		"expired_angles": [],
		"correction_times": [],
	}
	shot_count = 0
	hit_count = 0
	targets_spawned = 0
	targets_done = 0
	round_start_ms = Time.get_ticks_msec()
	_update_hud()
	_show_banner("第 %d/%d 轮" % [round_index + 1, TestConfig.rounds])
	_spawn_round_targets()

func _end_round() -> void:
	state = State.BANNER
	round_data["hits"] = hit_count
	round_data["shots"] = shot_count
	round_data["targets_done"] = targets_done
	round_data["total_time_ms"] = Time.get_ticks_msec() - round_start_ms
	test_plan.add_result(round_data)
	TestConfig.round_results.append(round_data)
	round_index += 1
	if round_index >= TestConfig.rounds:
		_finish_test()
		return
	_show_banner("准备第 %d/%d 轮" % [round_index + 1, TestConfig.rounds])
	await _banner_wait()
	if state == State.BANNER and not paused:
		_start_round()

func _finish_test() -> void:
	state = State.FINISHED
	TestConfig.current_sens = current_sens
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TestConfig.opt_summary = _build_opt_summary()
	SceneNav.go("res://test_result.tscn", self)

# 构建优化摘要（结果页 Phase 4 基础版展示；Phase 5 完整可视化）
func _build_opt_summary() -> Dictionary:
	if TestConfig.test_type == TestConfig.TestType.CONSISTENCY:
		var sens := current_sens
		return {
			"best_sens": sens,
			"score_mean": 0.0,
			"score_low": 0.0,
			"score_high": 0.0,
			"mode_label": "一致性测试（固定灵敏度）",
			"dpi": TestConfig.get_dpi(),
			"edpi": sens * TestConfig.get_dpi(),
			"samples": TestConfig.round_results.size(),
			"is_consistency": true,
		}
	var est: Dictionary = test_plan.best_estimate()
	var sens := float(est["sens"])
	var mean := float(est["mean"])
	var var_sq := maxf(float(est["variance"]), 0.0)
	# 得分 CI clamp 到合法区间（复审 P1-1）
	var low := clampf(mean - 1.96 * sqrt(var_sq), 0.0, 1.0)
	var high := clampf(mean + 1.96 * sqrt(var_sq), 0.0, 1.0)
	return {
		"best_sens": snappedf(sens, 0.01),
		"score_mean": mean,
		"score_low": low,
		"score_high": high,
		"flat": est.get("flat", false),
		"mode_label": _mode_label(sens),
		"dpi": TestConfig.get_dpi(),
		"edpi": snappedf(sens * TestConfig.get_dpi(), 1.0),
		"samples": TestConfig.round_results.size(),
		"is_consistency": false,
	}

# 灵敏度倾向标签（Phase 4.5 软化：不再断言手腕/手臂发力方式，
# 发力习惯因人而异，结果页注明基于本次测试任务）
func _mode_label(sens: float) -> String:
	if sens < 0.30:
		return "本测试中表现偏向低灵敏度 · 建议在 %.2f±0.05 范围内微调" % sens
	if sens > 0.60:
		return "本测试中表现偏向高灵敏度 · 建议在 %.2f±0.05 范围内微调" % sens
	return "本测试中表现偏向中灵敏度 · 建议在 %.2f±0.05 范围内微调" % sens

func _banner_wait() -> void:
	await get_tree().create_timer(1.8).timeout

func _show_banner(text: String) -> void:
	banner_label.text = text
	banner_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func() -> void: banner_label.visible = false)

func _apply_sens(sens: float) -> void:
	current_sens = sens
	# VALORANT yaw = 0.07°/count，每 count 鼠标移动旋转 0.07 × 灵敏度 度
	deg_per_pixel = 0.07 * sens
	sens_label.text = "灵敏度 %.2f" % sens

func _update_hud() -> void:
	round_label.text = "第 %d/%d 轮" % [round_index + 1, TestConfig.rounds]
	stats_label.text = "命中 0/0"

func _update_stats_ui() -> void:
	stats_label.text = "命中 %d/%d" % [hit_count, shot_count]

func _target_radius() -> float:
	# Phase 4.5 缩小一档：小 0.12m(1.7°) / 中 0.20m(2.9°) / 大 0.40m(5.7°)，提高命中率区分度
	match TestConfig.target_size:
		TestConfig.TargetSize.SMALL:
			return 0.12
		TestConfig.TargetSize.LARGE:
			return 0.40
		_:
			return 0.20

func _vertical_fov(horizontal_fov: float) -> float:
	var rect := get_viewport().get_visible_rect().size
	var aspect := rect.x / maxf(rect.y, 1.0)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_fov) * 0.5) / aspect))

func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	pause_menu.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if paused:
		match state:
			State.WARMUP:
				%PauseStateLabel.text = "热身阶段"
			State.BANNER:
				%PauseStateLabel.text = "轮次准备中（即将开始）"
			State.ACTIVE:
				%PauseStateLabel.text = "第 %d/%d 轮进行中" % [round_index + 1, TestConfig.rounds]
			_:
				%PauseStateLabel.text = ""

func _on_resume_button_pressed() -> void:
	_toggle_pause()

func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SceneNav.go("res://main.tscn", self)
