extends Control

@onready var title_label: Label = $TitleLabel2
@onready var thumbnail_row: HBoxContainer = $VBoxLayout/ThumbnailPanel/MarginContainer/ThumbnailRow
@onready var buttons_list: VBoxContainer = $VBoxLayout/ButtonsList
@onready var clicked_sound: AudioStreamPlayer = $ClickedSound
@onready var BG: TextureRect = $BG2

const COLOR_NORMAL := Color(0.40, 0.42, 0.62, 1.0)
const COLOR_HIGHLIGHT := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_MAXED := Color(0.26, 0.56, 0.32, 1.0)
const COLOR_LOCKED := Color(0.20, 0.21, 0.26, 1.0)   # 还没解锁的桌子：示意图色块用暗色

# 升级按钮的 modulate：可升级时正常，不可升级时压暗变灰
const BTN_MODULATE_ENABLED := Color(1.0, 1.0, 1.0, 1.0)
const BTN_MODULATE_DISABLED := Color(0.5, 0.5, 0.5, 1.0)

const DESK_HIGHLIGHT := Color(1.6, 1.4, 0.6, 1.0)
const DESK_LOCKED_DIM := Color(0.5, 0.5, 0.5, 1.0)   # 锁定桌子的静止 modulate，与 DeskSlot 锁定态一致

const FONT_PATH := "res://assets/fonts/Stacked pixel.ttf"
const NORMAL_BUTTON_SCENE := preload("res://scenes/UI/custom/normal_button.tscn")

var _desk_slots: Array = []
var _slot_boxes: Array[ColorRect] = []
var _camera_tween: Tween = null
var _camera_home_x: float = 0.0
var _camera_home_captured: bool = false

func _ready() -> void:
	var t := tr("SIDEBAR_DECOR_TITLE")
	if t != "SIDEBAR_DECOR_TITLE":
		title_label.text = t
	Gamemanager.level_changed.connect(func(_v): _refresh())
	Gamemanager.kpi_changed.connect(func(_v): _update_button_states())
	

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		title_label.text = tr("SIDEBAR_DECOR_TITLE")
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			# 每次打开 app 都重建，保证按钮数量与当前桌子状态完全同步
			_camera_home_captured = false
			_refresh()
		else:
			_reset_all_highlights()
			_return_camera_home()

# =====================================================
# 构建
# =====================================================
func _refresh() -> void:
	if not is_inside_tree():
		return
	_clear_dynamic_nodes()
	_collect_desk_slots()
	_build_thumbnail()
	_build_buttons()

func _clear_dynamic_nodes() -> void:
	_reset_all_highlights()
	for child in thumbnail_row.get_children():
		thumbnail_row.remove_child(child)
		child.queue_free()
	for child in buttons_list.get_children():
		buttons_list.remove_child(child)
		child.queue_free()
	_slot_boxes.clear()
	_desk_slots.clear()

# 收集全部桌子组，按"物理列顺序"（场景里从左到右）排列。
# 装修页要把 5 列桌子全部显示出来，锁着的也显示（按钮禁用+锁定提示），
# 这样示意图就是办公室的小地图：第 i 个色块/按钮 = 从左数第 i 列桌子。
func _collect_desk_slots() -> void:
	var raw := get_tree().get_nodes_in_group("desk_slots")
	raw.sort_custom(func(a, b): return a.get_index() < b.get_index())
	for slot in raw:
		_desk_slots.append(slot)

# 桌子是否还没解锁（没到它的 unlock_at_level）
func _is_slot_locked(slot) -> bool:
	return slot.unlock_at_level > Gamemanager.player_level

# 示意图色块的静止颜色：锁定→暗色，满级→绿，否则普通
func _box_rest_color(slot) -> Color:
	if _is_slot_locked(slot):
		return COLOR_LOCKED
	return COLOR_MAXED if slot.slot_level >= 4 else COLOR_NORMAL

# 桌子在办公室里的静止 modulate：锁定→压暗，否则正常
func _desk_rest_modulate(slot) -> Color:
	return DESK_LOCKED_DIM if _is_slot_locked(slot) else Color.WHITE

# 缩略图：每组桌子一个色块，不写数字
func _build_thumbnail() -> void:
	for i in range(_desk_slots.size()):
		var slot = _desk_slots[i]
		var box := ColorRect.new()
		box.custom_minimum_size = Vector2(26, 58)
		box.color = _box_rest_color(slot)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		thumbnail_row.add_child(box)
		_slot_boxes.append(box)

func _build_buttons() -> void:
	var font := load(FONT_PATH) as FontFile

	for i in range(_desk_slots.size()):
		var btn = NORMAL_BUTTON_SCENE.instantiate()
		btn.custom_minimum_size = Vector2(210, 24)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var label := btn.get_node("Label") as Label
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font:
			label.add_theme_font_override("font", font)

		var idx := i
		btn.mouse_entered.connect(func(): _on_hover(idx))
		btn.mouse_exited.connect(func(): _on_hover_exit(idx))
		btn.pressed.connect(func(): _on_upgrade_pressed(idx))

		buttons_list.add_child(btn)

	_update_button_states()

func _update_button_states() -> void:
	var btns := buttons_list.get_children()
	for i in range(mini(btns.size(), _desk_slots.size())):
		var slot = _desk_slots[i]
		var lvl: int = slot.slot_level
		var max_allowed: int = Gamemanager.max_desk_level
		var btn := btns[i] as TextureButton
		var label := btn.get_node("Label") as Label

		if _is_slot_locked(slot):
			# 桌子还没解锁：禁用 + 锁定提示，显示解锁所需的玩家等级。
			# 注：像素字体 Stacked pixel.ttf 没有 emoji 字形，🔒 会渲染成豆腐块，故用文字。
			label.text = "Locked  Need M%d" % slot.unlock_at_level
			btn.disabled = true
		elif lvl >= 4:
			label.text = "Lv.%d  MAX" % lvl
			btn.disabled = true
		elif lvl >= max_allowed:
			label.text = "Lv.%d  (Need M%d)" % [lvl, lvl + 1]
			btn.disabled = true
		else:
			label.text = "Lv.%d -> Lv.%d   %d KPI" % [lvl, lvl + 1, _get_cost(lvl)]
			btn.disabled = not Gamemanager.has_enough_kpi(_get_cost(lvl))

		# 不可升级（锁定 / MAX / 等级不够 / KPI 不足）的按钮压暗变灰
		btn.modulate = BTN_MODULATE_DISABLED if btn.disabled else BTN_MODULATE_ENABLED

		if i < _slot_boxes.size():
			_slot_boxes[i].color = _box_rest_color(slot)

# =====================================================
# 悬停：高亮缩略图色块 + 镜头移动到对应桌子
# =====================================================
func _on_hover(idx: int) -> void:
	if idx < _slot_boxes.size():
		_slot_boxes[idx].color = COLOR_HIGHLIGHT
	if idx < _desk_slots.size() and is_instance_valid(_desk_slots[idx]):
		_desk_slots[idx].modulate = DESK_HIGHLIGHT
		_move_camera_to(_desk_slots[idx])

func _on_hover_exit(idx: int) -> void:
	if idx < _slot_boxes.size() and idx < _desk_slots.size():
		_slot_boxes[idx].color = _box_rest_color(_desk_slots[idx])
	if idx < _desk_slots.size() and is_instance_valid(_desk_slots[idx]):
		_desk_slots[idx].modulate = _desk_rest_modulate(_desk_slots[idx])
	_return_camera_home()

func _on_upgrade_pressed(idx: int) -> void:
	if idx >= _desk_slots.size(): return
	var slot = _desk_slots[idx]
	if _is_slot_locked(slot): return   # 锁着的桌子不能升级（按钮本就禁用，这里再兜底）
	var lvl: int = slot.slot_level
	if lvl >= 4 or lvl >= Gamemanager.max_desk_level: return

	var cost := _get_cost(lvl)
	if not Gamemanager.spend_kpi(cost, Ledger.Cat.BUILD_DECOR): return

	# 镜头此时已停在该桌子上（因为鼠标正悬停在按钮上），升级动作可被玩家直接看到
	slot.upgrade_all()
	clicked_sound.play()
	_update_button_states()

# =====================================================
# 镜头控制
# =====================================================
func _move_camera_to(slot: Control) -> void:
	var camera := get_viewport().get_camera_2d()
	if not is_instance_valid(camera): return

	if not _camera_home_captured:
		_camera_home_x = camera.position.x
		_camera_home_captured = true

	if is_instance_valid(_camera_tween):
		_camera_tween.kill()

	var vp_half_w: float = get_viewport_rect().size.x / 2.0
	var slot_screen_cx: float = slot.get_global_transform_with_canvas().origin.x + slot.size.x / 2.0
	var offset: float = slot_screen_cx - vp_half_w
	var target_x: float = clampf(camera.position.x + offset, -100.0, 2110.0)

	_camera_tween = create_tween()
	_camera_tween.tween_property(camera, "position:x", target_x, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _return_camera_home() -> void:
	if not _camera_home_captured: return
	var camera := get_viewport().get_camera_2d()
	if not is_instance_valid(camera): return

	if is_instance_valid(_camera_tween):
		_camera_tween.kill()

	_camera_tween = create_tween()
	_camera_tween.tween_property(camera, "position:x", _camera_home_x, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _reset_all_highlights() -> void:
	for slot in _desk_slots:
		if is_instance_valid(slot):
			slot.modulate = _desk_rest_modulate(slot)

func _get_cost(level: int) -> int:
	match level:
		1: return 1000
		2: return 3000
		3: return 10000
	return 0
