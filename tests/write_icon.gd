extends SceneTree

# 生成 Windows 应用图标 icon.ico（与局内靶子同款六环配色，内嵌 PNG 的 ICO 格式，
# 多尺寸 16/24/32/48/64/128/256，Vista+ 支持）

const SIZES := [256, 128, 64, 48, 32, 24, 16]

func _init() -> void:
	await process_frame
	var entries: Array = []
	var offset := 6 + SIZES.size() * 16
	for s in SIZES:
		var img := _make_ring_image(s)
		var png := img.save_png_to_buffer()
		entries.append({"size": s, "png": png, "offset": offset})
		offset += png.size()
	var f := FileAccess.open("res://icon.ico", FileAccess.WRITE)
	f.store_8(0)
	f.store_8(0)
	f.store_8(1)
	f.store_8(0)
	f.store_16(SIZES.size())
	for e in entries:
		f.store_8(e["size"] & 0xFF if e["size"] < 256 else 0)
		f.store_8(e["size"] & 0xFF if e["size"] < 256 else 0)
		f.store_8(0)
		f.store_8(0)
		f.store_16(1)
		f.store_16(32)
		f.store_32(e["png"].size())
		f.store_32(e["offset"])
	for e in entries:
		f.store_buffer(e["png"])
	f.close()
	# 同时输出 256 源 PNG 备用
	var src := _make_ring_image(512)
	var fp := FileAccess.open("res://icon.png", FileAccess.WRITE)
	fp.store_buffer(src.save_png_to_buffer())
	fp.close()
	print("icon.ico written: %d sizes, %d bytes" % [SIZES.size(), offset])
	quit(0)

# 局内靶子同款同心环（target.gd make_target_texture 配色，归一化半径 d）
func _make_ring_image(px: int) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := float(px) / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var col := Color(0, 0, 0, 0)
			if d <= 1.0:
				col = Color(0.12, 0.16, 0.21)
			if d <= 0.9:
				col = Color(0.85, 0.88, 0.92)
			if d <= 0.68:
				col = Color(0.16, 0.2, 0.27)
			if d <= 0.46:
				col = Color(0.9, 0.9, 0.88)
			if d <= 0.24:
				col = Color(0.85, 0.16, 0.2)
			if d <= 0.08:
				col = Color(0.95, 0.95, 0.95)
			img.set_pixel(x, y, col)
	return img
