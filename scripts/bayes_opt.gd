extends RefCounted
# 贝叶斯优化器（Phase 4）：高斯过程回归 + EI/UCB 采集函数
# 单变量（灵敏度），样本量 ≤ 30，直接法求逆

const MODE_UCB := 0
const MODE_EI := 1

# 核参数
var length_scale := 0.2
var signal_variance := 1.0
var noise_variance := 0.0144  # σ_n = 0.12，单轮得分噪声（信度评估结论）

var xs: Array[float] = []
var ys: Array[float] = []
var y_mean := 0.0

var _kernel_inv: Array = []
var _kernel_det := 0.0
var _trained := false

func add_sample(x: float, y: float) -> void:
	xs.append(x)
	ys.append(y)
	_trained = false

func sample_count() -> int:
	return xs.size()

# 是否已有样本点落在 x 的 eps 邻域内
func has_tested_near(x: float, eps: float) -> bool:
	for xi in xs:
		if absf(xi - x) <= eps:
			return true
	return false

func _train() -> void:
	var n := xs.size()
	y_mean = 0.0
	for y in ys:
		y_mean += y
	if n > 0:
		y_mean /= float(n)
	# 信号方差按数据尺度自适应（复审 P1-1）：score 实测方差仅 ~0.03-0.05，
	# 固定 1.0 会让置信区间被高估 4-5 倍（EI/UCB 过度探索、结果页 CI 过宽）
	if n > 1:
		var var_y := 0.0
		for y in ys:
			var d := y - y_mean
			var_y += d * d
		signal_variance = maxf(var_y / float(n - 1), 0.001)
	var k: Array = []
	k.resize(n)
	for i in n:
		var row: Array = []
		row.resize(n)
		for j in n:
			var v := _kernel(xs[i], xs[j])
			if i == j:
				v += noise_variance
			row[j] = v
		k[i] = row
	_kernel_inv = _invert(k)
	_trained = true

# 中心化后的目标值
func _y_centered(i: int) -> float:
	return ys[i] - y_mean

# RBF 核
func _kernel(a: float, b: float) -> float:
	var d := a - b
	return signal_variance * exp(-(d * d) / (2.0 * length_scale * length_scale))

# 预测均值和方差
func predict(x: float) -> Dictionary:
	if xs.is_empty():
		return {"mean": 0.0, "variance": signal_variance}
	if not _trained:
		_train()
	var k_star: Array = []
	for xi in xs:
		k_star.append(_kernel(xi, x))
	var w := _matvec(_kernel_inv, k_star)
	var mean := y_mean
	for i in xs.size():
		mean += w[i] * _y_centered(i)
	var variance := _kernel(x, x) + noise_variance
	for i in xs.size():
		variance -= w[i] * k_star[i]
	return {"mean": mean, "variance": maxf(variance, 1e-9)}

# 候选网格上采集最优建议点
# candidates: 灵敏度候选数组；mode: MODE_UCB / MODE_EI
# explore: UCB 的 κ 参数；xi: EI 的探索项
func suggest(candidates: Array, mode: int, explore: float = 2.0, xi: float = 0.01) -> Dictionary:
	if xs.is_empty():
		var best: Dictionary = {}
		for c in candidates:
			if best.is_empty() or c < best["x"]:
				best = {"x": c, "mean": 0.0, "variance": 0.0}
		return best
	var best: Dictionary = {}
	var y_best := -INF
	for i in xs.size():
		if _y_centered(i) + y_mean > y_best:
			y_best = _y_centered(i) + y_mean
	for c in candidates:
		var p := predict(c)
		var score := 0.0
		if mode == MODE_UCB:
			score = p["mean"] + explore * sqrt(p["variance"])
		else:
			score = _ei(p["mean"], p["variance"], y_best, xi)
		if best.is_empty() or score > best["score"]:
			best = {"x": c, "mean": p["mean"], "variance": p["variance"], "score": score}
	return best

# Expected Improvement
func _ei(mean: float, variance: float, y_best: float, xi: float) -> float:
	var sigma := sqrt(variance)
	if sigma < 1e-9:
		return 0.0
	var z := (mean - y_best - xi) / sigma
	return (mean - y_best - xi) * _norm_cdf(z) + sigma * _norm_pdf(z)

static func _norm_pdf(z: float) -> float:
	return exp(-0.5 * z * z) / sqrt(2.0 * PI)

static func _norm_cdf(z: float) -> float:
	return 0.5 * (1.0 + _erf(z / sqrt(2.0)))

# erf 近似（Abramowitz & Stegun 7.1.26，精度 ~1.5e-7）
static func _erf(x: float) -> float:
	var sign := 1.0
	var ax := x
	if x < 0.0:
		sign = -1.0
		ax = -x
	var t := 1.0 / (1.0 + 0.5 * ax)
	var poly := t * exp(-ax * ax - 1.26551223 + t * (1.00002368 + t * (0.37409196 \
		+ t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 \
		+ t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))))
	return sign * (1.0 - poly)

static func _matvec(m: Array, v: Array) -> Array:
	var n := m.size()
	var out: Array = []
	out.resize(n)
	for i in n:
		var acc := 0.0
		var row: Array = m[i]
		for j in n:
			acc += row[j] * v[j]
		out[i] = acc
	return out

# 高斯消元求逆（n ≤ 30）
static func _invert(a: Array) -> Array:
	var n := a.size()
	var m: Array = []
	m.resize(n)
	for i in n:
		var row: Array = []
		row.resize(n)
		for j in n:
			row[j] = a[i][j]
		m[i] = row
	var inv: Array = []
	inv.resize(n)
	for i in n:
		var row: Array = []
		row.resize(n)
		for j in n:
			row[j] = 1.0 if i == j else 0.0
		inv[i] = row
	for col in n:
		var pivot := col
		for r in range(col + 1, n):
			if absf(m[r][col]) > absf(m[pivot][col]):
				pivot = r
		var tmp: Array = m[col]
		m[col] = m[pivot]
		m[pivot] = tmp
		tmp = inv[col]
		inv[col] = inv[pivot]
		inv[pivot] = tmp
		var diag: float = m[col][col]
		for j in n:
			m[col][j] /= diag
			inv[col][j] /= diag
		for r in n:
			if r == col:
				continue
			var factor: float = m[r][col]
			if factor == 0.0:
				continue
			for j in n:
				m[r][j] -= factor * m[col][j]
				inv[r][j] -= factor * inv[col][j]
	return inv
