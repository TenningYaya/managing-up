#win_scene.gd
extends Control

@onready var dialogue_ui = $DialogueIntroUI
@onready var final_confirm = $FinalConfirm
@onready var title_label = $FinalConfirm/MarginContainer/VBoxContainer/Title
@onready var content_label = $FinalConfirm/MarginContainer/VBoxContainer/Content
@onready var know_it_btn = $FinalConfirm/MarginContainer/VBoxContainer/KnowIt

@export var win_dialogue_keys: Array[String] = []

func _ready() -> void:
	dialogue_ui.hide()
	final_confirm.hide()
	dialogue_ui.intro_dialogue_finished.connect(_on_win_dialogue_completed)
	get_tree().create_timer(1.0).timeout.connect(start_win_sequence)

func start_win_sequence() -> void:
	if win_dialogue_keys.is_empty():
		push_warning("Inspector里的通关台词是空的")
		_on_win_dialogue_completed()
		return

	var localized_lines: Array[String] = []
	for key in win_dialogue_keys:
		localized_lines.append(tr(key))
	dialogue_ui.start_dialogue(localized_lines, 0, 0.0, 0.0, 0)

func _on_win_dialogue_completed() -> void:
	title_label.text = tr("WIN_SCENE_FINAL_TITLE")
	content_label.text = tr("WIN_SCENE_FINAL_CONTENT")
	final_confirm.show()
	await get_tree().process_frame
	know_it_btn.pressed.connect(_on_know_it_pressed)

func _on_know_it_pressed() -> void:
	hide()
	queue_free()
