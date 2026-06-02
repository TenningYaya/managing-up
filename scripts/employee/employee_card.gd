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

@onready var checkmark = $Checkmark
@onready var on_map_icon = $OnMapIcon
@onready var on_drop_area = $OnDropArea
@onready var not_working = $NotWorking

var my_employee_data: Employee
var is_selected: bool = false : 
	set(v):
		is_selected = v
		if checkmark: checkmark.visible = v

func _ready():
	# 只要有人被空投，或者有人被开除，就触发自查
	Gamemanager.request_employee_drop.connect(_on_map_changed)
	EmployeeManager.employee_removed.connect(_on_map_changed)

func _on_map_changed(_data = null):
	if not is_inside_tree() or is_queued_for_deletion():
		return
	# 给一点点缓冲时间，等节点彻底 queue_free 掉
	get_tree().create_timer(0.1).timeout.connect(func():
		update_on_map_status(my_employee_data)
	)
	
func setup_card(employee_data: Employee) -> void:
	if employee_data == null: return
	my_employee_data = employee_data
	
	# 1. 设置名字
	name_label.text = employee_data.employee_name
	
	if employee_data.portrait:
		AvatarHelper.apply_portrait(avatar_img, employee_data.portrait, employee_data.rarity)
		
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
	
	get_tree().create_timer(0.1).timeout.connect(func(): update_on_map_status(employee_data))
	
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(my_employee_data) # 发射信号
		accept_event() # 拦截点击，防止触发仓库的“点击空白处关闭”

func set_selection_mode(active: bool):
	if not active:
		is_selected = false
		
func update_on_map_status(employee_data_override: Employee = null):
	var data = employee_data_override if employee_data_override else my_employee_data
	if data == null: return
	
	# 定义三个状态变量
	var is_at_seat = false
	var is_on_drop_area = false
	
	# 1. 判定逻辑
	# 条件 A：如果有座位，说明在工位上
	if data.get("current_seat") != null:
		is_at_seat = true
		
	# 条件 B：如果没有座位，但他在掉落组且在场景树里，说明在空地上（DropArea）
	elif data.is_in_group("dropped_employee") and data.is_inside_tree() and data.visible:
		is_on_drop_area = true
		
	# 2. 视觉表现逻辑
	# 状态一：在工位上
	if is_at_seat:
		on_map_icon.visible = true       # 显示 OnMap 图标
		on_drop_area.visible = false     # 隐藏 OnDropArea 图标
		not_working.visible = false
		
	# 状态二：在空地上
	elif is_on_drop_area:
		on_map_icon.visible = false      # 隐藏 OnMap 图标
		on_drop_area.visible = true
		not_working.visible = false      # 显示 OnDropArea 图标
		
	# 状态三：不在场（在仓库）
	else:
		on_map_icon.visible = false
		on_drop_area.visible = false
		not_working.visible = true
