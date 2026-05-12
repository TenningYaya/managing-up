# change_office_button.gd
extends TextureButton

@export_group("Settings")
@export var office_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
@export var button_text: String = ""

@export_group("Visuals")
@export var normal_icon: Texture2D

# 节点引用
@onready var label: Label = $Label
@onready var locked_mask: Control = $LockedMask     # 未解锁遮罩
@onready var disabled_mask: Control = $DisabledMask # 已存在遮罩
@onready var selection_border: Control = $SelectionBorder # 选中边框

func _ready() -> void:
	if label:
		label.text = button_text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if normal_icon:
		texture_normal = normal_icon
	
	# 加入按钮组，方便面板统一调用
	add_to_group("office_buttons")
	
	# 初始状态：参数为 null 时，is_selected 默认为 false
	refresh_status(null)
	pressed.connect(_on_pressed)

# 🌟 核心刷新逻辑
func refresh_status(target_office: Node = null) -> void:
	# --- 1. 获取全局判定数据 ---
	var required_lv = Gamemanager.OFFICE_UNLOCK_LEVELS.get(office_type, 1)
	var is_level_ok = Gamemanager.player_level >= required_lv
	
	var already_exists = false
	if office_type == Gamemanager.OfficeType.RECRUITMENT:
		already_exists = OfficeManager.has_recruitment_office
	elif office_type == Gamemanager.OfficeType.CULTURE_CENTER:
		already_exists = OfficeManager.has_culture_center
	
	# --- 2. 核心选中判定 ---
	var is_selected = false
	if target_office != null:
		# 只有类型完全一致，才算被选中
		is_selected = (office_type == target_office.current_type)

	# --- 3. 视觉显隐控制 ---
	# 边框显隐
	if selection_border:
		selection_border.visible = is_selected
		selection_border.modulate.a = 1.0 # 确保它是实心的

	# 遮罩和状态重置
	disabled = false
	locked_mask.hide()
	disabled_mask.hide()

	if not is_level_ok:
		# 等级不够，显示锁头，禁用点击
		disabled = true
		locked_mask.show()
	elif already_exists:
		# 功能已存在
		if is_selected:
			# 🌟 特例：如果当前房间就是这个功能，必须允许玩家点它（或者至少亮着）
			# 这样边框才会显示出来
			disabled = false
			disabled_mask.hide()
		else:
			# 别的房间占了，这间房想换就不行了
			disabled = true
			disabled_mask.show()
	else:
		# 没有任何限制，正常可用
		pass

func _on_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		panel.on_type_selected(office_type)
