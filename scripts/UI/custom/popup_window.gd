#popup_window.gd
extends Control

signal confirmed
signal canceled

@export_group("Text Content")
@export var title_text: String = "InputQuestionHere":
	set(v):
		title_text = v
		if is_node_ready(): $Panel/VBoxContainer/Label.text = v

@export var confirm_label: String = "ConfirmButton":
	set(v):
		confirm_label = v
		if is_node_ready(): $Panel/VBoxContainer/HBoxContainer/ConfirmButton/Label.text = v

@export var cancel_label: String = "CancelButton":
	set(v):
		cancel_label = v
		if is_node_ready(): $Panel/VBoxContainer/HBoxContainer/CancelButton/Label.text = v

func _ready():
	# 初始化文本（保持之前的逻辑）
	_update_ui()
	
	# 2. 连接内部按钮的信号到本脚本的函数
	$Panel/VBoxContainer/HBoxContainer/ConfirmButton.pressed.connect(_on_confirm_pressed)
	$Panel/VBoxContainer/HBoxContainer/CancelButton.pressed.connect(_on_cancel_pressed)

func _on_confirm_pressed():
	# 3. 当内部按钮按下时，发出自定义信号
	confirmed.emit()
	# 如果是通用弹窗，通常点完就消失
	hide() 

func _on_cancel_pressed():
	canceled.emit()
	hide()

func _update_ui():
	# 封装一下之前的赋值逻辑，防止代码太乱
	$Panel/VBoxContainer/Label.text = title_text
	$Panel/VBoxContainer/HBoxContainer/ConfirmButton/Label.text = confirm_label
	$Panel/VBoxContainer/HBoxContainer/CancelButton/Label.text = cancel_label
