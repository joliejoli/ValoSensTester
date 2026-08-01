extends SceneTree

# 检查：折线图第一个灵敏度数据一致性（obs 顺序/数值 vs round_results + x_limits）

const Objective := preload("res://scripts/test_objective.gd")

func _init() -> void:
	await process_frame
	var tc: Node = root.get_node("TestConfig")
	var rounds: Array = []
	var sens_seq := [0.58, 0.26, 0.74, 0.42, 0.50, 0.30, 0.65, 0.35, 0.55, 0.45]
	for i in 10:
		var times: Array = []
		for j in 12:
			times.append(0.6)
		rounds.append({
			"round": i + 1, "sens": sens_seq[i], "shots": 12, "hits": 9 + (i % 3),
			"overshoots": 2, "first_shot_hits": 7, "micro_adjusts": 10, "targets_done": 12, "first_hit_time": 0.8,
			"total_time_ms": 20000, "shot_timestamps": [], "hit_times": times,
			"hit_angles": [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
			"hit_timestamps": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0],
			"expired_angles": [], "correction_times": [],
		})
	tc.set("round_results", rounds)
	tc.set("opt_summary", {
		"best_sens": 0.35, "score_mean": 0.8, "score_low": 0.7, "score_high": 0.9,
		"mode_label": "test", "dpi": 800, "edpi": 280, "samples": 10, "is_consistency": false, "flat": false,
	})
	tc.set("sens_min", 0.1)
	tc.set("sens_max", 0.9)
	var r: Control = (load("res://test_result.tscn") as PackedScene).instantiate()
	root.add_child(r)
	await process_frame
	var curve: Dictionary = r._gp_curve(rounds)
	var obs: Array = curve["obs"]
	print("== obs 前 3 点 ==")
	for i in mini(obs.size(), 3):
		var rd: Dictionary = rounds[i]
		var expect_score := Objective.score(rd)
		var ok_x: bool = absf(obs[i].x - float(rd.get("sens", 0.0))) < 1e-6
		var ok_y: bool = absf(obs[i].y - expect_score) < 1e-6
		print("  点%d: x=%.2f (round sens=%.2f, %s) y=%.4f (Objective.score=%.4f, %s)" % [
			i + 1, obs[i].x, float(rd.get("sens", 0.0)), "OK" if ok_x else "MISMATCH",
			obs[i].y, expect_score, "OK" if ok_y else "MISMATCH"])
	# 第一个灵敏度 = round_results[0].sens = 0.58（粗扫随机顺序首点）
	print("== 检查 ==")
	var first_ok: bool = absf(obs[0].x - 0.58) < 1e-6
	print("第一个灵敏度点 x=0.58 正确: ", first_ok)
	print("x_limits 应为 (0.1, 0.9): ", r.get_node("Scroll/Center/VBox/PageChartBox").get_child(0).x_limits)
	var grid: Array = curve["mean"]
	print("GP 曲线点数: ", grid.size(), " x 范围: %.2f ~ %.2f" % [grid[0].x, grid[grid.size() - 1].x])
	var full: bool = absf(grid[0].x - 0.1) < 0.02 and absf(grid[grid.size() - 1].x - 0.9) < 0.02
	print("GP 曲线覆盖全范围 (0.1~0.9): ", full)
	quit(0 if full else 1)
