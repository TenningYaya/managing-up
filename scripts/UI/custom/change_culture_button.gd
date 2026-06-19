# change_culture_button.gd
extends TextureButton

@export_group("Settings")
@export var culture_type: CultureCenterLogic.CultureType = CultureCenterLogic.CultureType.NONE
@export var button_text: String = ""

@export_group("Visuals")
@export var normal_icon: Texture2D          # 英文图标
@export var chinese_icon: Texture2D         # 中文图标（没设置就回退到英文）

@onready var label: Label = $Label
@onready var selection_border: Control = $SelectionBorder

func _ready() -> void:
	if label:
		label.text = button_text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_icon()

	# 确保初始边框是隐藏的
	if selection_border:
		selection_border.hide()

	pressed.connect(_on_pressed)

# 语言切换时 TranslationServer 会广播 NOTIFICATION_TRANSLATION_CHANGED，
# 面板就算已经创建过也能实时换成对应语言的图标。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_icon()

# 根据当前语言挑选图标：中文且配置了中文图就用中文，否则用英文
func _apply_icon() -> void:
	var icon := normal_icon
	if chinese_icon and TranslationServer.get_locale().begins_with("zh"):
		icon = chinese_icon
	if icon:
		texture_normal = icon

# 面板大喊时，按钮自己执行亮边框逻辑
func refresh_status(logic: CultureCenterLogic) -> void:
	if logic == null: return
	if selection_border:
		selection_border.visible = (culture_type == logic.cur_type)

# 点击按钮时，直接找 Logic 办事，然后全场广播刷新
func _on_pressed() -> void:
	var office_panel = get_tree().get_first_node_in_group("office_panel")
	if not office_panel or not office_panel.current_target_office: return
	
	var logic = office_panel.current_target_office.logic_node 
	if logic is CultureCenterLogic:
		# 1. 办事：改数值
		logic.switch_culture(culture_type)
		# 2. 广播：让同组的所有按钮（包括自己）刷新边框
		get_tree().call_group("culture_selection_buttons", "refresh_status", logic)
