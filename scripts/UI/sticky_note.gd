extends Control

# 点放大按钮 = 请求回到完整游戏模式（由 main.gd 监听并切换）
signal restore_full_game

const TITLE_BAR_HEIGHT := 35.0
# 按下 icon 后移动超过这个距离算拖拽，否则算点击（展开）
const ICON_DRAG_THRESHOLD := 4.0

var _dragging := false
var _drag_offset := Vector2()
var _base_size := Vector2()   # 正常态尺寸，进树时从场景里记录
var _collapsed := false       # 已折叠成 icon（隐藏/关闭按钮触发）
var _icon_home_pos := Vector2()   # icon 在便签上的场景位（右上角），折叠/展开时用来对齐
var _icon_press_pos := Vector2()  # 折叠态按下时的鼠标位置，用于区分点击和拖拽
var _icon_dragged := false        # 本次按下已经拖动过 → 松开时不触发展开

@onready var text_edit: TextEdit = $TextEdit
@onready var color_rect: ColorRect = $ColorRect
@onready var title_label: Label = $Label
@onready var title_buttons: HBoxContainer = $TitleButtons
@onready var resize_button: TextureButton = $TitleButtons/ResizeButton
@onready var collapsed_icon: TextureButton = $CollapsedIcon

func _ready() -> void:
	_base_size = size
	_icon_home_pos = collapsed_icon.position
	collapsed_icon.hide()  # 场景里可见方便编辑，运行时初始一定是展开态
	text_edit.text = Gamemanager.sticky_note_text
	text_edit.text_changed.connect(_on_text_changed)
	# 隐藏、关闭：都折叠成 icon；点 icon 恢复
	$TitleButtons/HideButton.pressed.connect(_collapse)
	$TitleButtons/CloseButton.pressed.connect(_collapse)
	resize_button.pressed.connect(func(): restore_full_game.emit())
	collapsed_icon.pressed.connect(_expand)

func _on_text_changed() -> void:
	Gamemanager.sticky_note_text = text_edit.text

func _collapse() -> void:
	_collapsed = true
	_dragging = false
	for n in [color_rect, title_label, text_edit, title_buttons]:
		n.hide()
	# icon 出现在它在便签上的原位（右上角）；根节点缩到 icon 大小并挪到该处，
	# 穿透 region 用的是根节点矩形，折叠后桌面其余区域才能点透
	var icon_global := position + _icon_home_pos * scale
	scale = Vector2.ONE
	size = collapsed_icon.size
	position = icon_global
	collapsed_icon.position = Vector2.ZERO
	collapsed_icon.show()
	_clamp_to_screen()

func _expand() -> void:
	# 拖拽 icon 松手时 TextureButton 也会发 pressed，这里吞掉，只有"原地点击"才展开
	if _icon_dragged:
		_icon_dragged = false
		return
	_collapsed = false
	collapsed_icon.hide()
	size = _base_size
	scale = Vector2.ONE
	# 便签展开后让 icon 槽位对准 icon 当前位置（icon 被拖过就地展开，没拖过等于原位还原）
	position -= _icon_home_pos * scale
	collapsed_icon.position = _icon_home_pos
	for n in [color_rect, title_label, text_edit, title_buttons]:
		n.show()
	_clamp_to_screen()

# 缩放/折叠后把可视矩形拉回屏幕内，避免放大时右下角出界够不着
func _clamp_to_screen() -> void:
	var vp := get_viewport().get_visible_rect().size
	var visual := size * scale
	position = position.clamp(Vector2.ZERO, (vp - visual).max(Vector2.ZERO))

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse := get_global_mouse_position()
			if _collapsed:
				# 折叠态：按住 icon 可拖动。不吞按下事件，让 TextureButton 正常收到，
				# 松手时靠 _icon_dragged 区分"点击展开"和"拖完放下"
				var icon_rect := collapsed_icon.get_global_transform() * Rect2(Vector2.ZERO, collapsed_icon.size)
				if icon_rect.has_point(mouse):
					_dragging = true
					_icon_dragged = false
					_icon_press_pos = mouse
					_drag_offset = mouse - global_position
				return
			var title_rect := Rect2(global_position, Vector2(size.x, TITLE_BAR_HEIGHT) * scale)
			# 右上角三个按钮让给 _gui_input，不然拖拽把点击吞掉
			var buttons_rect := title_buttons.get_global_transform() * Rect2(Vector2.ZERO, title_buttons.size)
			if title_rect.has_point(mouse) and not buttons_rect.has_point(mouse):
				_dragging = true
				_drag_offset = mouse - global_position
				get_viewport().set_input_as_handled()
		else:
			_dragging = false
	if event is InputEventMouseMotion and _dragging:
		if _collapsed and not _icon_dragged:
			if get_global_mouse_position().distance_to(_icon_press_pos) < ICON_DRAG_THRESHOLD:
				return  # 还没超过阈值，先当作点击候选
			_icon_dragged = true
		global_position = get_global_mouse_position() - _drag_offset
		get_viewport().set_input_as_handled()
