extends Control

# Phase 5.4 历史记录：列表查看 / 类型筛选 / 详情弹窗 / 导出 JSON / 删除

const HistoryStore := preload("res://scripts/history_store.gd")
const Chart := preload("res://scripts/chart.gd")
const TestMetrics := preload("res://scripts/test_metrics.gd")

const TYPE_LABEL := {
	"PSA": "灵敏度测试",
	"CONSISTENCY": "一致性测试",
}

@onready var list_box: VBoxContainer = %ListBox
@onready var filter_option: OptionButton = %FilterOption
@onready var empty_label: Label = %EmptyLabel
@onready var count_label: Label = %CountLabel
@onready var detail_popup: Control = %DetailPopup
@onready var detail_rec: Label = %DetailRec
@onready var detail_meta: Label = %DetailMeta
@onready var detail_metrics: Label = %DetailMetrics
@onready var detail_compare: Label = %DetailCompare
@onready var detail_rows: VBoxContainer = %DetailRows
@onready var trend_popup: Control = %TrendPopup
@onready var trend_box: VBoxContainer = %TrendBox

var _records: Array = []
var _filter := "ALL"

func _ready() -> void:
	_records = HistoryStore.load_records()
	_rebuild()

func _rebuild() -> void:
	for child in list_box.get_children():
		if child == empty_label:
			continue
		child.queue_free()
	var shown := 0
	for rec in _records:
		if _filter != "ALL" and rec.get("type", "") != _filter:
			continue
		shown += 1
		list_box.add_child(_make_row(rec))
	empty_label.visible = shown == 0
	count_label.text = "共 %d 条记录" % shown

func _make_row(rec: Dictionary) -> Control:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)
	var date := Label.new()
	date.text = HistoryStore.format_date(int(rec.get("ts", 0)))
	date.custom_minimum_size = Vector2(150, 0)
	date.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(date)
	var type := Label.new()
	type.text = TYPE_LABEL.get(rec.get("type", ""), rec.get("type", ""))
	type.custom_minimum_size = Vector2(110, 0)
	type.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type.modulate = Color(1, 0.368627, 0.4) if rec.get("type", "") == "PSA" else Color(0.6, 0.85, 1)
	hbox.add_child(type)
	var sens := Label.new()
	sens.text = "灵敏度 %.3f" % float(rec.get("sens", 0.0))
	sens.custom_minimum_size = Vector2(140, 0)
	sens.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(sens)
	var score := Label.new()
	score.text = "得分 %.2f" % float(rec.get("score_mean", 0.0))
	score.custom_minimum_size = Vector2(110, 0)
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(score)
	var rounds := Label.new()
	rounds.text = "%d 轮" % int(rec.get("rounds", 0))
	rounds.custom_minimum_size = Vector2(70, 0)
	rounds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(rounds)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	var detail_btn := Button.new()
	detail_btn.text = "详情"
	detail_btn.custom_minimum_size = Vector2(90, 40)
	detail_btn.pressed.connect(_show_detail.bind(rec))
	hbox.add_child(detail_btn)
	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.custom_minimum_size = Vector2(90, 40)
	del_btn.pressed.connect(_delete_record.bind(int(rec.get("ts", 0))))
	hbox.add_child(del_btn)
	return row

func _show_detail(rec: Dictionary) -> void:
	detail_rec.text = "推荐灵敏度 %.2f · %s" % [float(rec.get("sens", 0.0)), TYPE_LABEL.get(rec.get("type", ""), "")]
	var edpi := int(rec.get("edpi", 0))
	detail_meta.text = "%s · DPI %d · eDPI %d · %d 轮" % [
		HistoryStore.format_date(int(rec.get("ts", 0))),
		int(rec.get("dpi", 0)),
		edpi,
		int(rec.get("rounds", 0)),
	]
	var m: Dictionary = rec.get("metrics", {})
	var rounds: Array = rec.get("round_results", [])
	var total_targets := 0
	for r in rounds:
		total_targets += int(r.get("targets_done", 0))
	detail_metrics.text = "综合评分 %.2f（95%% CI %.2f~%.2f）\n成功率 %.1f%% · 中位命中 %.2fs · 每靶微调 %.1f 次" % [
		float(rec.get("score_mean", 0.0)),
		float(rec.get("score_low", 0.0)),
		float(rec.get("score_high", 0.0)),
		float(m.get("accuracy", 0.0)) * 100.0,
		float(m.get("median_hit", 0.0)),
		float(m.get("micro_adjusts", 0)) / float(maxf(total_targets, 1)),
	]
	for child in detail_rows.get_children():
		child.queue_free()
	# 与上一次同类型测试对比（附录 D P2）
	detail_compare.text = _compare_text(rec)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	for text in ["轮次", "灵敏度", "成功率", "命中耗时(s)", "失败点击", "超时"]:
		var lab := Label.new()
		lab.text = text
		lab.custom_minimum_size = Vector2(130, 0)
		lab.modulate = Color(1, 0.27451, 0.333333)
		header.add_child(lab)
	detail_rows.add_child(header)
	for r in rounds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var targets := int(r.get("targets_done", 0))
		var hit_times: Array = r.get("hit_times", [])
		var hits := int(r.get("hits", 0))
		for text in [
			"%d" % int(r.get("round", 0)),
			"%.2f" % float(r.get("sens", 0.0)),
			"%.0f%%" % (100.0 * float(hits) / float(maxf(targets, 1))),
			"%.2f" % TestMetrics.median(hit_times),
			"%d" % int(r.get("misses", 0)),
			"%d" % int(r.get("expired_angles", []).size()),
		]:
			var lab := Label.new()
			lab.text = text
			lab.custom_minimum_size = Vector2(130, 0)
			row.add_child(lab)
		detail_rows.add_child(row)
	detail_popup.visible = true

func _delete_record(ts: int) -> void:
	HistoryStore.delete_record(ts)
	_records = HistoryStore.load_records()
	_rebuild()

func _on_filter_changed(index: int) -> void:
	_filter = ["ALL", "PSA", "CONSISTENCY"][index]
	_rebuild()

func _on_close_detail_pressed() -> void:
	detail_popup.visible = false

func _on_export_pressed() -> void:
	var text := JSON.stringify({"version": 1, "records": _records}, "  ")
	DisplayServer.clipboard_set(text)
	count_label.text = "JSON 已复制到剪贴板（%d 条）" % _records.size()

func _on_clear_all_pressed() -> void:
	HistoryStore.clear_all()
	_records = []
	_rebuild()

# 趋势弹窗：灵敏度 / 得分随时间（按记录先后）变化（Phase 5.4）
func _on_trend_pressed() -> void:
	for c in trend_box.get_children():
		c.queue_free()
	var recs := _records.duplicate()
	recs.sort_custom(func(a, b): return int(a["ts"]) < int(b["ts"]))
	var sens_pts: Array = []
	var score_pts: Array = []
	var i := 0
	for r in recs:
		sens_pts.append(Vector2(i, float(r.get("sens", 0.0))))
		score_pts.append(Vector2(i, float(r.get("score_mean", 0.0))))
		i += 1
	var c1 := Chart.new()
	c1.title = "推荐灵敏度变化趋势（第 %d 次 ~ 第 %d 次）" % [1, maxf(recs.size(), 1)]
	c1.y_auto = true
	c1.custom_minimum_size = Vector2(0, 210)
	c1.add_series(sens_pts, Color(1, 0.368627, 0.4), "灵敏度")
	trend_box.add_child(c1)
	var c2 := Chart.new()
	c2.title = "综合得分变化趋势"
	c2.y_auto = true
	c2.custom_minimum_size = Vector2(0, 210)
	c2.add_series(score_pts, Color(0.6, 0.95, 0.7), "得分")
	trend_box.add_child(c2)
	trend_popup.visible = true

func _on_close_trend_pressed() -> void:
	trend_popup.visible = false

# 与上一次同类型测试的对比文本（灵敏度/得分/命中率/每靶微调，↑↓→ 标注变化）
func _compare_text(rec: Dictionary) -> String:
	var cur_ts := int(rec.get("ts", 0))
	var prev_ts := 0
	var prev: Dictionary = {}
	for other in _records:
		var ot := int(other.get("ts", 0))
		if other.get("type", "") == rec.get("type", "") and ot < cur_ts and ot > prev_ts:
			prev_ts = ot
			prev = other
	if prev.is_empty():
		return "（这是同类型测试的第一条记录，暂无对比）"
	var prev_m: Dictionary = prev.get("metrics", {})
	var cur_m: Dictionary = rec.get("metrics", {})
	var prev_targets := 0
	var cur_targets := 0
	for r in prev.get("round_results", []):
		prev_targets += int(r.get("targets_done", 0))
	for r in rec.get("round_results", []):
		cur_targets += int(r.get("targets_done", 0))
	return "对比上一次 %s（%s）：\n灵敏度 %s · 得分 %s · 命中率 %s · 每靶微调 %s" % [
		TYPE_LABEL.get(rec.get("type", ""), ""),
		HistoryStore.format_date(prev_ts),
		_arrow(float(prev.get("sens", 0.0)), float(rec.get("sens", 0.0)), "%.2f"),
		_arrow(float(prev.get("score_mean", 0.0)), float(rec.get("score_mean", 0.0)), "%.2f"),
		_arrow(float(prev_m.get("accuracy", 0.0)) * 100.0, float(cur_m.get("accuracy", 0.0)) * 100.0, "%.1f%%"),
		_arrow(
			float(prev_m.get("micro_adjusts", 0)) / float(maxf(prev_targets, 1)),
			float(cur_m.get("micro_adjusts", 0)) / float(maxf(cur_targets, 1)),
			"%.1f"),
	]

# 变化箭头：本次 < 上次 → ↓，本次 > 上次 → ↑，接近 → →（微调次数是越低越好，单独反转）
static func _arrow(prev: float, cur: float, fmt: String) -> String:
	var diff := cur - prev
	var arrow := "→"
	if absf(diff) > 0.005:
		arrow = "↑" if diff > 0.0 else "↓"
	return "%s %s" % [fmt % cur, arrow]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if detail_popup.visible:
			detail_popup.visible = false
		elif trend_popup.visible:
			trend_popup.visible = false
