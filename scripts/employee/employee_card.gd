#employee_card.gd

extends Control

signal card_clicked(employee_data: Employee) # 定义信号，把员工数据传出去

# 节点引用 (根据上面的结构定位)
@onready var name_label = $VBoxContainer/NameLabel
@onready var avatar_img = $VBoxContainer/AvatarArea/Avatar
@onready var rarity_label = $VBoxContainer/AvatarArea/RarityLabel

# 三个条
@onready var eff_bar = $VBoxContainer/StatsBars/EfficiencyBar
@onready var qual_bar = $VBoxContainer/StatsBars/QualityBar
@onready var exp_bar = $VBoxContainer/StatsBars/ExperienceBar

var my_employee_data: Employee

func setup_card(employee_data: Employee) -> void:
	if employee_data == null: return
	my_employee_data = employee_data
	
	# 1. 设置名字
	name_label.text = employee_data.employee_name
	print(name_label.text)
	
	# 2. 设置头像和等级悬浮标
	match employee_data.rarity:
		Employee.Rarity.R: 
			rarity_label.text = " R "
			rarity_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
		Employee.Rarity.SR: 
			rarity_label.text = " SR "
			rarity_label.add_theme_color_override("font_color", Color.MEDIUM_PURPLE)
		Employee.Rarity.SSR: 
			rarity_label.text = " SSR "
			rarity_label.add_theme_color_override("font_color", Color.GOLD)
			
	# 如果你有头像图片，可以在这里赋值：
	# avatar_img.texture = employee_data.avatar_texture
	
	# 3. 设置属性条
	eff_bar.max_value = 10
	eff_bar.value = employee_data.efficiency
	
	qual_bar.max_value = 10
	qual_bar.value = employee_data.quality
	
	exp_bar.max_value = 10
	exp_bar.value = employee_data.experience

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("点中了员工：", my_employee_data.employee_name)
		card_clicked.emit(my_employee_data) # 发射信号
		accept_event() # 拦截点击，防止触发仓库的“点击空白处关闭”
