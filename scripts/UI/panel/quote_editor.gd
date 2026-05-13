# quote_editor.gd
extends Control

@onready var list_container = $ScrollContainer/VBoxContainer
@onready var input_field = $HBoxContainer/LineEdit

func _ready():
	refresh_list()

func refresh_list():
	# 清空旧显示
	for child in list_container.get_children():
		child.queue_free()
	
	# 生成新列表
	for i in range(SpeedupQuoteSave.boss_quotes.size()):
		var line = HBoxContainer.new()
		var label = Label.new()
		label.text = SpeedupQuoteSave.boss_quotes[i]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var del_btn = Button.new()
		del_btn.text = "Delete"
		del_btn.pressed.connect(_on_delete_pressed.bind(i))
		
		line.add_child(label)
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
