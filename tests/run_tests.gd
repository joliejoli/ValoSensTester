extends SceneTree

# 常驻回归测试（论文范式重构后）：目标函数 / BO 收敛 / GP 方差 / 指标聚合 / 历史存储 / 图表几何 / 微调检测 / 一枪判定 / 场景实例化

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
	await _test_micro_detect()
	await _test_pause_time_exclusion()
	await _test_one_click_rule()
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

# ---------- 目标函数（论文范式：一次单击判定） ----------

func _test_objective() -> void:
	# 12 靶全中、每枪 0.6s、θ=0.3：eff=0.7 → 每靶 1/(1.7)=0.588 → score=0.588
	var all_hit := {"shots": 12, "hits": 12, "misses": 0, "targets_done": 12,
		"hit_times": [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6],
		"hit_angles": [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
		"expired_angles": [], "sens": 0.35}
	var s1 := Objective.score(all_hit)
	_check("全中得分 = 平均时间分", absf(s1 - 0.588) < 0.01, "=%f" % s1)
	_check("全中成功率 100%", absf(Objective.accuracy(all_hit) - 1.0) < 1e-9)
	# 失败靶（未击中点击）→ 0 分
	var with_miss := all_hit.duplicate(true)
	with_miss["hits"] = 10
	with_miss["misses"] = 2
	with_miss["hit_times"] = [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6]
	with_miss["hit_angles"] = [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
	_check("失败靶 0 分（10×0.588/12=0.49）", absf(Objective.score(with_miss) - 0.49) < 0.01, "=%f" % Objective.score(with_miss))
	_check("失败计入成功率 10/12", absf(Objective.accuracy(with_miss) - 10.0 / 12.0) < 1e-9)
	# 超时靶 → 0 分且计入分母
	var with_timeout := all_hit.duplicate(true)
	with_timeout["hits"] = 10
	with_timeout["misses"] = 0
	with_timeout["expired_angles"] = [0.3, 0.3]
	with_timeout["hit_times"] = [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6]
	with_timeout["hit_angles"] = [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
	_check("超时靶 0 分且成功率 10/12", absf(Objective.accuracy(with_timeout) - 10.0 / 12.0) < 1e-9, "=%f" % Objective.accuracy(with_timeout))
	# 全失败 → 0（无兜底）
	var all_miss := {"shots": 0, "hits": 0, "misses": 12, "targets_done": 12, "hit_times": [], "hit_angles": [], "expired_angles": [], "sens": 0.35}
	_check("全失败得 0 分", absf(Objective.score(all_miss)) < 1e-9)
	_check("全失败成功率 0", absf(Objective.accuracy(all_miss)) < 1e-9)
	# 越快分越高：0.3s 靶 vs 1.2s 靶
	var fast := all_hit.duplicate(true)
	fast["hit_times"] = [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
	var slow := all_hit.duplicate(true)
	slow["hit_times"] = [1.2, 1.2, 1.2, 1.2, 1.2, 1.2, 1.2, 1.2, 1.2, 1.2, 1.2, 1.2]
	_check("完成越快得分越高", Objective.score(fast) > Objective.score(slow))
	# 稳定性调制（B 项）：同平均耗时下，波动大的轮得分更低
	var stable := all_hit.duplicate(true)
	stable["hit_times"] = [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6]
	var unstable := all_hit.duplicate(true)
	unstable["hit_times"] = [0.2, 0.2, 0.2, 0.2, 1.0, 1.0, 1.0, 1.0, 0.6, 0.6, 0.6, 0.6]
	_check("波动大的轮得分更低（稳定性调制）", Objective.score(stable) > Objective.score(unstable), "stable=%f unstable=%f" % [Objective.score(stable), Objective.score(unstable)])

# ---------- BO 收敛 ----------

func _test_bo_convergence() -> void:
	var plan := TestPlan.new()
	plan.begin(false, 0.1, 0.9, 10)
	var xs := [0.26, 0.42, 0.58, 0.74]
	xs.shuffle()
	for x in xs:
		plan.add_result(_make_round(x, _peak_hits(x)))
	var bo_round := 0
	while plan._bo.sample_count() < 10:
		var sens := plan.next_sens(4 + bo_round)
		bo_round += 1
		plan.add_result(_make_round(sens, _peak_hits(sens)))
	var est := plan.best_estimate()
	_check("BO 收敛到峰值 0.45 ±0.08", absf(float(est["sens"]) - 0.45) <= 0.08, "sens=%f" % float(est["sens"]))

# 真实峰曲线：峰值在 0.45 的命中数（BO 收敛测试用）
func _peak_hits(x: float) -> int:
	return int(round(11.0 * exp(-pow((x - 0.45) / 0.18, 2.0))))

func _make_round(x: float, hits: int) -> Dictionary:
	var times: Array = []
	for i in hits:
		times.append(0.6)
	var angles: Array = []
	for i in hits:
		angles.append(0.3)
	return {"sens": x, "targets_done": 12, "hits": hits, "misses": maxf(12 - hits, 0),
		"hit_times": times, "hit_angles": angles, "expired_angles": [], "shots": hits,
		"shot_timestamps": []}

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
	var rounds := [{
		"targets_done": 12, "hits": 9, "misses": 2, "micro_adjusts": 20,
		"hit_times": [0.5, 0.6, 0.7], "hit_angles": [0.2, 0.3, 0.4],
		"hit_timestamps": [1.0, 2.0, 3.0, 4.0, 5.0], "sens": 0.35, "shots": 11,
		"expired_angles": [0.3], "track_scores": [0.7, 0.8],
		"miss_times": [0.4, 1.4]}]
	var m := TestMetrics.aggregate(rounds)
	_check("成功率 9/(9+2+1)=75%", absf(m.accuracy - 0.75) < 1e-9, "=%f" % m.accuracy)
	_check("归一化耗时 median([0.875,0.7,0.6125])=0.7", absf(m.median_eff - 0.7) < 1e-9)
	_check("跟枪精度平均 0.75", absf(m.track_accuracy - 0.75) < 1e-9)
	_check("切换间隔 1.0s", absf(m.switch_secs - 1.0) < 1e-9)
	_check("每靶微调 20/12=1.67", absf(float(m.micro_adjusts) / 12.0 - 20.0 / 12.0) < 1e-9)
	_check("失败耗时中位 median([0.4,1.4])=0.9", absf(m.median_miss - 0.9) < 1e-9, "=%f" % m.median_miss)

# ---------- 灵敏度方向建议 ----------

func _test_sens_direction() -> void:
	var m := {"long_acc": 0.4, "short_acc": 0.85, "long_ratio": 0.35, "micro_adjusts": 5}
	var t := Advice.sens_direction_advice(m, 30)
	_check("长距弱 → 偏低方向建议", t.contains("偏低"), t)
	var m2 := {"long_acc": 0.8, "short_acc": 0.6, "long_ratio": 0.35, "micro_adjusts": 60}
	var t2 := Advice.sens_direction_advice(m2, 30)
	_check("微调多+短距差 → 偏高方向建议", t2.contains("偏高"), t2)
	var m3 := {"long_acc": 0.8, "short_acc": 0.85, "long_ratio": 0.35, "micro_adjusts": 20}
	_check("均衡 → 适配良好", Advice.sens_direction_advice(m3, 30).contains("适配良好"))
	var m4 := {"long_acc": 0.5, "short_acc": 0.8, "long_ratio": 0.05, "micro_adjusts": 5}
	_check("长距样本少 → 无法判断", Advice.sens_direction_advice(m4, 30).contains("无法给出"))
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

# ---------- 暂停不污染命中耗时（评分 0 bug 根因） ----------

func _test_pause_time_exclusion() -> void:
	var shoot: Node3D = (load("res://test_shoot.tscn") as PackedScene).instantiate()
	root.add_child(shoot)
	await process_frame
	await physics_frame
	shoot.set_process(false)
	for t in shoot.active_targets:
		t.free()
	shoot.active_targets.clear()
	shoot.state = 2
	shoot.round_data = {"misses": 0, "micro_adjusts": 0, "hit_times": [], "hit_angles": [], "hit_timestamps": [], "track_scores": [], "shot_timestamps": [], "miss_times": []}
	var cam: Camera3D = shoot.get_node("%Camera")
	var t: Node3D = (preload("res://target.tscn") as PackedScene).instantiate()
	shoot.target_root.add_child(t)
	await process_frame
	await physics_frame
	t.setup(0.2, cam.global_position + Vector3(0, 0, -8))
	t.hit.connect(shoot._on_target_hit)
	shoot.active_targets.append(t)
	await physics_frame
	# 暂停 0.3 秒（create_timer 默认忽略暂停继续计时）
	shoot._toggle_pause()
	await create_timer(0.3).timeout
	shoot._toggle_pause()
	t.register_hit()
	await process_frame
	var ht := float(shoot.round_data["hit_times"][0])
	_check("命中耗时不含暂停时长（<0.5s）", ht < 0.5, "ht=%.2f" % ht)

# ---------- 一枪判定（论文范式） ----------

func _test_one_click_rule() -> void:
	var shoot: Node3D = (load("res://test_shoot.tscn") as PackedScene).instantiate()
	root.add_child(shoot)
	await process_frame
	await physics_frame
	shoot.state = 2  # ACTIVE
	shoot.round_data = {"misses": 0, "micro_adjusts": 0, "hit_times": [], "hit_angles": [], "hit_timestamps": [], "track_scores": [], "shot_timestamps": []}
	var tc: Node = root.get_node("TestConfig")
	tc.set("test_mode", 0)  # STANDARD 单靶
	var cam: Camera3D = shoot.get_node("%Camera")
	# 停掉 _process + 清掉热身靶（此时 state 还是 WARMUP，不会补生成）
	shoot.set_process(false)
	for t in shoot.active_targets:
		t.free()
	shoot.active_targets.clear()
	shoot.state = 2  # ACTIVE
	shoot.round_data = {"misses": 0, "micro_adjusts": 0, "hit_times": [], "hit_angles": [], "hit_timestamps": [], "track_scores": [], "shot_timestamps": [], "miss_times": []}
	await process_frame
	# 靶放在准星偏 10° 处（点击未命中 → 失败消失）
	var t: Node3D = (preload("res://target.tscn") as PackedScene).instantiate()
	shoot.target_root.add_child(t)
	await process_frame
	await physics_frame
	t.setup(0.2, cam.global_position + Vector3(0, 0, -8).rotated(Vector3.UP, deg_to_rad(10.0)))
	shoot.active_targets.append(t)
	await physics_frame
	# 直接调用失败判定（绕过物理残留靶干扰；射线命中判定由 _cast_ray 覆盖）
	shoot._on_miss_click(Time.get_ticks_msec())
	await process_frame
	_check("未命中点击 → 失败计数 1", int(shoot.round_data["misses"]) == 1, "=%d" % int(shoot.round_data["misses"]))
	_check("单靶模式失败 → 推进正常（下一靶已生成）", shoot.active_targets.size() == 1, "n=%d" % shoot.active_targets.size())
	_check("失败推进靶计数", shoot.targets_done == 1)
	# 正前方命中 → 成功不计失败
	var t2: Node3D = (preload("res://target.tscn") as PackedScene).instantiate()
	shoot.target_root.add_child(t2)
	await process_frame
	await physics_frame
	t2.setup(0.2, cam.global_position + Vector3(0, 0, -8))
	t2.hit.connect(shoot._on_target_hit)
	shoot.active_targets.append(t2)
	await physics_frame
	t2.register_hit()  # 模拟命中（射线命中判定由 _cast_ray 覆盖）
	await process_frame
	_check("命中点击 → 成功（misses 不变）", int(shoot.round_data["misses"]) == 1 and shoot.hit_count == 1, "misses=%d hits=%d" % [int(shoot.round_data["misses"]), shoot.hit_count])

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
	for x in [0.2, 0.35, 0.5, 0.65]:
		# 等效轨迹效率 t×sens/θ 恒定（0.4）→ 各点得分相同 → 平坦
		var r := _make_round(x, 10)
		var times: Array = []
		for i in 10:
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
	var p := Advice.diagnose({"accuracy": 0.6, "median_hit": 0.7, "median_eff": 0.6, "micro_adjusts": 5, "track_accuracy": -1.0, "switch_secs": -1.0}, [{}])
	_check("成功率 60% 触发命中率诊断", p.any(func(x): return x["tag"] == "slow_aim"))
