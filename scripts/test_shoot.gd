extends Node3D

const SceneNav := preload("res://scripts/scene_nav.gd")
const TargetScene := preload("res://target.tscn")
const Sfx := preload("res://scripts/sfx.gd")

enum State { WARMUP, BANNER, ACTIVE, FINISHED }

@onready var camera: Camera3D = %Camera
@onready var target_root: Node3D = %TargetRoot
@onready var crosshair: Control = %Crosshair
@onready var round_label: Label = %RoundLabel
@onready var sens_label: Label = %SensLabel
@onready var timer_label: Label = %TimerLabel
@onready var stats_label: Label = %StatsLabel
@onready var banner_label: Label = %BannerLabel
@onready var warmup_label: Label = %WarmupLabel
@onready var pause_menu: Control = %PauseMenu
@onready var shot_player: AudioStreamPlayer = %ShotPlayer
@onready var hit_player: AudioStreamPlayer = %HitPlayer
@onready var miss_player: AudioStreamPlayer = %MissPlayer

var state := State.WARMUP
var paused := false

var current_sens := 40.0
var deg_per_pixel := 0.0

var round_index := 0
var targets_spawned := 0
var targets_done := 0
var warmup_done := 0
var shot_count := 0
var hit_count := 0
var round_start_ms := 0

var active_targets: Array[Node3D] = []
var round_data: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera.fov = _vertical_fov(TestConfig.get_fov())
	shot_player.stream = Sfx.shot()
	hit_player.stream = Sfx.hit()
	miss_player.stream = Sfx.miss()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_sens(TestConfig.get_round_sens(0))
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
		camera.rotate_y(deg_to_rad(-event.relative.x * deg_per_pixel))
		camera.rotate_x(deg_to_rad(-event.relative.y * deg_per_pixel))
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

func _process(_delta: float) -> void:
	if paused:
		return
	if state == State.ACTIVE:
		timer_label.text = "%.1fs" % ((Time.get_ticks_msec() - round_start_ms) / 1000.0)
		_update_overshoot_detection()

func _shoot() -> void:
	shot_player.play()
	if state == State.ACTIVE:
		shot_count += 1
		round_data["shot_timestamps"].append((Time.get_ticks_msec() - round_start_ms) / 1000.0)
	var ray := _cast_ray()
	if ray.is_empty():
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
	_on_miss()

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
	var t: Node3D = TargetScene.instantiate()
	target_root.add_child(t)
	var moving: bool = TestConfig.target_type == TestConfig.TargetType.MOVING \
		or TestConfig.test_mode == TestConfig.TestMode.TRACKING
	var speed := 0.0
	if moving:
		speed = 1.8 if TestConfig.test_mode == TestConfig.TestMode.TRACKING else 0.8
	var pos := Vector3(randf_range(-5.0, 5.0), randf_range(-2.2, 2.2), -TestConfig.TARGET_DISTANCE)
	var tries := 0
	while tries < 8:
		var overlap := false
		for existing in active_targets:
			if existing.global_position.distance_to(pos) < 2.0:
				overlap = true
				break
		if not overlap:
			break
		pos.x = randf_range(-5.0, 5.0)
		pos.y = randf_range(-2.2, 2.2)
		tries += 1
	t.setup(_target_radius(), pos, speed, Vector3.RIGHT if randi() % 2 == 0 else Vector3.LEFT)
	t.hit.connect(_on_target_hit)
	t.expired.connect(_on_target_expired)
	active_targets.append(t)
	targets_spawned += 1

func _spawn_round_targets() -> void:
	if TestConfig.test_mode == TestConfig.TestMode.PRESSURE:
		var remaining := TestConfig.TARGETS_PER_ROUND - targets_spawned
		for i in mini(3, remaining):
			_spawn_single_target()
	else:
		_spawn_single_target()

func _despawn_target(t: Node3D) -> void:
	active_targets.erase(t)
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
	var sa: Variant = t.get("shots_against")
	var fsm: Variant = t.get("first_shot_ms")
	if sa != null and int(sa) > 1 and fsm != null and int(fsm) >= 0:
		round_data["correction_time"] = (now_ms - int(fsm)) / 1000.0
	targets_done += 1
	_update_stats_ui()
	_advance_round()

func _on_target_expired(t: Node3D) -> void:
	_despawn_target(t)
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
	current_sens = TestConfig.get_round_sens(round_index)
	_apply_sens(current_sens)
	round_data = {
		"round": round_index + 1,
		"sens": current_sens,
		"shots": 0,
		"hits": 0,
		"overshoots": 0,
		"first_hit_time": 0.0,
		"correction_time": 0.0,
		"total_time_ms": 0,
		"shot_timestamps": [],
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
	round_data["total_time_ms"] = Time.get_ticks_msec() - round_start_ms
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
	SceneNav.go("res://test_result.tscn", self)

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

func _update_overshoot_detection() -> void:
	var aimed_target: Node3D = null
	var ray := _cast_ray()
	if not ray.is_empty():
		var col: Object = ray["collider"]
		if col is Area3D:
			var p: Node = col.get_parent()
			if p is Node3D and p.get("alive") == true:
				aimed_target = p
	for t in active_targets:
		var aimed := t == aimed_target
		if aimed and not t.was_aimed:
			round_data["overshoots"] = int(round_data.get("overshoots", 0)) + 1
		t.was_aimed = aimed

func _target_radius() -> float:
	match TestConfig.target_size:
		TestConfig.TargetSize.SMALL:
			return 0.14
		TestConfig.TargetSize.LARGE:
			return 0.56
		_:
			return 0.28

func _vertical_fov(horizontal_fov: float) -> float:
	var rect := get_viewport().get_visible_rect().size
	var aspect := rect.x / maxf(rect.y, 1.0)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_fov) * 0.5) / aspect))

func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	pause_menu.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED

func _on_resume_button_pressed() -> void:
	_toggle_pause()

func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SceneNav.go("res://main.tscn", self)
