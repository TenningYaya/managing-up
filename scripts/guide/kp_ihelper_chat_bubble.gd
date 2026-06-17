extends Control

signal dialogue_finished
signal skip_all_requested

@onready var label: RichTextLabel = $HBoxContainer/RichTextLabel
@onready var hbox: HBoxContainer = $HBoxContainer

const CHAR_SPEED := 0.02
const EN_EXTRA_WIDTH := 100.0  # 调这个值

var _lines: Array[String] = []
var _current_index: int = 0
var _is_typing_done := false

var _space_pressed_time := 0.0
var _is_space_pressed := false
const SKIP_HOLD_TIME := 1.0

func _ready() -> void:
	if not TranslationServer.get_locale().begins_with("zh"):
		offset_right += EN_EXTRA_WIDTH
		hbox.offset_right += EN_EXTRA_WIDTH
		label.custom_minimum_size.x += EN_EXTRA_WIDTH

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _is_space_pressed:
		_space_pressed_time += delta
		if _space_pressed_time >= SKIP_HOLD_TIME:
			_is_space_pressed = false
			_space_pressed_time = 0.0
			skip_all_requested.emit()
			
# 🌟 改成接收整个数组
func setup(dialogue_lines: Array[String]) -> void:
	_lines = dialogue_lines
	_current_index = 0
	_show_current_line()

func _show_current_line() -> void:
	var text = _lines[_current_index] if _lines.size() > 0 else ""
	label.text = ""
	label.visible_characters = 0
	label.text = text
	_is_typing_done = false
	_play_typewriter()

func _play_typewriter() -> void:
	var total_chars = label.get_total_character_count()
	var tween = create_tween()
	tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_SPEED)
	await tween.finished
	_is_typing_done = true

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():   # ← 加这行
		return
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			_is_space_pressed = true
		elif not event.pressed:
			_is_space_pressed = false
			_space_pressed_time = 0.0
		get_viewport().set_input_as_handled()
		return
	if not _is_typing_done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_is_typing_done = false
		_current_index += 1
		
		if _current_index < _lines.size():
			# 还有下一句，继续播
			_show_current_line()
		else:
			# 说完了，通知大总管
			emit_signal("dialogue_finished")
