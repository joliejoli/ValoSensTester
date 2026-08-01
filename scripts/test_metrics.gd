extends RefCounted
# 全轮指标聚合（Phase 5.1）：结果页与单测共用
# 注意：不引用 TestConfig（headless --script 编译期不可用）

const Objective := preload("res://scripts/test_objective.gd")

static func aggregate(rounds: Array) -> Dictionary:
	var total_targets := 0
	var total_hits := 0
	var total_shots := 0
	var total_wasted := 0
	var first_shot := 0
	var micro := 0
	var hit_times: Array = []
	var corrections: Array = []
	var eff_times: Array = []
	var track_scores: Array = []
	var score_sum := 0.0
	for r in rounds:
		total_targets += int(r.get("targets_done", 0))
		total_hits += int(r.get("hits", 0))
		total_shots += int(r.get("shots", 0))
		total_wasted += int(r.get("overshoots", 0))
		first_shot += int(r.get("first_shot_hits", 0))
		micro += int(r.get("micro_adjusts", 0))
		var times: Array = r.get("hit_times", [])
		var angles: Array = r.get("hit_angles", [])
		var sens := maxf(float(r.get("sens", 0.0)), 0.001)
		for i in times.size():
			var th := 1.0
			if i < angles.size():
				th = maxf(float(angles[i]), 0.001)
			eff_times.append(float(times[i]) * sens / th)
		hit_times.append_array(times)
		corrections.append_array(r.get("correction_times", []))
		track_scores.append_array(r.get("track_scores", []))
		score_sum += Objective.score(r)
	# 修正耗时只统计有微调的靶（>0），0 表示一枪命中不计入"微调时长"
	var pos_corr: Array = []
	for c in corrections:
		if float(c) > 0.001:
			pos_corr.append(c)
	var track_acc := -1.0
	if not track_scores.is_empty():
		var s_sum := 0.0
		for s in track_scores:
			s_sum += float(s)
		track_acc = s_sum / float(track_scores.size())
	# 目标切换效率（Phase 6）：相邻命中时刻间隔的中位数（压力/标准模式切换节奏）
	var switch_secs := -1.0
	var hit_stamps: Array = []
	for r in rounds:
		hit_stamps.append_array(r.get("hit_timestamps", []))
	if hit_stamps.size() >= 4:
		var sorted_hits := hit_stamps.duplicate()
		sorted_hits.sort()
		var gaps: Array = []
		for i in range(1, sorted_hits.size()):
			gaps.append(float(sorted_hits[i]) - float(sorted_hits[i - 1]))
		switch_secs = median(gaps)
	# 长/短距分组命中率（一致性灵敏度方向分析）：长距阈值 15°（弧度）
	# 命中靶角度来自 hit_angles，超时靶角度来自 expired_angles
	var long_hits := 0
	var long_total := 0
	var short_hits := 0
	var short_total := 0
	for r in rounds:
		for a in r.get("hit_angles", []):
			if float(a) >= deg_to_rad(15.0):
				long_hits += 1
				long_total += 1
			else:
				short_hits += 1
				short_total += 1
		for a in r.get("expired_angles", []):
			if float(a) >= deg_to_rad(15.0):
				long_total += 1
			else:
				short_total += 1
	return {
		"accuracy": float(total_hits) / float(total_targets) if total_targets > 0 else 0.0,
		"shot_accuracy": float(total_hits) / float(total_shots) if total_shots > 0 else 0.0,
		"first_shot_rate": float(first_shot) / float(total_targets) if total_targets > 0 else 0.0,
		"median_hit": median(hit_times),
		"median_eff": median(eff_times),
		"median_correct": median(pos_corr),
		"wasted": total_wasted,
		"micro_adjusts": micro,
		"track_accuracy": track_acc,
		"switch_secs": switch_secs,
		"long_acc": float(long_hits) / float(long_total) if long_total > 0 else -1.0,
		"short_acc": float(short_hits) / float(short_total) if short_total > 0 else -1.0,
		"long_ratio": float(long_total) / float(total_targets) if total_targets > 0 else 0.0,
		"score": score_sum / float(rounds.size()) if not rounds.is_empty() else 0.0,
	}

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5
