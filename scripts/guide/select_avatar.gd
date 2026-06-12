#select_avatar
extends Control

signal confirmed(index: int)

@export var avatar_textures: Array[Texture2D] = []

const BUTTON_SIZE := 50.0
const BUTTON_GAP := 12.0
const SELECTED_SCALE := 1.3
const EXTRA_CENTER_GAP := 8.0

@onready var button_container: Control = $MarginContainer/VBoxContainer/ButtonContainer
@onready var confirm_btn: TextureButton = $MarginContainer/VBoxContainer/Confirm

var _buttons: Array[TextureButton] = []
var _selected_index: int = 0
var _move_tween: Tween = null

func _ready() -> void:
	var placeholder = button_container.get_node_or_null("Button")
	if placeholder:
		placeholder.queue_free()
	
	button_container.clip_contents = true
	
	_build_buttons()
	
	await get_tree().process_frame
	
	# 默认选中中间（偶数则中间偏左），并立即写入 Gamemanager
	# 这样 ESC 跳过教程时也会有一个合理的默认值
	var default_index := (avatar_textures.size() - 1) / 2
	_select(default_index, false)
	Gamemanager.player_avatar_index = default_index
	Gamemanager.player_avatar_texture = avatar_textures[default_index]
	confirm_btn.pressed.connect(_on_confirm_pressed)

func _build_buttons() -> void:
	for tex in avatar_textures:
		var btn := TextureButton.new()
		btn.texture_normal = tex
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE
		btn.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		# 缩放以中心为锚点
		btn.pivot_offset = Vector2(BUTTON_SIZE / 2.0, BUTTON_SIZE / 2.0)
		button_container.add_child(btn)
		
		var idx := _buttons.size()
		btn.pressed.connect(func(): _select(idx, true))
		_buttons.append(btn)

func _select(index: int, animated: bool) -> void:
	_selected_index = clamp(index, 0, _buttons.size() - 1)
	_update_positions(animated)

func _update_positions(animated: bool) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if animated:
		_move_tween = create_tween().set_parallel(true)
	
	var center_x := button_container.size.x / 2.0
	var center_y := button_container.size.y / 2.0
	var step := BUTTON_SIZE + BUTTON_GAP
	
	# 🌟 核心魔法算式：算出因为按钮 scale 放大而向外膨胀的物理宽度
	# BUTTON_SIZE * (1.6 - 1.0) / 2.0 刚好等于边缘长出去的肉
	var push_distance := (BUTTON_SIZE * (SELECTED_SCALE - 1.0) / 2.0) + EXTRA_CENTER_GAP
	
	for i in _buttons.size():
		var btn := _buttons[i]
		var offset := i - _selected_index
		
		# 🌟 决定这个按钮要被往哪边推
		var side_push := 0.0
		if offset < 0:
			side_push = -push_distance # 在选中项左边，集体往左平移
		elif offset > 0:
			side_push = push_distance  # 在选中项右边，集体往右平移
			
		# position 指的是左上角，pivot 已设为中心，所以位置这样算
		var target_pos := Vector2(
			center_x + offset * step + side_push - BUTTON_SIZE / 2.0, # 👈 把 side_push 加进来！
			center_y - BUTTON_SIZE / 2.0
		)
		var target_scale := Vector2.ONE * SELECTED_SCALE if i == _selected_index else Vector2.ONE
		
		if animated:
			_move_tween.tween_property(btn, "position", target_pos, 0.2)\
				.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
			_move_tween.tween_property(btn, "scale", target_scale, 0.2)\
				.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		else:
			btn.position = target_pos
			btn.scale = target_scale

func _on_confirm_pressed() -> void:
	confirmed.emit(_selected_index)
	Gamemanager.player_avatar_texture = avatar_textures[_selected_index]

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				_select(_selected_index - 1, true)
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				_select(_selected_index + 1, true)
	
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_select(_selected_index - 1, true)
			KEY_RIGHT, KEY_D:
				_select(_selected_index + 1, true)
