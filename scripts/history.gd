extends Control

# Phase 5.4 历史记录：列表查看 / 类型筛选 / 详情弹窗 / 导出 JSON / 删除

const HistoryStore := preload("res://scripts/history_store.gd")

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
@onready var detail_rows: VBoxContainer = %DetailRows

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
	sens.text = "灵敏度 %.2f" % float(rec.get("sens", 0.0))
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
	detail_metrics.text = "综合评分 %.2f（95%% CI %.2f~%.2f）\n命中率 %.1f%% · 中位命中 %.2fs · 中位修正 %.2fs · 多余开火 %d" % [
		float(rec.get("score_mean", 0.0)),
		float(rec.get("score_low", 0.0)),
		float(rec.get("score_high", 0.0)),
		float(m.get("accuracy", 0.0)) * 100.0,
		float(m.get("median_hit", 0.0)),
		float(m.get("median_correct", 0.0)),
		int(m.get("wasted", 0)),
	]
	for child in detail_rows.get_children():
		child.queue_free()
	var rounds: Array = rec.get("round_results", [])
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	for text in ["轮次", "灵敏度", "命中率", "命中耗时(s)", "修正(s)", "多余开火"]:
		var lab := Label.new()
		lab.text = text
		lab.custom_minimum_size = Vector2(120, 0)
		lab.modulate = Color(1, 0.27451, 0.333333)
		header.add_child(lab)
	detail_rows.add_child(header)
	for r in rounds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var targets := int(r.get("targets_done", 0))
		var hit_times: Array = r.get("hit_times", [])
		var corrections: Array = r.get("correction_times", [])
		for text in [
			"%d" % int(r.get("round", 0)),
			"%.2f" % float(r.get("sens", 0.0)),
			"%d/%d" % [int(r.get("hits", 0)), targets],
			"%.2f" % _median(hit_times),
			"%.2f" % _median(corrections),
			"%d" % int(r.get("overshoots", 0)),
		]:
			var lab := Label.new()
			lab.text = text
			lab.custom_minimum_size = Vector2(120, 0)
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

func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if detail_popup.visible:
			detail_popup.visible = false
