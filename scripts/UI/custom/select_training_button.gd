# select_training_button.gd
# 培训属性选择按钮。结构（对应你搭好的场景）：
#   UnselectedBcg / SelectedBcg   —— 合上 / 打开 的文件夹背景（各自独立摆放、尺寸可不同）
#   UnselectedIcon / SelectedIcon —— 未选 / 选中 的属性图标（各自独立摆放、尺寸可不同）
#   Label                          —— 属性缩写（英文 EFF/QUAL/EXP，中文 效率/品质/经验）
#
# "选中" = 玩家当前准备培训的就是这项属性（由培训面板做单选管理，不是 TextureButton 的按下态）。
# 本脚本只切换那两对节点的 visible，绝不改动任何贴图 / 尺寸 / 位置。
extends TextureButton
class_name SelectTrainingButton

enum Attr { EFF, QUAL, EXP }

@export var attribute: Attr = Attr.EFF:
	set(value):
		attribute = value
		_refresh_label()

signal attribute_chosen(attr: int)   # 被点击时发出，告诉面板"选我这项属性"

## 属性图标（选中/未选中是同一张素材）：在【实例根节点】上设一次即可，脚本会同时套到两个 Icon 节点。
## 留空则保留场景里 UnselectedIcon/SelectedIcon 各自已设的贴图。
@export var icon_texture: Texture2D

@onready var _unsel_bcg: TextureRect = $UnselectedBcg
@onready var _sel_bcg: TextureRect = $SelectedBcg
@onready var _unsel_icon: TextureRect = $UnselectedIcon
@onready var _sel_icon: TextureRect = $SelectedIcon
@onready var _label: Label = $Label

var _is_selected: bool = false

func _ready() -> void:
	# 子节点都别挡按钮点击（否则点在背景/图标上按钮收不到）
	for c in [_unsel_bcg, _sel_bcg, _unsel_icon, _sel_icon, _label]:
		if c:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 属性图标：实例根上设了 icon_texture，就同时套到两个图标节点（选中/未选中同一张素材）
	if icon_texture:
		if _unsel_icon: _unsel_icon.texture = icon_texture
		if _sel_icon: _sel_icon.texture = icon_texture
	_refresh_label()
	pressed.connect(_on_pressed)
	set_selected(_is_selected)   # 初始按当前状态刷新显隐

func _on_pressed() -> void:
	attribute_chosen.emit(attribute)

# 面板调用：选中 = 显示"打开文件夹 + 选中图标"；未选中 = 显示"合上文件夹 + 未选图标"。
# 只切 visible，不动贴图/尺寸/位置。
func set_selected(sel: bool) -> void:
	_is_selected = sel
	if _sel_bcg: _sel_bcg.visible = sel
	if _sel_icon: _sel_icon.visible = sel
	if _unsel_bcg: _unsel_bcg.visible = not sel
	if _unsel_icon: _unsel_icon.visible = not sel

func is_selected() -> bool:
	return _is_selected

func _refresh_label() -> void:
	if _label:
		_label.text = tr(_label_key())

func _label_key() -> String:
	match attribute:
		Attr.EFF: return "Sidebar_TRAIN_ABBR_EFF"
		Attr.QUAL: return "Sidebar_TRAIN_ABBR_QUAL"
		Attr.EXP: return "Sidebar_TRAIN_ABBR_EXP"
	return "Sidebar_TRAIN_ABBR_EFF"

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_label()
