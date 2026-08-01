extends RefCounted
# 智能建议系统（Phase 5.3）：问题识别 + 个性化建议 + 分享文本
# 纯静态函数，输入聚合指标/优化摘要/每轮数据，输出建议列表

const Objective := preload("res://scripts/test_objective.gd")

# 问题识别：返回 [{tag, title, detail}]（tag: overaim/slow_aim/low_acc/unstable/fast_unstable）
static func diagnose(metrics: Dictionary, rounds: Array) -> Array:
	var problems: Array = []
	var targets := 0
	for r in rounds:
		targets += int(r.get("targets_done", 0))
	var wasted_per := float(metrics.wasted) / float(maxf(targets, 1))
	var acc := float(metrics.accuracy)
	var hit := float(metrics.median_hit)
	var correct := float(metrics.median_correct)
	var first_rate := float(metrics.get("first_shot_rate", 0.0))
	# 轨迹级微调（准星方向反转/靶，与是否开火无关——不开火玩家同样可测）
	var adjust_per := float(metrics.get("micro_adjusts", 0)) / float(maxf(targets, 1))
	if adjust_per > 2.5:
		problems.append({
			"tag": "overaim",
			"title": "瞄准微调偏多（准星来回摆动）",
			"detail": "每靶平均准星反向调整 %.1f 次，准星到位后仍在反复确认，建议先慢速一停一打、再逐步提速。" % adjust_per,
		})
	if first_rate > 0.0 and first_rate < 0.55:
		problems.append({
			"tag": "overaim",
			"title": "一次定位率偏低（需要多次修正）",
			"detail": "第一枪命中率 %.0f%%，多数目标需要补枪修正，拉枪定位精度是主要瓶颈。" % (first_rate * 100.0),
		})
	if correct > 0.35 or wasted_per > 0.3:
		problems.append({
			"tag": "overaim",
			"title": "瞄准修正偏多（过度瞄准）",
			"detail": "中位修正耗时 %.2fs、每靶多余开火 %.2f 次，说明准星到位后仍在反复修正。" % [correct, wasted_per],
		})
	if acc < 0.75:
		problems.append({
			"tag": "slow_aim",
			"title": "命中率偏低（时间压力/反应偏慢）",
			"detail": "命中率 %.0f%%，部分目标可能 3s 超时。首次出手速度是主要瓶颈。" % (acc * 100.0),
		})
	if acc >= 0.85 and hit > 1.0:
		problems.append({
			"tag": "slow_aim",
			"title": "求稳但偏慢（微调能力需提升）",
			"detail": "命中率 %.0f%% 但中位命中耗时 %.2fs，靶子基本都能打中，但慢在最后一步微调。" % [acc * 100.0, hit],
		})
	if hit < 0.6 and acc < 0.8:
		problems.append({
			"tag": "fast_unstable",
			"title": "快而不稳",
			"detail": "中位命中 %.2fs 很快但命中率只有 %.0f%%，建议放慢节奏保证准星停稳再开枪。" % [hit, acc * 100.0],
		})
	var scores: Array = []
	for r in rounds:
		scores.append(Objective.score(r))
	if scores.size() >= 3:
		var mean := 0.0
		for s in scores:
			mean += s
		mean /= float(scores.size())
		var var_y := 0.0
		for s in scores:
			var d: float = s - mean
			var_y += d * d
		if mean > 0.0 and sqrt(var_y / float(scores.size() - 1)) / mean > 0.12:
			problems.append({
				"tag": "unstable",
				"title": "轮间稳定性波动较大",
				"detail": "各轮得分波动幅度超过均值 12%%，状态起伏明显，适合固定灵敏度下多练稳定手感。",
			})
	return problems

# 个性化建议（问题对应的训练方向）
static func train_advice(problems: Array) -> Array:
	var advice: Array = []
	for p in problems:
		match p["tag"]:
			"overaim":
				advice.append("预瞄练习：把准星停在靶心再开枪，先慢后快（训练后命中前空枪应逐步减少）")
			"slow_aim":
				advice.append("快速拉枪练习：用大角度靶反复练习一枪到位，再逐步缩小靶子")
			"fast_unstable":
				advice.append("节奏控制练习：每枪前刻意停顿 0.1-0.2s，确保准星稳定再击发")
			"unstable":
				advice.append("固定灵敏度专项练习：连续多日同一灵敏度练习，减少轮间状态波动")
	return advice

# 发力方式通用建议（基于推荐灵敏度，标注因人而异）
static func grip_advice(sens: float) -> String:
	if sens < 0.30:
		return "低灵敏度下大角度拉枪依赖手臂移动：建议桌面/椅子高度让手臂能自由滑动，握持自然放松（通用建议，因人而异）"
	if sens > 0.60:
		return "高灵敏度下微调依赖手腕：注意避免长时间压腕（腕管压力），定期放松手腕（通用建议，因人而异）"
	return "中灵敏度适合手臂+手腕混合发力：大角度用手臂、微调用手腕，保持掌心贴合鼠标（通用建议，因人而异）"

# 分享文本卡片
static func share_text(s: Dictionary, metrics: Dictionary, problems: Array, advice: Array, rounds: Array, grip: String) -> String:
	var is_consistency: bool = s.get("is_consistency", false)
	var lines: Array = []
	lines.append("【无畏契约灵敏度测试结果】")
	lines.append("类型：%s（%d 轮）" % ["一致性测试" if is_consistency else "灵敏度测试", rounds.size()])
	if not is_consistency:
		lines.append("推荐灵敏度：%.2f（游戏内）" % float(s.get("best_sens", 0.0)))
	lines.append("eDPI ≈ %d · 参考 800 DPI 时 %.1f cm/360°" % [int(s.get("edpi", 0)), _edpi_to_cm(float(s.get("edpi", 0.0)))])
	lines.append("综合评分：%.2f（95%% CI %.2f~%.2f）" % [
		float(s.get("score_mean", 0.0)),
		float(s.get("score_low", 0.0)),
		float(s.get("score_high", 0.0)),
	])
	var tg := 0
	for r in rounds:
		tg += int(r.get("targets_done", 0))
	lines.append("命中率 %.1f%% · 中位命中 %.2fs · 每靶微调 %.1f 次 · 多余开火 %d" % [
		float(metrics.accuracy) * 100.0,
		float(metrics.median_hit),
		float(metrics.get("micro_adjusts", 0)) / float(maxf(tg, 1)),
		int(metrics.wasted),
	])
	if problems.is_empty():
		lines.append("建议：当前表现均衡，可在推荐灵敏度下继续巩固")
	else:
		lines.append("建议：")
		for a in advice:
			lines.append("· " + a)
	lines.append("· " + grip)
	return "\n".join(lines)

static func _edpi_to_cm(edpi: float) -> float:
	if edpi <= 0.0:
		return 0.0
	return 914.4 / (0.07 * edpi)
