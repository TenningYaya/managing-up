# quote_editor.gd
extends Control

@onready var list_container = $ScrollContainer/MarginContainer/VBoxContainer
@onready var input_field = $HBoxContainer/LineEdit
const TRASH_ICON_SCENE = preload("res://scenes/UI/custom/normal_delete_button.tscn")

func _ready():
	input_field.text_changed.connect(_on_text_changed)
	refresh_list()

func refresh_list():
	# 清空旧显示
	for child in list_container.get_children():
		child.queue_free()
	
	
	for i in range(SpeedupQuoteSave.boss_quotes.size()):
		var line = HBoxContainer.new()
		
		# 1. 文本框部分
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# 🌟【关键】：MarginContainer 可以强制内部留出边距
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 5)
		margin.add_theme_constant_override("margin_right", 5)
		margin.add_theme_constant_override("margin_top", 5)
		margin.add_theme_constant_override("margin_bottom", 5)
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.4, 0.7, 0.5, 0.5) # 浅绿色半透明
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		panel.add_theme_stylebox_override("panel", style)
		
		var label = Label.new()
		label.text = SpeedupQuoteSave.boss_quotes[i]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		
		# 组装：Label -> MarginContainer -> PanelContainer -> Line
		margin.add_child(label)
		panel.add_child(margin)
		line.add_child(panel)
		
		# 2. 垃圾桶按钮
		var del_btn = TRASH_ICON_SCENE.instantiate()
		del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del_btn.pressed.connect(_on_delete_pressed.bind(i))
		line.add_child(del_btn)
		
		list_container.add_child(line)
		
func _on_add_pressed():
	var text = input_field.text.strip_edges()
	if text != "":
		SpeedupQuoteSave.add_quote(text)
		input_field.clear()
		refresh_list()

func _on_delete_pressed(index: int):
	SpeedupQuoteSave.remove_quote(index)
	refresh_list()

func _on_text_changed(new_text: String):
	var max_chars = 50
	if input_field.text.length() > max_chars:
		# 记录光标位置（防止删除超出字符时光标乱跳）
		var cursor_pos = input_field.get_caret_column()
		# 截断文本
		input_field.text = input_field.text.left(max_chars)
		# 恢复光标位置
		input_field.set_caret_column(max_chars)
