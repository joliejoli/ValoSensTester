extends Control

# Phase 5.1 结果页：推荐灵敏度 + 性能指标聚合 + 置信区间 + 自动保存历史（5.4）
# 指标聚合为静态函数，便于 headless 单测

const HistoryStore := preload("res://scripts/history_store.gd")
const TestMetrics := preload("res://scripts/test_metrics.gd")
const SceneNav := preload("res://scripts/scene_nav.gd")

@onready var rec_label: Label = %RecLabel
@onready var mode_label: Label = %ModeLabel
@onready var score_label: Label = %ScoreLabel
@onready var ci_label: Label = %CiLabel
@onready var dpi_label: Label = %DpiLabel
@onready var sample_label: Label = %SampleLabel
@onready var metric_accuracy: Label = %MetricAccuracy
@onready var metric_hit_time: Label = %MetricHitTime
@onready var metric_correct: Label = %MetricCorrect
@onready var metric_wasted: Label = %MetricWasted
@onready var metric_score: Label = %MetricScore
@onready var metric_rounds: Label = %MetricRounds
@onready var history_hint: Label = %HistoryHint

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
	metric_correct.text = "%.2fs" % m.median_correct
	metric_wasted.text = "%d" % m.wasted
	metric_score.text = "%.2f" % (float(s.get("score_mean", 0.0)) if not is_consistency else m.score)
	metric_rounds.text = "%d 轮" % rounds.size()
	_save_history(s, m, rounds, is_consistency)

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
