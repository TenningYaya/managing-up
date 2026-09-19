#employee_card.gd

extends Control

signal card_clicked(employee_data: Employee) # 定义信号，把员工数据传出去

# 节点引用 (根据上面的结构定位)
@onready var name_label: Label = $VBoxContainer/NameLabel
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

# 名字自适应：名字过长时自动缩小字号塞进卡片宽度，而不是把卡片撑变形。
# ⚠️ NAME_BASE_FONT_SIZE 必须和场景里 NameLabel 的 font_size 保持一致。
const NAME_BASE_FONT_SIZE := 16
const NAME_MIN_FONT_SIZE := 8

# ==========================================================
# 🎨 卡片底色（按稀有度区分）—— 随便调，改完直接跑就能看效果
# 现在给的是头像底色的浅化版，当起点用；想怎么改都行。
# ==========================================================
const RARITY_CARD_COLORS = {
	Employee.Rarity.R:   Color("ffffffff"),
	Employee.Rarity.SR:  Color("ffffffff"),
	Employee.Rarity.SSR: Color("ffffffff")
}

# 卡片底色的那块 ColorRect。
# 兼容两种节点名：改名成 RarityColorRect 的用新名，没改名的回退到原来的 ColorRect。
@onready var rarity_rect: ColorRect = (
	get_node_or_null("RarityColorRect") as ColorRect
)

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

	# 名字标签：裁切模式 + 布局变化时重算字号
	# ⚠️ clip_text 是关键：Label 默认把「文字完整宽度」当成自己的最小宽度，
	#    会一路把 VBoxContainer 顶宽、进而把 AvatarArea 也拉长（卡片变形）。
	#    开了裁切之后最小宽度归零，卡片宽度就只由 AvatarArea 决定，稳定不变。
	name_label.clip_text = true
	name_label.resized.connect(_fit_name_font)

# 名字自适应字号：按当前可用宽度，把过长的名字缩到塞得下为止。
# 用实际尺寸计算，卡片宽度以后怎么调都自动适配，不写死像素。
func _fit_name_font() -> void:
	if name_label == null or name_label.text == "":
		return
	var font: Font = name_label.get_theme_font("font")
	if font == null:
		return
	var avail: float = name_label.size.x
	if avail <= 0.0:
		return   # 还没布局好，等 resized 再来

	var full_w := font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_BASE_FONT_SIZE).x
	var target := NAME_BASE_FONT_SIZE
	if full_w > avail and full_w > 0.0:
		target = int(floor(NAME_BASE_FONT_SIZE * avail / full_w))
	name_label.add_theme_font_size_override("font_size", clampi(target, NAME_MIN_FONT_SIZE, NAME_BASE_FONT_SIZE))

# 按稀有度刷卡片底色。节点没找到就安静跳过，不报错。
func _apply_rarity_card_color(emp_rarity: Employee.Rarity) -> void:
	if rarity_rect == null:
		return
	rarity_rect.color = RARITY_CARD_COLORS.get(emp_rarity, rarity_rect.color)

# 统一的「设名字」入口：设完文字顺手重算字号
func _set_name_text(new_text: String) -> void:
	name_label.text = new_text
	_fit_name_font()

# 数据被改名时（在员工面板改的）刷新本卡名字
func _on_employee_renamed() -> void:
	if is_instance_valid(my_employee_data):
		_set_name_text(my_employee_data.get_display_name())

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and is_instance_valid(my_employee_data):
		_set_name_text(my_employee_data.get_display_name())

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

	# 1. 设置名字（过长会自动缩字号，不撑变卡片）
	_set_name_text(employee_data.get_display_name())
	
	if employee_data.portrait:
		AvatarHelper.apply_portrait(avatar_img, employee_data.portrait, employee_data.rarity)
		
	# 2. 卡片底色按稀有度刷
	_apply_rarity_card_color(employee_data.rarity)

	# 3. 设置头像和等级悬浮标
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
