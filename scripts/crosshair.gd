extends Control
# 准星绘制：样式由 TestConfig.crosshair_style 控制
# 0=标准十字 1=紧凑十字（默认，缩小版） 2=圆点

var flash_timer := 0.0

func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		queue_redraw()

func flash() -> void:
	flash_timer = 0.15

func _draw() -> void:
	var c := size / 2.0
	var col := Color(1, 1, 1, 1)
	if flash_timer > 0.0:
		col = Color(1, 0.25, 0.3, 1)
	match TestConfig.crosshair_style:
		2:
			draw_circle(c, 2.5, col)
		1:
			_draw_cross(c, col, 1.0, 5.0, 1.5)
		_:
			_draw_cross(c, col, 2.0, 9.0, 2.0)

func _draw_cross(c: Vector2, col: Color, gap: float, len: float, thick: float) -> void:
	draw_rect(Rect2(c.x - thick / 2.0, c.y - gap - len, thick, len), col)
	draw_rect(Rect2(c.x - thick / 2.0, c.y + gap, thick, len), col)
	draw_rect(Rect2(c.x - gap - len, c.y - thick / 2.0, len, thick), col)
	draw_rect(Rect2(c.x + gap, c.y - thick / 2.0, len, thick), col)
	draw_rect(Rect2(c.x - 0.75, c.y - 0.75, 1.5, 1.5), col)
