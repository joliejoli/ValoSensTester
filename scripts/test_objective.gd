extends RefCounted
# 多维目标函数（Phase 4 信度/效度修订版）
# score = 0.5×accuracy + 0.3×speed + 0.2×consistency
# accuracy   = hits/shots
# speed      = 1/(1 + median(hit_times))，中位数抗离群
# consistency= 1/(1 + MAD归一化 + 0.25×越靶率)，MAD 替代 std 抗离群，越靶反映微调失控

const WEIGHT_ACC := 0.5
const WEIGHT_SPEED := 0.3
const WEIGHT_CONS := 0.2
const OVER_SHOOT_PENALTY := 0.25

static func score(round_data: Dictionary) -> float:
	var acc := accuracy(round_data)
	var speed := speed_score(round_data)
	var cons := consistency_score(round_data)
	return WEIGHT_ACC * acc + WEIGHT_SPEED * speed + WEIGHT_CONS * cons

static func accuracy(round_data: Dictionary) -> float:
	var shots := int(round_data.get("shots", 0))
	if shots <= 0:
		return 0.0
	return float(int(round_data.get("hits", 0))) / float(shots)

static func speed_score(round_data: Dictionary) -> float:
	var times: Array = round_data.get("hit_times", [])
	if times.is_empty():
		return 0.5
	return 1.0 / (1.0 + median(times))

static func consistency_score(round_data: Dictionary) -> float:
	var times: Array = round_data.get("hit_times", [])
	if times.is_empty():
		return 0.5
	var targets := int(round_data.get("targets_done", times.size()))
	if targets <= 0:
		return 0.5
	var mad_norm := 0.0
	if times.size() >= 2:
		var med := median(times)
		if med > 0.001:
			var devs: Array[float] = []
			for t in times:
				devs.append(absf(t - med))
			mad_norm = median(devs) / med
	var over_norm := float(int(round_data.get("overshoots", 0))) / float(targets)
	return 1.0 / (1.0 + mad_norm + OVER_SHOOT_PENALTY * over_norm)

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5
