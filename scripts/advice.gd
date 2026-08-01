extends RefCounted
# 智能建议系统（Phase 5.3）：问题识别 + 个性化建议 + 分享文本
# 纯静态函数，输入聚合指标/优化摘要/每轮数据，输出建议列表

const Objective := preload("res://scripts/test_objective.gd")

# 问题识别：返回 [{tag, title, detail}]（tag: overaim/slow_aim/low_acc/unstable/fast_unstable/track）
static func diagnose(metrics: Dictionary, rounds: Array) -> Array:
	var problems: Array = []
	var targets := 0
	for r in rounds:
		targets += int(r.get("targets_done", 0))
	var acc := float(metrics.accuracy)
	var eff := float(metrics.get("median_eff", 0.0))
	# 轨迹级微调（准星方向反转/靶，与是否开火无关——不开火玩家同样可测）
	var adjust_per := float(metrics.get("micro_adjusts", 0)) / float(maxf(targets, 1))
	# 跟枪精度（移动靶/追踪，-1 表示无移动靶数据）
	var track_acc := float(metrics.get("track_accuracy", -1.0))
	if track_acc >= 0.0 and track_acc < 0.6:
		problems.append({
			"tag": "track",
			"title": "跟枪精度不足",
			"detail": "准星停留在靶心命中区内的时间仅 %.0f%%，移动目标跟枪不够稳定。" % (track_acc * 100.0),
		})
	# 目标切换效率（Phase 6，-1 表示样本不足）：多目标间命中间隔偏长 → 切换偏慢
	var switch_secs := float(metrics.get("switch_secs", -1.0))
	if switch_secs > 0.0 and switch_secs > 1.5:
		problems.append({
			"tag": "slow_aim",
			"title": "目标切换偏慢",
			"detail": "相邻目标平均命中间隔 %.1fs，多目标场景下切换节奏偏慢，需要更快的目标转移。" % switch_secs,
		})
	if adjust_per > 2.5:
		problems.append({
			"tag": "overaim",
			"title": "瞄准微调偏多（准星来回摆动）",
			"detail": "每靶平均准星反向调整 %.1f 次，准星到位后仍在反复确认，建议先慢速一停一打、再逐步提速。" % adjust_per,
		})
	if acc < 0.75:
		problems.append({
			"tag": "slow_aim",
			"title": "命中率偏低（一次单击成功率）",
			"detail": "一次单击成功率 %.0f%%，单击时准星经常不在目标上，拉枪定位精度是主要瓶颈。" % (acc * 100.0),
		})
	# 快慢判断用归一化耗时（t×sens/θ，轨迹效率，与 score 口径一致）
	if eff > 0.0 and acc >= 0.85 and eff > 0.6:
		problems.append({
			"tag": "slow_aim",
			"title": "求稳但偏慢（微调能力需提升）",
			"detail": "成功率 %.0f%% 但轨迹效率 %.2f（等效鼠标移动距离/角距），慢在最后一步微调。" % [acc * 100.0, eff],
		})
	if eff > 0.0 and eff < 0.35 and acc < 0.8:
		problems.append({
			"tag": "fast_unstable",
			"title": "快而不稳",
			"detail": "轨迹效率 %.2f 很快但成功率只有 %.0f%%，建议放慢节奏保证准星停稳再开枪。" % [eff, acc * 100.0],
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
			"track":
				advice.append("跟枪练习：在移动靶上保持准星贴住靶心移动，从慢速目标开始逐步提速")
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

# 一致性测试的"灵敏度快/慢"方向建议（基于长/短距分组命中率 + 微调指标推断）
# 返回建议文本；数据不足时返回空串
static func sens_direction_advice(metrics: Dictionary, targets: int) -> String:
	var long_acc := float(metrics.get("long_acc", -1.0))
	var short_acc := float(metrics.get("short_acc", -1.0))
	var long_ratio := float(metrics.get("long_ratio", 0.0))
	var adjust_per := float(metrics.get("micro_adjusts", 0)) / float(maxf(targets, 1))
	if long_acc < 0.0 or short_acc < 0.0:
		return ""
	# 长距靶样本不足（<15%）时方向推断不可靠
	if long_ratio < 0.15:
		return "本次长距靶样本偏少，暂无法给出灵敏度方向判断；建议多测几轮或运行 PSA 测试获得精确推荐。"
	if long_acc - short_acc <= -0.15:
		return "大角度拉枪明显吃力（长距命中率 %.0f%% vs 短距 %.0f%%），大范围移动跟不上——当前灵敏度可能偏低，建议调高 0.05~0.10 后重测对比。" % [long_acc * 100.0, short_acc * 100.0]
	if adjust_per > 1.5 and short_acc < 0.8:
		return "近距离微调不稳（每靶微调 %.1f 次且短距命中率仅 %.0f%%），准星抖动偏多——当前灵敏度可能偏高，建议调低 0.05~0.10 后重测对比。" % [adjust_per, short_acc * 100.0]
	return "各角度表现均衡（长距 %.0f%% / 短距 %.0f%%），当前灵敏度适配良好；如需精确最优值可运行 PSA 测试。" % [long_acc * 100.0, short_acc * 100.0]

# 与历史 PSA 推荐的灵敏度对比（records: 历史记录数组，找最近一条 PSA）
# 返回对比文本；无 PSA 历史时返回空串
static func compare_history_sens(cur_sens: float, records: Array) -> String:
	var best_ts := 0
	var rec: Dictionary = {}
	for r in records:
		var ts := int(r.get("ts", 0))
		if r.get("type", "") == "PSA" and ts > best_ts:
			best_ts = ts
			rec = r
	if rec.is_empty():
		return ""
	var hist := float(rec.get("sens", 0.0))
	if cur_sens > hist + 0.05:
		return "历史 PSA 测试推荐 %.2f，你当前测试 %.2f 偏高 —— 若感觉控制吃力可尝试调低。" % [hist, cur_sens]
	if cur_sens < hist - 0.05:
		return "历史 PSA 测试推荐 %.2f，你当前测试 %.2f 偏低 —— 若感觉拉枪费力可尝试调高。" % [hist, cur_sens]
	return "历史 PSA 测试推荐 %.2f，与当前测试一致，方向无误。" % hist

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
	lines.append("一次单击成功率 %.1f%% · 中位命中 %.2fs · 每靶微调 %.1f 次" % [
		float(metrics.accuracy) * 100.0,
		float(metrics.median_hit),
		float(metrics.get("micro_adjusts", 0)) / float(maxf(tg, 1)),
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
