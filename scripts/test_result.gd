extends Control

# Phase 4 基础版结果展示（Phase 5 实现完整可视化）

@onready var rec_label: Label = %RecLabel
@onready var mode_label: Label = %ModeLabel
@onready var score_label: Label = %ScoreLabel
@onready var dpi_label: Label = %DpiLabel
@onready var sample_label: Label = %SampleLabel

func _ready() -> void:
	var s: Dictionary = TestConfig.opt_summary
	if s.is_empty():
		rec_label.text = "--"
		mode_label.text = "无优化数据（异常退出）"
		return
	rec_label.text = "%.2f" % float(s.get("best_sens", 0.0))
	if s.get("is_consistency", false):
		mode_label.text = s.get("mode_label", "")
		score_label.text = "固定灵敏度测试 · %d 轮" % int(s.get("samples", 0))
	else:
		mode_label.text = "%s · 预估得分 %.2f" % [s.get("mode_label", ""), float(s.get("score_mean", 0.0))]
		score_label.text = "95%% 置信区间 %.2f ~ %.2f" % [float(s.get("score_low", 0.0)), float(s.get("score_high", 0.0))]
	dpi_label.text = "测试时 DPI %d · 对应 eDPI ≈ %d（参考 800 DPI 时 %.1f cm/360°）" % [
		int(s.get("dpi", 0)),
		int(s.get("edpi", 0)),
		_edpi_to_cm(float(s.get("edpi", 0.0))),
	]
	sample_label.text = "已采集 %d 轮数据" % int(s.get("samples", 0))

func _edpi_to_cm(edpi: float) -> float:
	if edpi <= 0.0:
		return 0.0
	# cm/360° = (360 / (0.07 × sens)) × 2.54 / dpi = 914.4 / (0.07 × edpi)
	return 914.4 / (0.07 * edpi)
