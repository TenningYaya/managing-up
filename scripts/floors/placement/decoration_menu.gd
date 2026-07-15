class_name DecorationMenu
extends PanelContainer
# 装修菜单:分类页签 + 物品格子 + 仓库页 + 提示条 + 退出按钮。
# 内容完全由 PlaceableItemDB 驱动:新增 .tres 自动出现,分类按 Category 枚举自动生成,
# 本脚本没有任何具体物品的硬编码。
# 挂在共享 UI 层(CanvasLayer),位于窗口底部条内,天然在可点击穿透区里。

const FONT_PATH := "res://assets/fonts/standard.tres"
const CATEGORY_LABELS := {
	PlaceableItemData.Category.ROOM: "房间",
	PlaceableItemData.Category.DESK: "工位",
	PlaceableItemData.Category.UTILITY: "设施",
	PlaceableItemData.Category.SMALL_DECOR: "装饰",
	PlaceableItemData.Category.ZONE_PREFAB: "功能区",
	PlaceableItemData.Category.FLOOR_DECOR: "地面",
}
const TAB_WAREHOUSE := -1  # 仓库页的伪分类 id

var _controller = null            # DecorationController(不加类型注解避免循环引用)
var _db: PlaceableItemDB = null
var _floor: DecoratableFloor = null
var _font: Font = null
var _current_tab: int = PlaceableItemData.Category.ROOM

var _tab_bar: HBoxContainer
var _item_grid: GridContainer
var _hint_label: Label
var _hint_tween: Tween


func setup(controller, db: PlaceableItemDB, floor_node: DecoratableFloor) -> void:
	_controller = controller
	_db = db
	_floor = floor_node


func _ready() -> void:
	_font = load(FONT_PATH)
	visible = false
	# 底部条内左下角,右移让开最左侧的楼层/装修按钮列
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 96.0
	offset_bottom = -16.0
	offset_top = -336.0
	offset_right = 616.0

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 页签行:分类 + 仓库 + 退出
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 4)
	root.add_child(_tab_bar)
	for cat in CATEGORY_LABELS:
		_tab_bar.add_child(_make_tab_button(CATEGORY_LABELS[cat], cat))
	_tab_bar.add_child(_make_tab_button("仓库", TAB_WAREHOUSE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.add_child(spacer)
	var exit_btn := Button.new()
	_style_button(exit_btn, "退出装修")
	exit_btn.pressed.connect(func(): _controller.exit_edit_mode())
	_tab_bar.add_child(exit_btn)

	# 物品滚动区(⚠️ ScrollContainer 在 VBox 里必须给 custom_minimum_size,否则被压成 0 高)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_item_grid = GridContainer.new()
	_item_grid.columns = 3
	_item_grid.add_theme_constant_override("h_separation", 6)
	_item_grid.add_theme_constant_override("v_separation", 6)
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_grid)

	# 提示条
	_hint_label = Label.new()
	if _font:
		_hint_label.add_theme_font_override("font", _font)
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_hint_label.text = " "
	root.add_child(_hint_label)


func open_menu() -> void:
	visible = true
	refresh()


func close_menu() -> void:
	visible = false


func show_hint(text: String) -> void:
	_hint_label.text = text
	if _hint_tween:
		_hint_tween.kill()
	_hint_label.modulate.a = 1.0
	_hint_tween = create_tween()
	_hint_tween.tween_interval(2.5)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.5)


# 重建当前页(购买/入库后拥有数变化也走这里)
func refresh() -> void:
	for c in _item_grid.get_children():
		c.queue_free()
	if _db == null:
		return
	if _current_tab == TAB_WAREHOUSE:
		_fill_warehouse()
	else:
		for item in _db.get_by_category(_current_tab):
			_item_grid.add_child(_make_item_button(item, false))


func _fill_warehouse() -> void:
	var has_any := false
	for key in _floor.inventory:
		if int(_floor.inventory[key]) <= 0:
			continue
		var item := _db.get_item(StringName(key))
		if item:
			_item_grid.add_child(_make_item_button(item, true))
			has_any = true
	if not has_any:
		var empty := Label.new()
		if _font:
			empty.add_theme_font_override("font", _font)
		empty.text = "仓库是空的"
		_item_grid.add_child(empty)


func _make_tab_button(text: String, tab_id: int) -> Button:
	var btn := Button.new()
	_style_button(btn, text)
	btn.toggle_mode = true
	btn.button_pressed = tab_id == _current_tab
	btn.pressed.connect(func():
		_current_tab = tab_id
		for b in _tab_bar.get_children():
			if b is Button and b.toggle_mode:
				b.button_pressed = false
		btn.button_pressed = true
		refresh())
	return btn


func _make_item_button(item: PlaceableItemData, from_warehouse: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(158, 92)
	btn.focus_mode = Control.FOCUS_NONE
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	if item.icon:
		btn.icon = item.icon
		btn.expand_icon = true

	var owned := int(_floor.inventory.get(String(item.item_id), 0))
	var locked: bool = item.unlock_level > Gamemanager.player_level
	var lines := [item.display_name]
	if locked:
		lines.append("Lv.%d 解锁" % item.unlock_level)
	elif from_warehouse or owned > 0:
		lines.append("已有 %d 件" % owned)
	else:
		lines.append("花费 %d KPI" % item.price)
	btn.text = "\n".join(lines)
	var display_lines := [item.display_name]
	if locked:
		display_lines.append("Lv.%d 解锁" % item.unlock_level)
	else:
		display_lines.append("花费 %d KPI" % item.price)
		if from_warehouse or owned > 0:
			display_lines.append("已有 %d 个" % owned)
		if item.has_orientations() and item.get_orientation_count() > 1:
			display_lines.append("滚轮切换方向")
		elif item.can_rotate and item.allow_transform_rotation:
			display_lines.append("R 旋转")
	btn.text = "\n".join(display_lines)
	if item.has_orientations() and item.get_orientation_count() > 1:
		btn.tooltip_text = "滚轮切换方向；菜单滚动时不会旋转家具"

	if locked:
		btn.modulate = Color(1, 1, 1, 0.45)
		btn.tooltip_text = "达到 %d 级解锁" % item.unlock_level
		btn.pressed.connect(func(): show_hint("「%s」达到 %d 级解锁" % [item.display_name, item.unlock_level]))
	else:
		btn.pressed.connect(func(): _controller.select_item_for_placement(item))
	return btn


func _style_button(btn: Button, text: String) -> void:
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
