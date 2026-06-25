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

# 重命名相关资源（铅笔图标 + 卡片字体，保持与名字标签一致的像素字体）
const RENAME_ICON := preload("res://assets/UI/employee/warehouse/rename.png")
const CARD_FONT := preload("res://assets/fonts/stacked_pixel_cjk.tres")

# 重命名用到的节点（在 _ready 里动态创建，避免改 .tscn 结构）
var name_row: HBoxContainer
var edit_name_button: TextureButton
var name_edit: LineEdit
var _is_editing_name: bool = false
var _name_before_edit: String = ""

var my_employee_data: Employee
var is_selected: bool = false : 
	set(v):
		is_selected = v
		if checkmark: checkmark.visible = v

func _ready():
	# 只要有人被空投，或者有人被开除，就触发自查
	Gamemanager.request_employee_drop.connect(_on_map_changed)
	EmployeeManager.employee_removed.connect(_on_map_changed)
	EmployeeManager.employee_map_status_changed.connect(_on_map_changed)
	_build_rename_ui()

# 把名字标签塞进一行容器，并在右侧加一个铅笔按钮；再放一个默认隐藏的行内编辑框。
func _build_rename_ui() -> void:
	var vbox := $VBoxContainer
	var label_index := name_label.get_index()

	# 一行容器：名字（占满剩余宽度、文字居中）+ 铅笔按钮（贴右）
	name_row = HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.mouse_filter = Control.MOUSE_FILTER_PASS  # 让空白处的点击仍能冒泡给卡片（打开面板）
	name_row.add_theme_constant_override("separation", 2)
	vbox.add_child(name_row)
	vbox.move_child(name_row, label_index)

	# 原 NameLabel 移进行容器，占满剩余宽度（文字本身已是居中对齐）
	name_label.reparent(name_row, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 铅笔按钮
	edit_name_button = TextureButton.new()
	edit_name_button.name = "EditNameButton"
	edit_name_button.texture_normal = RENAME_ICON
	edit_name_button.ignore_texture_size = true
	edit_name_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	edit_name_button.custom_minimum_size = Vector2(14, 14)
	edit_name_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(edit_name_button)
	edit_name_button.pressed.connect(_start_rename)

	# 行内编辑框：默认隐藏，编辑时顶替 name_row 的位置
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.max_length = 12
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.add_theme_font_override("font", CARD_FONT)
	name_edit.add_theme_font_size_override("font_size", 14)
	name_edit.hide()
	vbox.add_child(name_edit)
	vbox.move_child(name_edit, name_row.get_index() + 1)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_on_name_focus_exited)
	name_edit.gui_input.connect(_on_name_edit_gui_input)

# ==================== 行内重命名 ====================
func _start_rename() -> void:
	if my_employee_data == null or _is_editing_name:
		return
	_is_editing_name = true
	_name_before_edit = my_employee_data.get_display_name()
	name_edit.text = _name_before_edit
	name_row.hide()
	name_edit.show()
	# 等控件显示后再抢焦点并全选，让玩家直接打字覆盖
	name_edit.grab_focus.call_deferred()
	name_edit.select_all.call_deferred()

func _on_name_submitted(_text: String) -> void:
	_commit_rename()

func _on_name_focus_exited() -> void:
	_commit_rename()

func _on_name_edit_gui_input(event: InputEvent) -> void:
	# Esc 取消：先还原再退出（见 _cancel_rename），并吃掉事件防止冒泡
	if event.is_action_pressed("ui_cancel"):
		_cancel_rename()
		accept_event()

func _commit_rename() -> void:
	if not _is_editing_name:
		return
	_is_editing_name = false
	var new_name := name_edit.text.strip_edges()
	# 空名字不接受 → 还原原名字（即不写回）；没变化也不写回
	if new_name != "" and is_instance_valid(my_employee_data) and new_name != my_employee_data.get_display_name():
		my_employee_data.set_custom_name(new_name)  # 写回数据源，renamed 信号会刷新所有视图
	_exit_edit_mode()

func _cancel_rename() -> void:
	if not _is_editing_name:
		return
	# 关键顺序：先把标志位置 false，这样退出时 hide() 触发的 focus_exited 会被 _commit_rename 拦掉，
	# 绝不会把编辑框里的新文本提交回去
	_is_editing_name = false
	name_edit.text = _name_before_edit
	_exit_edit_mode()

func _exit_edit_mode() -> void:
	name_edit.hide()
	name_row.show()
	if is_instance_valid(my_employee_data):
		name_label.text = my_employee_data.get_display_name()

# 数据被改名时（无论从哪触发）刷新本卡名字
func _on_employee_renamed() -> void:
	if is_instance_valid(my_employee_data):
		name_label.text = my_employee_data.get_display_name()
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and is_instance_valid(my_employee_data):
		name_label.text = my_employee_data.get_display_name()

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

	# 改名时同步刷新本卡名字（卡片被销毁时连接会自动断开）
	if not employee_data.display_name_changed.is_connected(_on_employee_renamed):
		employee_data.display_name_changed.connect(_on_employee_renamed)

	# 1. 设置名字
	name_label.text = employee_data.get_display_name()
	
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
