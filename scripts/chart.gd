extends Control
# 通用折线图（Phase 5.2）：多序列折线 + CI 带填充 + 网格刻度 + 图例，_draw 自绘

var title := ""
var series: Array[Dictionary] = []   # {points: Array[Vector2], color: Color, label: String}
var bands: Array[Dictionary] = []    # {upper: Array[Vector2], lower: Array[Vector2], color: Color, label: String}
var y_limits := Vector2(0.0, 1.0)   # 固定 y 范围；y_auto=true 时忽略
var y_auto := false
var y_format := "%.2f"

const PAD_LEFT := 42.0
const PAD_RIGHT := 10.0
const PAD_TOP := 22.0
const PAD_BOTTOM := 24.0
const GRID_LINES := 4

func add_series(points: Array, color: Color, label: String) -> void:
	series.append({"points": points, "color": color, "label": label})
	queue_redraw()

func add_band(upper: Array, lower: Array, color: Color, label: String) -> void:
	bands.append({"upper": upper, "lower": lower, "color": color, "label": label})
	queue_redraw()

func clear_data() -> void:
	series.clear()
	bands.clear()
	queue_redraw()

func _bounds() -> Dictionary:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for s in series:
		for p in s["points"]:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
	for b in bands:
		for p in b["upper"]:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
		for p in b["lower"]:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
	if min_x == INF:
		return {"x": Vector2(0, 1), "y": Vector2(0, 1)}
	var x_pad := (max_x - min_x) * 0.06
	if x_pad <= 0.0:
		x_pad = maxf(absf(max_x) * 0.1, 0.1)
	var y_min := min_y
	var y_max := max_y
	if y_auto:
		var y_pad := (y_max - y_min) * 0.15
		if y_pad <= 0.0:
			y_pad = 0.1
		return {"x": Vector2(min_x - x_pad, max_x + x_pad), "y": Vector2(y_min - y_pad, y_max + y_pad)}
	return {"x": Vector2(min_x - x_pad, max_x + x_pad), "y": y_limits}

func _plot(p: Vector2, x_range: Vector2, y_range: Vector2) -> Vector2:
	var w := size.x - PAD_LEFT - PAD_RIGHT
	var h := size.y - PAD_TOP - PAD_BOTTOM
	return Vector2(
		PAD_LEFT + (p.x - x_range.x) / (x_range.y - x_range.x) * w,
		PAD_TOP + h - (p.y - y_range.y) / (y_range.y - y_range.x) * h,
	)

func _draw() -> void:
	var b := _bounds()
	var x_range: Vector2 = b["x"]
	var y_range: Vector2 = b["y"]
	var plot_h := size.y - PAD_TOP - PAD_BOTTOM
	if not title.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(PAD_LEFT, 14), title,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD_LEFT - PAD_RIGHT, 12, Color(0.92549, 0.909804, 0.882353, 0.85))
	var grid_color := Color(1, 1, 1, 0.08)
	var label_color := Color(0.92549, 0.909804, 0.882353, 0.5)
	for i in GRID_LINES + 1:
		var y_val := lerpf(y_range.y, y_range.x, float(i) / float(GRID_LINES))
		var py := PAD_TOP + plot_h * float(i) / float(GRID_LINES)
		draw_line(Vector2(PAD_LEFT, py), Vector2(size.x - PAD_RIGHT, py), grid_color, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(2, py + 4), y_format % y_val, HORIZONTAL_ALIGNMENT_LEFT, PAD_LEFT - 4, 10, label_color)
	var x0 := Vector2(x_range.x, 0)
	var x1 := Vector2(x_range.y, 0)
	draw_string(ThemeDB.fallback_font, Vector2(PAD_LEFT, size.y - 6), "%.2f" % x0.x, HORIZONTAL_ALIGNMENT_LEFT, 80, 10, label_color)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - PAD_RIGHT - 60, size.y - 6), "%.2f" % x1.x, HORIZONTAL_ALIGNMENT_LEFT, 60, 10, label_color)
	for bnd in bands:
		_draw_band(bnd, x_range, y_range)
	for s in series:
		_draw_series(s, x_range, y_range)
	_draw_legend()

func _draw_series(s: Dictionary, x_range: Vector2, y_range: Vector2) -> void:
	var pts: Array[Vector2] = []
	for p in s["points"]:
		pts.append(_plot(p, x_range, y_range))
	if pts.size() >= 2:
		draw_polyline(PackedVector2Array(pts), s["color"], 2.0, true)
	for pt in pts:
		draw_circle(pt, 3.0, s["color"])

func _draw_band(b: Dictionary, x_range: Vector2, y_range: Vector2) -> void:
	if b["upper"].is_empty() or b["lower"].is_empty():
		return
	var poly: PackedVector2Array = PackedVector2Array()
	var upper_pts: PackedVector2Array = PackedVector2Array()
	var lower_pts: PackedVector2Array = PackedVector2Array()
	for p in b["upper"]:
		upper_pts.append(_plot(p, x_range, y_range))
	for p in b["lower"]:
		lower_pts.append(_plot(p, x_range, y_range))
	poly.append_array(upper_pts)
	for i in range(lower_pts.size() - 1, -1, -1):
		poly.append(lower_pts[i])
	if poly.size() >= 3:
		draw_colored_polygon(poly, Color(b["color"].r, b["color"].g, b["color"].b, 0.18))
	if upper_pts.size() >= 2:
		draw_polyline(upper_pts, b["color"], 1.0, true)
		draw_polyline(lower_pts, b["color"], 1.0, true)

func _draw_legend() -> void:
	var entries: Array[Dictionary] = []
	for b in bands:
		if not String(b.get("label", "")).is_empty():
			entries.append({"color": b["color"], "label": b["label"]})
	for s in series:
		if not String(s.get("label", "")).is_empty():
			entries.append({"color": s["color"], "label": s["label"]})
	if entries.is_empty():
		return
	# 右上角竖排，避免与标题/多序列横排重叠
	var x := size.x - PAD_RIGHT - 124.0
	var y := 4.0
	for e in entries:
		draw_rect(Rect2(x, y, 10, 10), e["color"])
		draw_string(ThemeDB.fallback_font, Vector2(x + 14, y + 9), e["label"],
			HORIZONTAL_ALIGNMENT_LEFT, 110, 10, Color(0.92549, 0.909804, 0.882353, 0.8))
		y += 15.0
