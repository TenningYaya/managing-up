extends Control

signal dialogue_finished

@onready var label: RichTextLabel = $HBoxContainer/RichTextLabel

const CHAR_SPEED := 0.04
var _is_typing_done := false

func setup(dialogue_text: String) -> void:
	label.text = ""
	label.visible_characters = 0
	label.text = dialogue_text
	_is_typing_done = false
	_play_typewriter()

func _play_typewriter() -> void:
	var total_chars = label.get_total_character_count()
	var tween = create_tween()
	tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_SPEED)
	await tween.finished
	_is_typing_done = true  # 打字完成，开始监听点击

func _input(event: InputEvent) -> void:
	if not _is_typing_done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_is_typing_done = false
		emit_signal("dialogue_finished")
