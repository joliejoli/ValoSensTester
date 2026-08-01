extends SceneTree

# 常驻回归测试（Phase 7）：聚合历次 headless 验证用例
# 运行：godot --headless --path "." --script res://tests/run_tests.gd
# 覆盖：目标函数 / BO 收敛 / GP 方差 / 指标聚合 / 历史存储 / 图表几何 / 微调检测 / 场景实例化 / 完整流程

const Objective := preload("res://scripts/test_objective.gd")
const BayesOpt := preload("res://scripts/bayes_opt.gd")
const TestPlan := preload("res://scripts/test_plan.gd")
const TestMetrics := preload("res://scripts/test_metrics.gd")
const HistoryStore := preload("res://scripts/history_store.gd")
const Chart := preload("res://scripts/chart.gd")
const Advice := preload("res://scripts/advice.gd")

const TEST_HISTORY_PATH := "user://run_tests_history.json"

var failures := 0
var pass_count := 0

func _init() -> void:
	await process_frame
	_test_objective()
	_test_bo_convergence()
	_test_gp_variance()
	_test_metrics()
	_test_sens_direction()
	_test_history_store()
	_test_chart()
	await 	_test_micro_detect()
	await _test_long_quota()
	await _test_blind_sens()
	await _test_scenes()
	await _test_flat_detection()
	print("通过 %d 项，失败 %d 项" % [pass_count, failures])
	quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		pass_count += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

# ---------- 目标函数 ----------

func _test_objective() -> void:
	var all_hit := {"shots": 12, "hits": 12, "targets_done": 12, "hit_times": [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6], "hit_angles": [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3], "overshoots": 0, "sens": 0.35}
	var s1 := Objective.score(all_hit)
	# eff = 0.6×0.35/0.3 = 0.7 → speed = 0.588 → score = 0.5+0.176+0.2 = 0.876
	_check("全中得分合理", absf(s1 - 0.876) < 0.01, "=%f" % s1)
	var all_miss := {"shots": 0, "hits": 0, "targets_done": 12, "hit_times": [], "overshoots": 0, "sens": 0.35}
	_check("全空兜底 0.25", absf(Objective.score(all_miss) - 0.25) < 1e-9)
	var outlier := all_hit.duplicate(true)
	outlier["hit_times"] = [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 10.0]
	_check("MAD 免疫离群值", absf(Objective.score(outlier) - s1) < 1e-9)
	var overshoot := all_hit.duplicate(true)
	overshoot["overshoots"] = 12
	_check("越靶惩罚生效", Objective.score(overshoot) < s1)
	var near := {"sens": 0.35, "hit_times": [0.2], "hit_angles": [deg_to_rad(8.0)]}
	var far := {"sens": 0.35, "hit_times": [1.15], "hit_angles": [deg_to_rad(46.0)]}
	_check("θ 归一化等效效率同分", absf(Objective.speed_score(near) - Objective.speed_score(far)) < 0.01)

# ---------- BO 收敛 ----------

func _test_bo_convergence() -> void:
	var plan := TestPlan.new()
	plan.begin(false, 0.1, 0.9, 10)
	var xs := [0.26, 0.42, 0.58, 0.74]
	xs.shuffle()
	for x in xs:
		plan.add_result(_make_round(x, 10))
	var bo_round := 0
	while plan._bo.sample_count() < 10:
		var sens := plan.next_sens(4 + bo_round)
		bo_round += 1
		plan.add_result(_make_round(sens, 10))
	var est := plan.best_estimate()
	_check("BO 收敛到峰值 0.45 ±0.08", absf(float(est["sens"]) - 0.45) <= 0.08, "sens=%f" % float(est["sens"]))

func _make_round(x: float, hits: int) -> Dictionary:
	# 峰值在 0.45：命中数随灵敏度变化
	var peak := int(round(11.0 * exp(-pow((x - 0.45) / 0.18, 2.0))))
	var times: Array = []
	for i in 12:
		times.append(0.6)
	return {"sens": x, "targets_done": 12, "hits": peak, "overshoots": 0,
		"hit_times": times, "hit_angles": [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
		"correction_times": [], "shots": peak, "shot_timestamps": []}

# ---------- GP 方差 ----------

func _test_gp_variance() -> void:
	var bo := BayesOpt.new()
	bo.add_sample(0.2, 0.70)
	bo.add_sample(0.3, 0.72)
	bo.add_sample(0.4, 0.75)
	bo.add_sample(0.5, 0.74)
	var p := bo.predict(0.45)
	_check("低方差数据 GP 方差收缩 <0.1", p["variance"] < 0.1, "=%f" % p["variance"])
	_check("GP 预测在数据区间", p["mean"] > 0.6 and p["mean"] < 0.85)
	_check("σ_n 校准为 0.08（附录 E P0）", absf(bo.noise_variance - 0.0064) < 1e-9, "=%f" % bo.noise_variance)

# ---------- 指标聚合 ----------

func _test_metrics() -> void:
	var rounds := [
		{"targets_done": 12, "hits": 10, "overshoots": 3, "first_shot_hits": 6, "micro_adjusts": 20,
			"hit_times": [0.5, 0.6, 0.7], "hit_angles": [0.2, 0.3, 0.4], "correction_times": [0.0, 0.3],
			"hit_timestamps": [1.0, 2.0, 3.0, 4.0, 5.0], "sens": 0.35, "shots": 11, "shot_timestamps": [],
			"track_scores": [0.7, 0.8]},
	]
	var m := TestMetrics.aggregate(rounds)
	_check("命中率 10/12", absf(m.accuracy - 10.0 / 12.0) < 1e-9)
	_check("一次定位率 6/12", absf(m.first_shot_rate - 0.5) < 1e-9)
	_check("修正过滤 0 → 0.3", absf(m.median_correct - 0.3) < 1e-9)
	_check("归一化耗时 median([0.875,0.7,0.6125])=0.7", absf(m.median_eff - 0.7) < 1e-9)
	_check("跟枪精度平均 0.75", absf(m.track_accuracy - 0.75) < 1e-9)
	_check("切换间隔 median([1,1,1,1])=1.0", absf(m.switch_secs - 1.0) < 1e-9)
	_check("每靶微调 20/12=1.67", absf(float(m.micro_adjusts) / 12.0 - 20.0 / 12.0) < 1e-9)

# ---------- 灵敏度方向建议 ----------

func _test_sens_direction() -> void:
	# 长距明显差 → 偏低建议
	var m := {"long_acc": 0.4, "short_acc": 0.85, "long_ratio": 0.35, "micro_adjusts": 5}
	var t := Advice.sens_direction_advice(m, 30)
	_check("长距弱 → 偏低方向建议", t.contains("偏低"), t)
	# 微调多 + 短距差 → 偏高建议
	var m2 := {"long_acc": 0.8, "short_acc": 0.6, "long_ratio": 0.35, "micro_adjusts": 60}
	var t2 := Advice.sens_direction_advice(m2, 30)
	_check("微调多+短距差 → 偏高方向建议", t2.contains("偏高"), t2)
	# 均衡 → 适配良好
	var m3 := {"long_acc": 0.8, "short_acc": 0.85, "long_ratio": 0.35, "micro_adjusts": 20}
	_check("均衡 → 适配良好", Advice.sens_direction_advice(m3, 30).contains("适配良好"))
	# 长距样本不足 → 无法判断
	var m4 := {"long_acc": 0.5, "short_acc": 0.8, "long_ratio": 0.05, "micro_adjusts": 5}
	_check("长距样本少 → 无法判断", Advice.sens_direction_advice(m4, 30).contains("无法给出"))
	# 历史对比
	_check("无 PSA 历史 → 空", Advice.compare_history_sens(0.3, []).is_empty())
	var recs := [{"ts": 1000, "type": "PSA", "sens": 0.28}, {"ts": 2000, "type": "CONSISTENCY", "sens": 0.3}]
	_check("历史 PSA 0.28 vs 当前 0.35 → 偏高", Advice.compare_history_sens(0.35, recs).contains("偏高"))
	_check("历史 PSA 0.28 vs 当前 0.3 → 一致", Advice.compare_history_sens(0.30, recs).contains("一致"))
	_check("历史 PSA 0.28 vs 当前 0.2 → 偏低", Advice.compare_history_sens(0.20, recs).contains("偏低"))

# ---------- 历史存储 ----------

func _test_history_store() -> void:
	HistoryStore.clear_all(TEST_HISTORY_PATH)
	HistoryStore.save_record({"ts": 1000, "type": "PSA", "sens": 0.35}, TEST_HISTORY_PATH)
	HistoryStore.save_record({"ts": 2000, "type": "CONSISTENCY", "sens": 0.5}, TEST_HISTORY_PATH)
	var records := HistoryStore.load_records(TEST_HISTORY_PATH)
	_check("历史新记录在前", records.size() == 2 and int(records[0]["ts"]) == 2000)
	HistoryStore.delete_record(2000, TEST_HISTORY_PATH)
	_check("历史删除", HistoryStore.load_records(TEST_HISTORY_PATH).size() == 1)
	HistoryStore.clear_all(TEST_HISTORY_PATH)
	_check("历史清空", HistoryStore.load_records(TEST_HISTORY_PATH).is_empty())

# ---------- 图表几何 ----------

func _test_chart() -> void:
	var c := Chart.new()
	c.size = Vector2(200, 100)
	var top := c._plot(Vector2(0.5, 1.0), Vector2(0, 1), Vector2(0, 1))
	var bottom := c._plot(Vector2(0.5, 0.0), Vector2(0, 1), Vector2(0, 1))
	_check("图表 y=1 顶部", absf(top.y - 22.0) < 0.01)
	_check("图表 y=0 底部", absf(bottom.y - 76.0) < 0.01)
	c.add_series([Vector2(0.2, 0.8), Vector2(0.5, 0.85)], Color.RED, "s")
	c.x_limits = Vector2(0.1, 0.9)
	var b := c._bounds()
	_check("图表 x 固定范围", absf(b["x"].x - 0.1) < 1e-6 and absf(b["x"].y - 0.9) < 1e-6)

# ---------- 微调检测 ----------

func _test_micro_detect() -> void:
	var shoot: Node3D = (load("res://test_shoot.tscn") as PackedScene).instantiate()
	root.add_child(shoot)
	await process_frame
	await physics_frame
	shoot.state = 2
	var cam: Camera3D = shoot.get_node("%Camera")
	var t: Node3D = (preload("res://target.tscn") as PackedScene).instantiate()
	shoot.target_root.add_child(t)
	await process_frame
	await physics_frame
	t.setup(0.2, cam.global_position + Vector3(0, 0, -8))
	shoot.active_targets.append(t)
	await physics_frame
	shoot._yaw = deg_to_rad(3.0)
	shoot._update_micro_adjust_detection()
	_check("微调首帧不计数", int(t.micro_adjusts) == 0)
	shoot._yaw = deg_to_rad(1.5)
	shoot._update_micro_adjust_detection()
	_check("微调反向计数 1", int(t.micro_adjusts) == 1)
	var before := int(t.micro_adjusts)
	shoot._update_micro_adjust_detection()
	_check("微调静止帧不计", int(t.micro_adjusts) == before)

# ---------- 长距配额与单盲 ----------

func _test_long_quota() -> void:
	var shoot: Node3D = (load("res://test_shoot.tscn") as PackedScene).instantiate()
	root.add_child(shoot)
	await process_frame
	var tc: Node = root.get_node("TestConfig")
	tc.set("test_mode", 0)  # STANDARD
	shoot.state = 2  # ACTIVE
	shoot._start_round()  # 真实路径：内部生成 12 位置洗牌取 4
	var positions: Array = shoot.get("_long_positions")
	_check("长距配额 4 个", positions.size() == 4, "n=%d" % positions.size())
	var cam: Camera3D = shoot.get_node("%Camera")
	shoot._yaw = 0.0
	cam.rotation = Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	var long_ok := true
	var long_count := 0
	var short_max := -1.0
	for i in 12:
		shoot.set("targets_spawned", i)
		var is_long: bool = positions.has(i)
		var pos: Vector3 = shoot._spawn_position(is_long)
		var ang := rad_to_deg(acos(clampf((pos - cam.global_position).normalized().dot(forward), -1.0, 1.0)))
		if is_long:
			long_count += 1
			if ang < 17.0:
				long_ok = false
		else:
			short_max = maxf(short_max, ang)
	_check("配额位置全部长距 ≥17°", long_ok and long_count == 4, "n=%d" % long_count)
	_check("非配额位置全部短距（≤15.5°）", short_max <= 15.5, "max=%.1f" % short_max)

func _test_blind_sens() -> void:
	var shoot: Node3D = (load("res://test_shoot.tscn") as PackedScene).instantiate()
	root.add_child(shoot)
	await process_frame
	shoot._apply_sens(0.35)
	_check("单盲：HUD 不显示灵敏度数值", shoot.get_node("%SensLabel").text.contains("??"), shoot.get_node("%SensLabel").text)

# ---------- 场景实例化 ----------

func _test_scenes() -> void:
	var all_ok := true
	for s in ["res://main.tscn", "res://test_select.tscn", "res://test_config.tscn",
			"res://test_shoot.tscn", "res://test_result.tscn", "res://history.tscn",
			"res://settings.tscn", "res://about.tscn"]:
		var ps := load(s)
		if ps == null:
			all_ok = false
			_check("场景加载失败: %s" % s, false)
			continue
		var inst: Node = (ps as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame
		inst.queue_free()
		await process_frame
	_check("8 场景实例化无错误", all_ok)

# ---------- 平坦检测与建议 ----------

func _test_flat_detection() -> void:
	var flat := TestPlan.new()
	flat.begin(false, 0.1, 0.9, 6)
	# 等效轨迹效率 t×sens/θ 恒定（0.4）→ 各点得分相同 → 平坦
	for x in [0.2, 0.35, 0.5, 0.65]:
		var r := _make_round(x, 10)
		r["hits"] = 10
		var times: Array = []
		for i in 12:
			times.append(0.12 / x)
		r["hit_times"] = times
		flat.add_result(r)
	var est := flat.best_estimate()
	_check("平坦检测 flat=true", est.get("flat", false))
	var sig := TestPlan.new()
	sig.begin(false, 0.1, 0.9, 6)
	for x in [0.2, 0.35, 0.5, 0.65]:
		sig.add_result(_make_round(x, 5 + int(round((x - 0.1) * 40))))
	_check("有信号 flat=false", not sig.best_estimate().get("flat", false))
	var p := Advice.diagnose({"accuracy": 0.75, "median_hit": 0.7, "median_correct": 0.2, "wasted": 2, "first_shot_rate": 0.4, "micro_adjusts": 5, "track_accuracy": -1.0, "switch_secs": -1.0}, [{}])
	_check("定位率 40% 触发诊断", p.any(func(x): return x["tag"] == "overaim"))
