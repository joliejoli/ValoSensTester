extends RefCounted
# 测试灵敏度策略（Phase 4）
# PSA 模式：冷启动粗扫 COARSE_SAMPLES 个等分点（随机顺序消除轮序混杂）→ BO 选点
#   探索/利用：BO 阶段前 40% 用 UCB(κ=2.0)，之后用 EI
# Consistency 模式：固定单点（直通原逻辑）
# 轮数 < 粗扫点数时退化为等分采样
# 注意：不直接引用 TestConfig（headless --script 编译期不可用），参数由调用方传入

const BayesOpt := preload("res://scripts/bayes_opt.gd")
const Objective := preload("res://scripts/test_objective.gd")

const COARSE_SAMPLES := 4
const GRID_STEP := 0.01
const EXPLORE_RATIO := 0.4
const UCB_KAPPA := 2.0

var _bo: BayesOpt
var _coarse_points: Array[float] = []
var _is_consistency := false
var _sens_min := 0.1
var _sens_max := 0.9
var _rounds := 10

func begin(p_consistency: bool, p_sens_min: float, p_sens_max: float, p_rounds: int) -> void:
	_is_consistency = p_consistency
	_sens_min = p_sens_min
	_sens_max = p_sens_max
	_rounds = p_rounds
	_bo = BayesOpt.new()
	_coarse_points = _make_coarse_points()

func _make_coarse_points() -> Array[float]:
	var n := mini(COARSE_SAMPLES, _rounds)
	var points: Array[float] = []
	if n <= 1:
		return points
	for i in n:
		points.append(lerpf(_sens_min, _sens_max, float(i + 1) / float(n + 1)))
	points.shuffle()
	return points

# 返回第 round_index 轮（0 起）的灵敏度
func next_sens(round_index: int) -> float:
	if _is_consistency or _rounds <= 1:
		return (_sens_min + _sens_max) / 2.0
	if round_index < _coarse_points.size():
		return _coarse_points[round_index]
	# BO 阶段：候选排除已测点邻域，避免连续重复测试同一灵敏度（EI 收敛会反复建议最优点）
	var candidates := _candidates(true)
	if candidates.is_empty():
		candidates = _candidates(false)
	if candidates.is_empty():
		return lerpf(_sens_min, _sens_max, 0.5)
	var bo_round := round_index - _coarse_points.size()
	var total_bo := maxf(_rounds - _coarse_points.size(), 1)
	var use_ucb := float(bo_round) / float(total_bo) < EXPLORE_RATIO
	var mode := BayesOpt.MODE_UCB if use_ucb else BayesOpt.MODE_EI
	return _bo.suggest(candidates, mode, UCB_KAPPA)["x"]

# 轮结束回报数据（PSA 模式计入优化器）
func add_result(round_data: Dictionary) -> void:
	if _is_consistency:
		return
	var sens := float(round_data.get("sens", 0.0))
	if sens > 0.0:
		_bo.add_sample(sens, Objective.score(round_data))

# GP 预测当前最佳灵敏度（测试结束调用，未采样时返回中点）
func best_estimate() -> Dictionary:
	if _bo.sample_count() == 0:
		var mid := (_sens_min + _sens_max) / 2.0
		return {"sens": mid, "mean": 0.0, "variance": 0.0}
	var candidates := _candidates()
	var rec: Dictionary = _bo.suggest(candidates, BayesOpt.MODE_EI, UCB_KAPPA)
	return {"sens": rec["x"], "mean": rec["mean"], "variance": rec["variance"]}

# GP 后验曲线（Phase 5.2 曲线图用）：points 为灵敏度数组，返回 [{x, mean, variance}]
func gp_predictions(points: Array) -> Array:
	var out: Array = []
	for p in points:
		var pred := _bo.predict(float(p))
		out.append({"x": float(p), "mean": pred["mean"], "variance": pred["variance"]})
	return out

func _candidates(exclude_tested: bool = false) -> Array:
	var out: Array[float] = []
	var x := _sens_min
	while x <= _sens_max + GRID_STEP * 0.5:
		var xc := snappedf(x, GRID_STEP)
		if not exclude_tested or not _bo.has_tested_near(xc, 0.03):
			out.append(xc)
		x += GRID_STEP
	return out
