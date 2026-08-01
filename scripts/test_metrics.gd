extends RefCounted
# 全轮指标聚合（Phase 5.1）：结果页与单测共用
# 注意：不引用 TestConfig（headless --script 编译期不可用）

const Objective := preload("res://scripts/test_objective.gd")

static func aggregate(rounds: Array) -> Dictionary:
	var total_targets := 0
	var total_hits := 0
	var total_wasted := 0
	var first_shot := 0
	var hit_times: Array = []
	var corrections: Array = []
	var score_sum := 0.0
	for r in rounds:
		total_targets += int(r.get("targets_done", 0))
		total_hits += int(r.get("hits", 0))
		total_wasted += int(r.get("overshoots", 0))
		first_shot += int(r.get("first_shot_hits", 0))
		hit_times.append_array(r.get("hit_times", []))
		corrections.append_array(r.get("correction_times", []))
		score_sum += Objective.score(r)
	# 修正耗时只统计有微调的靶（>0），0 表示一枪命中不计入"微调时长"
	var pos_corr: Array = []
	for c in corrections:
		if float(c) > 0.001:
			pos_corr.append(c)
	return {
		"accuracy": float(total_hits) / float(total_targets) if total_targets > 0 else 0.0,
		"first_shot_rate": float(first_shot) / float(total_targets) if total_targets > 0 else 0.0,
		"median_hit": median(hit_times),
		"median_correct": median(pos_corr),
		"wasted": total_wasted,
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
