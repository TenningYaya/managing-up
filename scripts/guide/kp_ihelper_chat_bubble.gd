extends Control

@onready var label: RichTextLabel = $HBoxContainer/RichTextLabel

# 每个字出现的间隔时间（越小越快）
const CHAR_SPEED := 0.04

func setup(dialogue_text: String) -> void:
	label.text = ""
	label.visible_characters = 0
	label.text = dialogue_text
	_play_typewriter()

func _play_typewriter() -> void:
	var total_chars = label.get_total_character_count()
	var tween = create_tween()
	tween.tween_property(
		label,
		"visible_characters",
		total_chars,
		total_chars * CHAR_SPEED  # 总时长 = 字数 × 每字时间
	)
