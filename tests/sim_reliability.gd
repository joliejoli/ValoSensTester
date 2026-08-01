extends SceneTree

# 信度仿真：轮间任务结构（长距随机 vs 固定配额）对 score 噪声的影响 + BO 分辨力
# 结论写入附录 E 评估文档

const Objective := preload("res://scripts/test_objective.gd")
const TestPlan := preload("res://scripts/test_plan.gd")

var failures := 0

func _init() -> void:
	await process_frame
	_run()
	print("失败数: ", failures)
	quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _sim_round(sens: float, n_long: int, rng: RandomNumberGenerator) -> Dictionary:
	# 模拟玩家：长距命中率 0.72、短距 0.88，命中耗时随 sens 轻微变化（真实信号）
	var hit_times: Array = []
	var hit_angles: Array = []
	var hits := 0
	var total := 12
	for i in total:
		var is_long := i < n_long
		var acc := 0.72 if is_long else 0.88
		var angle := deg_to_rad(randf_range(18.0, 30.0)) if is_long else deg_to_rad(randf_range(6.0, 14.0))
		if rng.randf() < acc:
			hits += 1
			hit_times.append(randf_range(0.5, 1.1) + rng.randf_range(-0.1, 0.1) * (sens - 0.45))
			hit_angles.append(angle)
	return {"sens": sens, "targets_done": 12, "hits": hits, "overshoots": 0,
		"hit_times": hit_times, "hit_angles": hit_angles, "correction_times": [], "shots": hits, "shot_timestamps": []}

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	# 1) 轮间任务结构：长距随机（二项 35%） vs 固定配额（4/12），同玩家同 sens 重复 200 轮
	var rand_scores: Array = []
	var fixed_scores: Array = []
	for i in 200:
		rng.seed = i
		var n_long_rand := 0
		for j in 12:
			if rng.randf() < 0.35:
				n_long_rand += 1
		rand_scores.append(Objective.score(_sim_round(0.45, n_long_rand, rng)))
		fixed_scores.append(Objective.score(_sim_round(0.45, 4, rng)))
	var sd_rand := _sd(rand_scores)
	var sd_fixed := _sd(fixed_scores)
	print("   长距随机轮间 score SD: %.4f | 固定配额: %.4f（降噪 %.0f%%）" % [sd_rand, sd_fixed, 100.0 * (1.0 - sd_fixed / sd_rand)])
	_check("固定配额降噪 ≥10%", sd_fixed < sd_rand * 0.90, "rand=%.4f fixed=%.4f" % [sd_rand, sd_fixed])
	# 2) GP σ_n 匹配度：仿真噪声 vs 当前 0.12
	print("   仿真单轮 score SD ≈ %.4f（当前 GP σ_n=0.12）" % sd_fixed)
	_check("σ_n 高估 ≥1.5 倍（过平滑）", sd_fixed < 0.12 * 0.66, "sd=%.4f" % sd_fixed)
	# 3) BO 分辨力：真实信号幅度 vs 噪声
	#    相邻 sens（0.05 步长）真实差异 0.02-0.03 → 与噪声 SD 0.05-0.07 比
	var sig := 0.03
	var noise := sd_fixed
	print("   相邻灵敏度真实差异 ~%.2f vs 单轮噪声 SD %.4f → 信噪比 %.2f" % [sig, noise, sig / noise])
	_check("相邻差异信噪比 <1（附录 B 结论延续）", sig / noise < 1.0)
	# 4) 平均多轮后的信噪比：BO 每点单轮 → 若每点 2 轮
	var noise2 := noise / sqrt(2.0)
	print("   每点 2 轮平均后信噪比 %.2f" % (sig / noise2))
	_check("每点 2 轮仍 <1", sig / noise2 < 1.0)

func _sd(values: Array) -> float:
	var mean := 0.0
	for v in values:
		mean += v
	mean /= float(values.size())
	var v := 0.0
	for x in values:
		var d: float = x - mean
		v += d * d
	return sqrt(v / float(values.size() - 1))
