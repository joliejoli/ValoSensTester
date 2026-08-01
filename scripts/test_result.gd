extends Control

# Phase 5.1 结果页：推荐灵敏度 + 性能指标聚合 + 置信区间 + 自动保存历史（5.4）
# Phase 5.2/5.3 详细报告弹窗：GP 曲线 + 命中率/学习曲线 + 对比表 + 建议 + 分享文本

const HistoryStore := preload("res://scripts/history_store.gd")
const TestMetrics := preload("res://scripts/test_metrics.gd")
const Objective := preload("res://scripts/test_objective.gd")
const TestPlan := preload("res://scripts/test_plan.gd")
const Advice := preload("res://scripts/advice.gd")
const Chart := preload("res://scripts/chart.gd")
const SceneNav := preload("res://scripts/scene_nav.gd")

@onready var rec_label: Label = %RecLabel
@onready var mode_label: Label = %ModeLabel
@onready var score_label: Label = %ScoreLabel
@onready var ci_label: Label = %CiLabel
@onready var flat_label: Label = %FlatLabel
@onready var dpi_label: Label = %DpiLabel
@onready var sample_label: Label = %SampleLabel
@onready var metric_accuracy: Label = %MetricAccuracy
@onready var metric_hit_time: Label = %MetricHitTime
@onready var metric_correct: Label = %MetricCorrect
@onready var metric_wasted: Label = %MetricWasted
@onready var metric_wasted_key: Label = %MetricWastedKey
@onready var metric_score: Label = %MetricScore
@onready var metric_rounds: Label = %MetricRounds
@onready var history_hint: Label = %HistoryHint
@onready var report_popup: Control = %ReportPopup
@onready var charts_box: VBoxContainer = %ChartsBox
@onready var table_box: VBoxContainer = %TableBox
@onready var share_hint: Label = %ShareHint

var _share_metrics: Dictionary = {}
var _share_problems: Array = []
var _share_advice: Array = []

func _ready() -> void:
	var s: Dictionary = TestConfig.opt_summary
	var rounds: Array = TestConfig.round_results
	if s.is_empty() or rounds.is_empty():
		rec_label.text = "--"
		mode_label.text = "无优化数据（异常退出）"
		return
	var is_consistency: bool = s.get("is_consistency", false)
	rec_label.text = "%.2f" % float(s.get("best_sens", 0.0))
	if is_consistency:
		mode_label.text = s.get("mode_label", "")
		score_label.text = "固定灵敏度测试 · %d 轮" % int(s.get("samples", 0))
		ci_label.text = "推荐灵敏度即测试灵敏度"
	else:
		mode_label.text = "%s · 预估得分 %.2f" % [s.get("mode_label", ""), float(s.get("score_mean", 0.0))]
		score_label.text = "推荐灵敏度 %.2f" % float(s.get("best_sens", 0.0))
		if s.get("flat", false):
			ci_label.text = "各灵敏度得分差异小于测量噪声（平坦曲线）"
			flat_label.text = "提示：不同灵敏度表现接近，推荐值为已测最高分点，也可按手感选择任意舒适灵敏度"
		else:
			ci_label.text = "得分 95%% 置信区间 %.2f ~ %.2f" % [float(s.get("score_low", 0.0)), float(s.get("score_high", 0.0))]
	var edpi := float(s.get("edpi", 0.0))
	dpi_label.text = "测试时 DPI %d · eDPI ≈ %d（参考 800 DPI 时 %.1f cm/360°）" % [
		int(s.get("dpi", 0)),
		int(edpi),
		_edpi_to_cm(edpi),
	]
	sample_label.text = "已采集 %d 轮数据" % int(s.get("samples", 0))
	var m := TestMetrics.aggregate(rounds)
	metric_accuracy.text = "%.1f%%" % (m.accuracy * 100.0)
	metric_hit_time.text = "%.2fs" % m.median_hit
	var total_targets := 0
	for r in rounds:
		total_targets += int(r.get("targets_done", 0))
	metric_correct.text = "%.1f" % (float(m.micro_adjusts) / float(maxf(total_targets, 1))) if total_targets > 0 else "--"
	# 第 4 格：有跟枪数据（移动靶/追踪）显示跟枪精度，否则显示一次定位率
	if float(m.track_accuracy) >= 0.0:
		metric_wasted_key.text = "跟枪精度（准星停留命中区）"
		metric_wasted.text = "%.1f%%" % (m.track_accuracy * 100.0)
	else:
		metric_wasted_key.text = "一次定位率（第一枪命中）"
		metric_wasted.text = "%.1f%%" % (m.first_shot_rate * 100.0)
	metric_score.text = "%.2f" % (float(s.get("score_mean", 0.0)) if not is_consistency else m.score)
	metric_rounds.text = "%d 轮" % rounds.size()
	_build_page_chart()
	_build_page_advice()
	_save_history(s, m, rounds, is_consistency)

# ---------- 结果页直接展示：得分曲线 + 分析与建议 ----------

func _build_page_chart() -> void:
	for c in %PageChartBox.get_children():
		c.queue_free()
	var rounds: Array = TestConfig.round_results
	var is_consistency: bool = TestConfig.opt_summary.get("is_consistency", false)
	var c1 := Chart.new()
	c1.title = "灵敏度-综合评分（阴影 = 95% 置信区间）"
	c1.y_limits = Vector2(0, 1)
	c1.custom_minimum_size = Vector2(0, 160)
	if not is_consistency and not rounds.is_empty():
		# x 轴固定为灵敏度配置范围（折线位置符合预期，与轴标签对应）
		c1.x_limits = Vector2(TestConfig.sens_min, TestConfig.sens_max)
		var curve := _gp_curve(rounds)
		c1.add_band(curve["upper"], curve["lower"], Color(1, 0.368627, 0.4), "95% CI")
		c1.add_series(curve["mean"], Color(1, 0.7, 0.72), "GP 后验")
		c1.add_series(curve["obs"], Color(0.95, 0.95, 0.95), "实测")
	else:
		var pts: Array = []
		for i in rounds.size():
			pts.append(Vector2(i + 1, _round_score(rounds[i])))
		c1.title = "各轮得分（一致性测试）"
		c1.add_series(pts, Color(0.6, 0.95, 0.7), "得分")
	%PageChartBox.add_child(c1)

func _build_page_advice() -> void:
	for c in %PageAdviceBox.get_children():
		c.queue_free()
	for ctrl in _make_advice_controls():
		%PageAdviceBox.add_child(ctrl)
	# 分享卡片数据与结果页建议同源
	var metrics := TestMetrics.aggregate(TestConfig.round_results)
	_share_metrics = metrics
	_share_problems = Advice.diagnose(metrics, TestConfig.round_results)
	_share_advice = Advice.train_advice(_share_problems)

func _make_advice_controls() -> Array:
	var rounds: Array = TestConfig.round_results
	var s: Dictionary = TestConfig.opt_summary
	var metrics := TestMetrics.aggregate(rounds)
	var problems := Advice.diagnose(metrics, rounds)
	var advice := Advice.train_advice(problems)
	var out: Array = []
	if problems.is_empty():
		out.append(_mk_label("未识别出明显问题：表现均衡，可在推荐灵敏度下继续巩固手感。", 0.85, false))
	else:
		for p in problems:
			out.append(_mk_label("• %s" % p["title"], 1.0, true))
			out.append(_mk_label(p["detail"], 0.8, false))
		out.append(HSeparator.new())
	for a in advice:
		out.append(_mk_label("训练建议：%s" % a, 0.95, false))
	out.append(_mk_label(Advice.grip_advice(float(s.get("best_sens", 0.0))), 0.72, false))
	return out

func _mk_label(text: String, alpha: float, red: bool) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.modulate = Color(1, 0.368627, 0.4, alpha) if red else Color(0.92549, 0.909804, 0.882353, alpha)
	return lab

# GP 后验曲线（公共）：供结果页与详细报告弹窗使用
func _gp_curve(rounds: Array) -> Dictionary:
	var min_s := 1.0
	var max_s := 0.0
	for r in rounds:
		min_s = minf(min_s, float(r.get("sens", 0.0)))
		max_s = maxf(max_s, float(r.get("sens", 0.0)))
	min_s = maxf(min_s - 0.05, 0.05)
	max_s = minf(max_s + 0.05, 0.95)
	var grid: Array = []
	var x := min_s
	while x <= max_s + 0.001:
		grid.append(x)
		x += 0.02
	var plan := TestPlan.new()
	plan.begin(false, min_s, max_s, rounds.size())
	for r in rounds:
		plan.add_result(r)
	var preds := plan.gp_predictions(grid)
	var upper: Array = []
	var lower: Array = []
	var mean: Array = []
	for p in preds:
		var sd := sqrt(maxf(p["variance"], 0.0))
		upper.append(Vector2(p["x"], clampf(p["mean"] + 1.96 * sd, 0.0, 1.0)))
		lower.append(Vector2(p["x"], clampf(p["mean"] - 1.96 * sd, 0.0, 1.0)))
		mean.append(Vector2(p["x"], clampf(p["mean"], 0.0, 1.0)))
	var obs: Array = []
	for r in rounds:
		obs.append(Vector2(float(r.get("sens", 0.0)), _round_score(r)))
	return {"upper": upper, "lower": lower, "mean": mean, "obs": obs}

func _save_history(s: Dictionary, m: Dictionary, rounds: Array, is_consistency: bool) -> void:
	var mean_score: float = m.score if is_consistency else float(s.get("score_mean", m.score))
	HistoryStore.save_record({
		"ts": int(Time.get_unix_time_from_system()),
		"type": "CONSISTENCY" if is_consistency else "PSA",
		"sens": float(s.get("best_sens", 0.0)),
		"dpi": int(s.get("dpi", 0)),
		"edpi": int(s.get("edpi", 0)),
		"score_mean": mean_score,
		"score_low": float(s.get("score_low", 0.0)),
		"score_high": float(s.get("score_high", 0.0)),
		"mode_label": s.get("mode_label", ""),
		"rounds": rounds.size(),
		"metrics": m,
		"round_results": rounds,
	})
	history_hint.text = "本次结果已保存至历史记录"

func _on_history_button_pressed() -> void:
	SceneNav.go("res://history.tscn", self)

func _edpi_to_cm(edpi: float) -> float:
	if edpi <= 0.0:
		return 0.0
	return 914.4 / (0.07 * edpi)

# ---------- Phase 5.2/5.3 详细报告 ----------

func _on_report_button_pressed() -> void:
	_build_charts()
	_build_table()
	report_popup.visible = true

func _round_score(r: Dictionary) -> float:
	return Objective.score(r)

func _build_charts() -> void:
	for c in charts_box.get_children():
		c.queue_free()
	var rounds: Array = TestConfig.round_results
	var is_consistency: bool = TestConfig.opt_summary.get("is_consistency", false)
	# 1) 灵敏度-综合评分：GP 后验均值 + 95% CI 带 + 实测散点
	var c1 := Chart.new()
	c1.title = "灵敏度-综合评分（GP 后验，阴影 = 95% CI）"
	c1.y_limits = Vector2(0, 1)
	c1.custom_minimum_size = Vector2(0, 190)
	if not is_consistency and not rounds.is_empty():
		var curve := _gp_curve(rounds)
		c1.add_band(curve["upper"], curve["lower"], Color(1, 0.368627, 0.4), "95% CI")
		c1.add_series(curve["mean"], Color(1, 0.7, 0.72), "GP 后验")
		c1.add_series(curve["obs"], Color(0.95, 0.95, 0.95), "实测")
	charts_box.add_child(c1)
	# 2) 灵敏度-命中率
	var c2 := Chart.new()
	c2.title = "灵敏度-命中率"
	c2.y_limits = Vector2(0, 1)
	if not is_consistency:
		c2.x_limits = Vector2(TestConfig.sens_min, TestConfig.sens_max)
	c2.custom_minimum_size = Vector2(0, 150)
	var acc_pts: Array = []
	for r in rounds:
		var td := int(r.get("targets_done", 0))
		acc_pts.append(Vector2(float(r.get("sens", 0.0)), float(int(r.get("hits", 0))) / float(td) if td > 0 else 0.0))
	c2.add_series(acc_pts, Color(0.6, 0.85, 1), "命中率")
	charts_box.add_child(c2)
	# 3) 学习曲线（轮次-得分）
	var c3 := Chart.new()
	c3.title = "学习曲线（轮次-得分）"
	c3.y_auto = true
	c3.custom_minimum_size = Vector2(0, 150)
	var lc: Array = []
	for i in rounds.size():
		lc.append(Vector2(i + 1, _round_score(rounds[i])))
	c3.add_series(lc, Color(0.6, 0.95, 0.7), "得分")
	charts_box.add_child(c3)

func _build_table() -> void:
	for c in table_box.get_children():
		c.queue_free()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	for text in ["轮次", "灵敏度", "命中率", "中位耗时(s)", "修正(s)", "得分"]:
		var lab := Label.new()
		lab.text = text
		lab.custom_minimum_size = Vector2(100, 0)
		lab.modulate = Color(1, 0.27451, 0.333333)
		header.add_child(lab)
	table_box.add_child(header)
	for r in TestConfig.round_results:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var td := int(r.get("targets_done", 0))
		var cells := [
			"%d" % int(r.get("round", 0)),
			"%.2f" % float(r.get("sens", 0.0)),
			"%d/%d" % [int(r.get("hits", 0)), td],
			"%.2f" % TestMetrics.median(r.get("hit_times", [])),
			"%.2f" % TestMetrics.median(r.get("correction_times", [])),
			"%.2f" % _round_score(r),
		]
		for text in cells:
			var lab := Label.new()
			lab.text = text
			lab.custom_minimum_size = Vector2(100, 0)
			row.add_child(lab)
		table_box.add_child(row)

func _on_share_pressed() -> void:
	var s: Dictionary = TestConfig.opt_summary
	var text := Advice.share_text(s, _share_metrics, _share_problems, _share_advice,
		TestConfig.round_results, Advice.grip_advice(float(s.get("best_sens", 0.0))))
	DisplayServer.clipboard_set(text)
	share_hint.text = "已复制到剪贴板"

func _on_report_tab_changed(index: int) -> void:
	%PanelCharts.visible = index == 0
	%PanelTable.visible = index == 1

func _on_close_report_pressed() -> void:
	report_popup.visible = false
