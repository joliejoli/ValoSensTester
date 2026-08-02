extends Control

@export var title_text: String = ""

func _ready() -> void:
	# 防御：TopBar 是唯一 root 为 Control 的 instanced 子场景，多屏 DPI 环境
	# （4K 双屏 150%）下实例化时锚点可能未被应用（实测宽度塌成 46 逻辑而非
	# 全宽，标题居中后左半出屏），显式强制顶部拉伸预设覆盖
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	%TitleLabel.text = title_text
