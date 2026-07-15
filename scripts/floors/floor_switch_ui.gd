extends VBoxContainer
# 楼层切换按钮条(1F/2F/…)。
# 按 BuildingManager 注册的楼层自动生成按钮——不给任何一层写死独立逻辑,
# 未来 3F/4F 注册后自动出现。当前楼层高亮(toggle 按下态),未解锁显示锁定提示。

const FONT_PATH := "res://assets/fonts/standard.tres"

var _bm: BuildingManager = null
var _buttons := {}  # floor_id -> Button
var _hint_label: Label = null


func _ready() -> void:
	add_to_group("floor_switch_ui")
	# BuildingManager 与本 UI 同一场景建树,顺序不定,延迟到首帧后再绑定
	call_deferred("_bind")


func _bind() -> void:
	_bm = get_tree().get_first_node_in_group("building_manager")
	if _bm == null:
		push_error("FloorSwitchUI:场景里没有 BuildingManager,楼层按钮不可用")
		return
	_bm.floor_changed.connect(func(_id): _rebuild())
	_bm.floor_unlocked.connect(func(_id): _rebuild())
	_bm.decoration_mode_changed.connect(func(_active): _rebuild())
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	_hint_label = null

	var font := load(FONT_PATH)
	for fid in _bm.get_floor_ids():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(64, 40)
		btn.focus_mode = Control.FOCUS_NONE
		if font:
			btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 20)

		var unlocked: bool = _bm.is_floor_unlocked(fid)
		btn.text = _bm.get_floor_label(fid)
		if not unlocked:
			# 项目字体没有锁形字符,锁定态用半透明 + 悬停/点击文字提示表达
			btn.modulate = Color(1, 1, 1, 0.5)
			btn.tooltip_text = _bm.get_unlock_hint(fid)
		btn.button_pressed = fid == _bm.current_floor_id
		btn.pressed.connect(_on_floor_button_pressed.bind(fid))
		add_child(btn)
		_buttons[fid] = btn

	# 当前楼层可装修 → 显示"装修/完成"按钮(第一层不可装修,不会出现)
	if _bm.is_floor_decoratable(_bm.current_floor_id):
		var deco_btn := Button.new()
		deco_btn.custom_minimum_size = Vector2(64, 40)
		deco_btn.focus_mode = Control.FOCUS_NONE
		var font2 := load(FONT_PATH)
		if font2:
			deco_btn.add_theme_font_override("font", font2)
		deco_btn.add_theme_font_size_override("font_size", 18)
		deco_btn.text = "完成" if _bm.is_decoration_active() else "装修"
		deco_btn.pressed.connect(func(): _bm.toggle_decoration_mode())
		add_child(deco_btn)


func _on_floor_button_pressed(fid: int) -> void:
	if _bm.is_floor_unlocked(fid):
		_bm.switch_floor(fid)
		_rebuild()
	else:
		_flash_hint(_bm.get_unlock_hint(fid))
		_rebuild()  # 恢复按钮 toggle 状态


# 点未解锁楼层时短暂弹出解锁说明
func _flash_hint(text: String) -> void:
	if text.is_empty():
		return
	if _hint_label == null or not is_instance_valid(_hint_label):
		_hint_label = Label.new()
		var font := load(FONT_PATH)
		if font:
			_hint_label.add_theme_font_override("font", font)
		_hint_label.add_theme_font_size_override("font_size", 16)
		_hint_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
		add_child(_hint_label)
	_hint_label.text = text
	_hint_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(func():
		if is_instance_valid(_hint_label):
			_hint_label.visible = false)
