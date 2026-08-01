extends RefCounted
# 多维目标函数（论文范式重构：每次单击一次判定）
# 参考瞄准研究范式（Fitts 类任务）：
#   每靶仅允许一次单击——点击时准星在目标内 = 成功，否则 = 失败（试验立即结束）
#   目标先可见再计时，测得纯运动反应时间；成功按完成时间打分（越快越高），失败 = 0 分
# score = mean(每靶得分) × 稳定性系数：
#   命中靶 → 1/(1 + t×sens/θ)（等效轨迹效率归一化，剥离灵敏度物理优势与角距差异）
#   失败靶 / 超时靶 → 0
#   稳定性系数 = 1/(1 + 命中耗时MAD归一化)：耗时忽快忽慢的轮被下调（恢复一致性维度，
#   不破坏 per-trial 结构——B 项：稳定性调制）
# accuracy = hits / (hits + misses + 超时数)（一次机会成功率，"没中就是没中"）

static func score(round_data: Dictionary) -> float:
	var times: Array = round_data.get("hit_times", [])
	var angles: Array = round_data.get("hit_angles", [])
	var targets := int(round_data.get("targets_done", 0))
	if targets <= 0:
		return 0.0
	var sens := maxf(float(round_data.get("sens", 0.0)), 0.001)
	var sum := 0.0
	for i in times.size():
		var th := 1.0
		if i < angles.size():
			th = maxf(float(angles[i]), 0.001)
		var eff := float(times[i]) * sens / th
		sum += 1.0 / (1.0 + eff)
	var base := sum / float(targets)
	return base * _stability_factor(times)

# 稳定性系数：命中耗时 MAD/中位数（波动越小越接近 1）
static func _stability_factor(times: Array) -> float:
	if times.size() < 2:
		return 1.0
	var med := median(times)
	if med <= 0.001:
		return 1.0
	var devs: Array[float] = []
	for t in times:
		devs.append(absf(t - med))
	var mad_norm := median(devs) / med
	return 1.0 / (1.0 + mad_norm)

static func accuracy(round_data: Dictionary) -> float:
	var hits := int(round_data.get("hits", 0))
	var misses := int(round_data.get("misses", 0))
	var expired := int(round_data.get("expired_angles", []).size())
	var denom := hits + misses + expired
	if denom <= 0:
		return 0.0
	return float(hits) / float(denom)

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5
