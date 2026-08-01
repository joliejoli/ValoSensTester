extends RefCounted
# 多维目标函数（Phase 4.5 修订版 + 复审 P0-3 + 用户决策：没中就是没中）
# score = 0.5×accuracy + 0.3×speed + 0.2×consistency
# accuracy   = hits / (targets_done + 空枪数)，分母 = 已出靶（每靶至少一次机会，超时靶计失败）
#             + 打空枪次数（shots - hits，每发空枪都算一次失败——灵敏度不合适会直接体现在准确率）
# speed      = 1/(1 + median(t×sens/θ))，t×sens 归一化剥离灵敏度物理优势，再除以每靶角距 θ
#             （等效轨迹效率 = 鼠标物理移动距离/目标角距，8° 靶与 46° 靶同分；无角距数据时退化为 t×sens）
# consistency= 1/(1 + MAD归一化)（耗时稳定性；空枪惩罚已并入 accuracy，不再重复计越靶率）

const WEIGHT_ACC := 0.5
const WEIGHT_SPEED := 0.3
const WEIGHT_CONS := 0.2

static func score(round_data: Dictionary) -> float:
	var acc := accuracy(round_data)
	var speed := speed_score(round_data)
	var cons := consistency_score(round_data)
	return WEIGHT_ACC * acc + WEIGHT_SPEED * speed + WEIGHT_CONS * cons

static func accuracy(round_data: Dictionary) -> float:
	var targets := int(round_data.get("targets_done", 0))
	var hits := int(round_data.get("hits", 0))
	var shots := int(round_data.get("shots", 0))
	# 空枪数 = shots - hits（每枪要么命中要么空枪）；超时靶无开火也计入 targets 分母
	var denom := targets + maxf(shots - hits, 0)
	if denom <= 0:
		return 0.0
	return float(hits) / float(denom)

static func speed_score(round_data: Dictionary) -> float:
	var times: Array = round_data.get("hit_times", [])
	if times.is_empty():
		return 0.5
	var angles: Array = round_data.get("hit_angles", [])
	var sens := maxf(float(round_data.get("sens", 0.0)), 0.001)
	var eff: Array[float] = []
	for i in times.size():
		var theta := 1.0
		if i < angles.size():
			theta = maxf(float(angles[i]), 0.001)
		eff.append(float(times[i]) * sens / theta)
	return 1.0 / (1.0 + median(eff))

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
	return 1.0 / (1.0 + mad_norm)

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5
