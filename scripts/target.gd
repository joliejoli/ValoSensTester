extends Node3D

signal hit(target: Node3D)
signal expired(target: Node3D)

var radius: float = 0.3
var alive := true
var move_speed := 0.0
var move_bounds := Vector2(-4.5, 4.5)

# 数据收集（由主控写入/读取）
var shots_against := 0
var first_shot_ms := -1
var lifetime := 0.0
var max_lifetime := 6.0
var spawn_ms := 0
# 生成时相对相机初始朝向的角距（弧度），speed 归一化分母（复审 P0-3）
var angle_rad := 0.0
# 瞄准过程中的准星方向反转次数（轨迹级微调，与是否开火无关；由 test_shoot 每帧更新）
var micro_adjusts := 0
var _aim_yaw_sign := 0.0
var _aim_pitch_sign := 0.0

var _sprite: Sprite3D
var _area: Area3D
var _shape: CollisionShape3D
var _move_dir := Vector3.RIGHT

const TEXTURE_SIZE := 256

func _ready() -> void:
	_sprite = $Sprite3D
	_area = $Area3D
	_shape = $Area3D/CollisionShape3D
	_sprite.texture = make_target_texture()
	_apply_size()

func setup(p_radius: float, p_position: Vector3, p_speed: float = 0.0, p_dir := Vector3.RIGHT, p_angle_rad: float = 0.0) -> void:
	radius = p_radius
	move_speed = p_speed
	_move_dir = p_dir.normalized()
	angle_rad = p_angle_rad
	global_position = p_position
	# 移动窗口以生成点为中心（修复：相机朝向任意时 world bounds 会把出生靶子瞬移到固定边界）
	move_bounds = Vector2(p_position.x - 3.0, p_position.x + 3.0)
	spawn_ms = Time.get_ticks_msec()
	max_lifetime = float(TestConfig.TARGET_MAX_LIFETIME)
	if not is_node_ready():
		await ready
	_apply_size()

func _apply_size() -> void:
	if _sprite == null:
		return
	# Sprite3D 显示尺寸 = 纹理像素数 × pixel_size，故 pixel_size = 直径 / 纹理尺寸
	_sprite.pixel_size = radius * 2.0 / TEXTURE_SIZE
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_shape.shape = sphere

func mark_shot(now_ms: int) -> void:
	if first_shot_ms < 0:
		first_shot_ms = now_ms
	shots_against += 1

func register_hit() -> void:
	if not alive:
		return
	alive = false
	_flash()
	hit.emit(self)

func _flash() -> void:
	_sprite.modulate = Color(1.6, 0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.15)

func _process(delta: float) -> void:
	if alive:
		lifetime += delta
		if lifetime > max_lifetime:
			alive = false
			expired.emit(self)
			return
		if move_speed > 0.0:
			global_position += _move_dir * move_speed * delta
			if global_position.x < move_bounds.x or global_position.x > move_bounds.y:
				global_position.x = clampf(global_position.x, move_bounds.x, move_bounds.y)
				_move_dir.x = -_move_dir.x

static func make_target_texture() -> ImageTexture:
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := float(TEXTURE_SIZE) / 2.0
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
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
	return ImageTexture.create_from_image(img)
