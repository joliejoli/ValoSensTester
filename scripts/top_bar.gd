extends Control

@export var title_text: String = ""

func _ready() -> void:
	%TitleLabel.text = title_text
