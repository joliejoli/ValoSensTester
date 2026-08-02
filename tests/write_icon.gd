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
	# 32px 简化版：运行时窗口/任务栏图标用（小尺寸直接清晰，无需 OS 缩放大图）
	var small := _make_ring_image(32)
	var fp2 := FileAccess.open("res://icon_small.png", FileAccess.WRITE)
	fp2.store_buffer(small.save_png_to_buffer())
	fp2.close()
	print("icon.ico written: %d sizes, %d bytes" % [SIZES.size(), offset])
	quit(0)

# 局内靶子同款同心环（target.gd make_target_texture 配色，归一化半径 d）
# 小尺寸（≤32px）用简化版：只保留底圆+红心+白点——细环在 16~32px 下会糊成
# 灰团（此前 512px 原图缩放导致小图标看不见），简化后小图标依然清晰可辨
func _make_ring_image(px: int) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := float(px) / 2.0
	var simplified := px <= 32
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var col := Color(0, 0, 0, 0)
			if simplified:
				if d <= 1.0:
					col = Color(0.16, 0.2, 0.27)
				if d <= 0.52:
					col = Color(0.85, 0.16, 0.2)
				if d <= 0.2:
					col = Color(0.95, 0.95, 0.95)
			else:
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
