extends SceneTree

# 生成 Windows 应用图标 icon.ico（靶子主题，内嵌 PNG 的 ICO 格式，Vista+ 支持）

func _init() -> void:
	await process_frame
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 256:
		for x in 256:
			var d := Vector2(x + 0.5 - 128.0, y + 0.5 - 128.0).length() / 128.0
			var col := Color(0, 0, 0, 0)
			if d <= 1.0:
				col = Color(0.1, 0.14, 0.19)
			if d <= 0.92:
				col = Color(0.85, 0.88, 0.92)
			if d <= 0.6:
				col = Color(0.16, 0.2, 0.27)
			if d <= 0.35:
				col = Color(1, 0.27, 0.33)
			if d <= 0.12:
				col = Color(0.95, 0.95, 0.95)
			img.set_pixel(x, y, col)
	var png := img.save_png_to_buffer()
	var f := FileAccess.open("res://icon.ico", FileAccess.WRITE)
	f.store_8(0)
	f.store_8(0)
	f.store_8(1)
	f.store_8(0)
	f.store_8(1)
	f.store_8(0)
	f.store_8(0)
	f.store_8(0)
	f.store_8(0)
	f.store_8(0)
	f.store_8(0)
	f.store_8(0)
	f.store_16(1)
	f.store_16(32)
	f.store_32(png.size())
	f.store_32(22)
	f.store_buffer(png)
	f.close()
	print("icon.ico written, png=", png.size(), " bytes")
	quit(0)
