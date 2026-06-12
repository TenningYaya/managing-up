#name_program.gd
extends Control

signal confirmed(name: String)
signal canceled

const MAX_LEN_CJK = 15
const MAX_LEN_LATIN = 25

@onready var line_edit: LineEdit = $MarginContainer/VBoxContainer/LineEdit
@onready var name_too_long_label: Label = $NameTooLongLabel
@onready var confirm_btn = $MarginContainer/VBoxContainer/HBoxContainer/Confirm
@onready var cancel_btn = $MarginContainer/VBoxContainer/HBoxContainer/Cancel
@export var cancel_closes_panel: bool = false
var _refuse_tween: Tween = null


func _ready() -> void:
	name_too_long_label.hide()
	confirm_btn.pressed.connect(_on_confirm_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	line_edit.text_changed.connect(_on_text_changed)
	line_edit.grab_focus()
	
	# 根据是否在教程中切换取消键的文字
	if Gamemanager.is_tutorial_completed:
		cancel_btn.button_text = "NAME_INPUT_CANCEL_SETTINGS"
	else:
		cancel_btn.button_text = "NAME_INPUT_CANCEL"

func _on_cancel_pressed() -> void:
	if Gamemanager.is_tutorial_completed:
		canceled.emit()
		return
	line_edit.clear()
	name_too_long_label.hide()
	line_edit.grab_focus()

func _on_confirm_pressed() -> void:
	var text = line_edit.text.strip_edges()
	if text == "":
		return
	if _is_too_long(text):
		_show_refused_label()
		return
	confirmed.emit(text)

func _on_text_changed(_new_text: String) -> void:
	# 玩家改了内容就把警告收起来，给他重新尝试的感觉
	name_too_long_label.hide()

func _is_too_long(text: String) -> bool:
	var limit = MAX_LEN_CJK if _has_cjk(text) else MAX_LEN_LATIN
	return text.length() > limit

func _has_cjk(text: String) -> bool:
	for i in text.length():
		var code = text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false

func _show_refused_label() -> void:
	# 顶替旧动画
	if _refuse_tween and _refuse_tween.is_valid():
		_refuse_tween.kill()
	
	name_too_long_label.modulate.a = 1.0
	name_too_long_label.show()
	
	_refuse_tween = create_tween()
	_refuse_tween.tween_interval(3.0)
	_refuse_tween.tween_property(name_too_long_label, "modulate:a", 0.0, 0.5)
	_refuse_tween.tween_callback(name_too_long_label.hide)

func refresh_cancel_btn() -> void:
	if Gamemanager.is_tutorial_completed:
		cancel_btn.button_text = "NAME_INPUT_CANCEL_SETTINGS"
	else:
		cancel_btn.button_text = "NAME_INPUT_CANCEL"
