extends Control

@export var title_text: String = ""

func _ready() -> void:
	# 防御：TopBar 是唯一 root 为 Control 的 instanced 子场景，多屏 DPI 环境
	# （4K 双屏 150%）下实例化时锚点可能未被应用（宽度塌成 46 逻辑而非全宽）。
	# 直接赋值锚点属性强制顶部拉伸——不能用 set_anchors_and_offsets_preset：
	# 其默认 MINSIZE 模式会重算 offsets 把 offset_bottom=82 清成 0（高度塌陷、
	# 标题垂直裁剪），仅改锚点保留既有尺寸
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	%TitleLabel.text = title_text
