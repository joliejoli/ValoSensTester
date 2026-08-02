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
# 平坦检测：两条判定（任一触发 → flat，推荐实测最高分点，避免探索偏好把推荐推到
# 任意位置，并标记 flat）：
#   1) 已测点得分范围 < σ_n(0.08)：全部实测挤在一起，无信号
#   2) GP 后验曲线信号强度（峰值-谷值均值）< σ_n：实测范围可能因噪声尖峰超阈值
#      （如 0.13），但模型拟合后曲线平坦（峰谷差仅 0.03），此时 EI 推荐点具有任意性
# 高原修正：GP 强平滑会把数据密集区（如 0.2~0.3）的真实差异抹平为一条平带
# （均值差 < 0.001 而实测差 0.05），此时峰值位置由浮点微差决定（假峰值）。
# 修正：GP 均值 ≥ 峰值-0.02 的区间视为"模型认可的高原"，在其中取实测得分
# 最高的数据点（数据直接证据）——孤立尖峰（平滑值显著低于峰值）自动排除，
# 有多个数据点支撑的高点（如 0.24 两轮 0.518/0.517）胜出
const PEAK_STEP := 0.001
# 边缘判定阈值：推荐点距灵敏度范围边界 < 0.1 时视为边缘推荐（GP 在边界外
# 无数据，无法区分"最优真在边缘"与"最优在范围外"，需提示用户扩大范围重测）
const EDGE_MARGIN := 0.1

func _edge_flag(sens: float) -> bool:
	return sens - _sens_min < EDGE_MARGIN or _sens_max - sens < EDGE_MARGIN

func best_estimate() -> Dictionary:
	if _bo.sample_count() == 0:
		var mid := (_sens_min + _sens_max) / 2.0
		return {"sens": mid, "mean": 0.0, "variance": 0.0, "flat": false, "edge": false}
	var ys: Array = _bo.ys
	var y_min := INF
	var y_max := -INF
	var best_x := 0.0
	var best_y := -INF
	for i in ys.size():
		var y := float(ys[i])
		y_min = minf(y_min, y)
		y_max = maxf(y_max, y)
		if y > best_y:
			best_y = y
			best_x = _bo.xs[i]
	if y_max - y_min < 0.08:
		return {"sens": best_x, "mean": best_y, "variance": 0.0, "flat": true, "edge": _edge_flag(best_x)}
	# 一次网格扫描完成信号强度判定 + 均值峰值定位（0.001 步长）
	var peak_x := 0.0
	var peak_y := -INF
	var trough := INF
	var x := _sens_min
	while x <= _sens_max + PEAK_STEP * 0.5:
		var p := _bo.predict(x)
		if p["mean"] > peak_y:
			peak_y = p["mean"]
			peak_x = x
		trough = minf(trough, p["mean"])
		x += PEAK_STEP
	if peak_y - trough < 0.08:
		return {"sens": best_x, "mean": best_y, "variance": 0.0, "flat": true, "edge": _edge_flag(best_x)}
	# 高原内实测最高数据点
	var plateau_best_x := -1.0
	var plateau_best_y := -INF
	for i in _bo.xs.size():
		if _bo.predict(_bo.xs[i])["mean"] >= peak_y - 0.02 and float(_bo.ys[i]) > plateau_best_y:
			plateau_best_y = float(_bo.ys[i])
			plateau_best_x = _bo.xs[i]
	if plateau_best_x >= 0.0:
		return {"sens": plateau_best_x, "mean": plateau_best_y, "variance": _bo.predict(plateau_best_x)["variance"], "flat": false, "edge": _edge_flag(plateau_best_x)}
	return {"sens": peak_x, "mean": peak_y, "variance": _bo.predict(peak_x)["variance"], "flat": false, "edge": _edge_flag(peak_x)}

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
