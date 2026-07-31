extends RefCounted
# 多维目标函数（Phase 4.5 修订版）
# score = 0.5×accuracy + 0.3×speed + 0.2×consistency
# accuracy   = hits/targets_done（以靶为单位，超时靶=未命中，恢复时间压力下的区分度）
# speed      = 1/(1 + median(t×sens))，t×sens 归一化剥离灵敏度物理优势
#             （恒速模型下到达时间 t ∝ 角度/sens，乘 sens 后与灵敏度无关，衡量瞄准效率）
# consistency= 1/(1 + MAD归一化 + 0.25×越靶率)，MAD/median 为比例，天然无量纲

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
	var targets := int(round_data.get("targets_done", 0))
	if targets <= 0:
		return 0.0
	return float(int(round_data.get("hits", 0))) / float(targets)

static func speed_score(round_data: Dictionary) -> float:
	var times: Array = round_data.get("hit_times", [])
	if times.is_empty():
		return 0.5
	var sens := maxf(float(round_data.get("sens", 0.0)), 0.001)
	return 1.0 / (1.0 + median(times) * sens)

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
