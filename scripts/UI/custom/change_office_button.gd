# change_office_button.gd
extends TextureButton

@export_group("Settings")
@export var office_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
@export var button_text: String = ""

@export_group("Visuals")
@export var normal_icon: Texture2D

@export_group("Explain Tips")
## 👑 这栋建筑是干嘛的？（人肉在编辑器里填）
@export_multiline var office_description: String = "功能介绍：..."
## 👑 怎么用？（人肉在编辑器里填）
@export_multiline var office_usage: String = "使用方法：..."


# 节点引用
@onready var label: Label = $Label
@onready var locked_mask: Control = $LockedMask     # 未解锁遮罩
@onready var disabled_mask: Control = $DisabledMask # 已存在遮罩
@onready var selection_border: Control = $SelectionBorder # 选中边框
@onready var current_mark: TextureRect = $CurrentMark     # 当前功能的对号标记（图标下方）
var _full_tip_text: String = ""

func _ready() -> void:
	if label:
		label.text = button_text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if normal_icon:
		texture_normal = normal_icon
	
	# ====================================================
	# 💥 核心：拔掉遮罩的“物理体积”，让鼠标直接穿透它们摸到按钮！
	# ====================================================
	if locked_mask: locked_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if disabled_mask: disabled_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#if selection_border: selection_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if current_mark: current_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	add_to_group("office_buttons")
	_setup_native_tooltip() # 先拼凑好文案
	
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
	elif office_type == Gamemanager.OfficeType.STOCK_OFFICE:
		already_exists = OfficeManager.has_stock_office
	
	# --- 2. 核心选中判定 ---
	var is_selected = false
	if target_office != null:
		# 只有类型完全一致，才算被选中
		is_selected = (office_type == target_office.current_type)

	# --- 3. 视觉显隐控制 ---
	# 边框显隐
	#if selection_border:
		#selection_border.visible = is_selected
		#selection_border.modulate.a = 1.0 # 确保它是实心的

	# 对号标记：和边框同一个判定，只有当前办公室正在用的那个功能才显示
	if current_mark:
		current_mark.visible = is_selected

	# 遮罩和状态重置
	disabled = false
	locked_mask.hide()
	disabled_mask.hide()
#
	if not is_level_ok:
		# 等级不够，显示锁头，禁用点击
		disabled = true
		locked_mask.show()
		
		# 💥 体验升级中英双语版：调用 tr() 获取带 %d 的文案，然后把 required_lv 塞进去！
		tooltip_text = tr("OFFICE_UNLOCK_REQUIREMENT") + str(required_lv)
		
	elif already_exists:
		if is_selected:
			disabled = false
			disabled_mask.hide()
		else:
			disabled = true
			disabled_mask.show()
		# 等级够了，但被别人占用的，依然把台词本发给它，正常看介绍
		tooltip_text = _full_tip_text
	else:
		# 正常可用状态
		tooltip_text = _full_tip_text

func _on_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		panel.on_type_selected(office_type)

# 是否"全局唯一"：整间公司只能开一间。判定与 refresh_status 里的 already_exists 一致
func _is_unique_type() -> bool:
	return office_type == Gamemanager.OfficeType.RECRUITMENT \
		or office_type == Gamemanager.OfficeType.CULTURE_CENTER \
		or office_type == Gamemanager.OfficeType.STOCK_OFFICE

func _setup_native_tooltip() -> void:
	# 首行标注数量限制：唯一职能办 → "全司唯一"；其余 → "可设多间"。
	# 这样玩家点不了时能明白是"已经开过一间"，而不是"等级不够"（后者由锁 + 等级提示负责）
	var limit_line := tr("OFFICE_UNIQUE_ONE") if _is_unique_type() else tr("OFFICE_UNIQUE_MULTI")

	var desc = tr(office_description) if office_description != "" else ""
	var usage = "\n" + tr(office_usage) if office_usage != "" else ""

	# 💥 核心：把拼好的长篇大论存起来，先不急着喂给 tooltip_text
	_full_tip_text = limit_line + "\n" + desc + usage
	
func _make_custom_tooltip(for_text: String) -> Object:
	# 💥 核心防呆：如果文字为空，直接返回 null，彻底拒绝渲染空黑框！
	if for_text.strip_edges() == "":
		return null
		
	var label = Label.new()
	label.text = for_text
	
	# 💥 核心魔法：开启智能自动换行
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# 💥 核心魔法：锁死宽度为 250px（高度填 0 代表由文字多少自动撑开）
	label.custom_minimum_size = Vector2(300, 0)
	
	return label
