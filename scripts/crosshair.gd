extends Control

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
	var gap := 2.0
	var len := 9.0
	var thick := 2.0
	draw_rect(Rect2(c.x - thick / 2.0, c.y - gap - len, thick, len), col)
	draw_rect(Rect2(c.x - thick / 2.0, c.y + gap, thick, len), col)
	draw_rect(Rect2(c.x - gap - len, c.y - thick / 2.0, len, thick), col)
	draw_rect(Rect2(c.x + gap, c.y - thick / 2.0, len, thick), col)
	draw_rect(Rect2(c.x - 0.75, c.y - 0.75, 1.5, 1.5), col)
