# change_office_button.gd
extends TextureButton

@export_group("Settings")
@export var office_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
@export var button_text: String = ""

@export_group("Visuals")
@export var normal_icon: Texture2D

# 🌟 新增引用：锁头图标
@onready var label: Label = $Label
@onready var lock_icon: TextureRect = $LockIcon # 假设你在预制体里加了这个节点

func _ready() -> void:
	if label:
		label.text = button_text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if normal_icon:
		texture_normal = normal_icon
	
	# 初始刷一次状态
	refresh_status()
	pressed.connect(_on_pressed)

# 🌟 核心：封装刷新逻辑
func refresh_status() -> void:
	# 1. 判定等级解锁 (从 Gamemanager 拿配置)
	var required_lv = Gamemanager.OFFICE_UNLOCK_LEVELS.get(office_type, 1)
	var is_level_ok = Gamemanager.player_level >= required_lv
	
	# 2. 判定唯一性 (从 OfficeManager 拿状态)
	var already_exists = false
	if office_type == Gamemanager.OfficeType.RECRUITMENT:
		already_exists = OfficeManager.has_recruitment_office
	elif office_type == Gamemanager.OfficeType.CULTURE_CENTER:
		already_exists = OfficeManager.has_culture_center
	
	# 🌟 重点：如果当前办公室已经选择了这个功能，不应该判定为“重复而禁用”
	# 所以这里通常配合 Panel 的逻辑，但为了按钮通用，我们可以只管等级
	
	# 3. 执行视觉反馈
	if not is_level_ok:
		# 等级未达到：重度变暗 + 显示锁头
		disabled = true
		modulate = Color(0.3, 0.3, 0.3, 1.0)
		if lock_icon: lock_icon.show()
	elif already_exists:
		# 已存在：中度变暗 + 禁用点击 + 不显锁头
		disabled = true
		modulate = Color(0.5, 0.5, 0.5, 1.0)
		if lock_icon: lock_icon.hide()
	else:
		# 正常可用
		disabled = false
		modulate = Color(1, 1, 1, 1)
		if lock_icon: lock_icon.hide()

func _on_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		panel.on_type_selected(office_type)
