# training_panel.gd
# office_panel 里"培训"页签的脚本，挂在 training_panel.tscn 根节点上。
# 节点结构（对应你搭好的场景）：
#   VBoxContainer/Avatars                     —— 在训员工头像（HBoxContainer，动态生成）
#   VBoxContainer/AttributeSelector/{Eff,Qual,Exp}
#   VBoxContainer/TurnSelector/{Minus,RoundCount,Plus}
#   VBoxContainer/Progress                    —— ProgressBar
#   VBoxContainer/StatusSelector/{StartButton,EndButton}
extends Control
class_name TrainingPanel

# 头像裁剪参数（照会议室，露出头部+面部填满方框）
const AVATAR_FRAME_SIZE := Vector2(56, 56)
const MINI_BAR_HEIGHT := 5.0
const AVATAR_SLOT_EXTRA_Y := 9.0   # 头像格子比立绘区域多出的下缘空间：给进度条住，别压着头像太挤
# 迷你条本色，与员工面板属性条一致（效率蓝/品质金/经验绿）
const ATTR_BAR_COLORS := {
	"eff": Color("4fb2ff"),
	"qual": Color("eeb422"),
	"exp": Color("76c442"),
}
const HEAD_ZOOM := 2.0
const HEAD_FOCUS_R := 16.0    # R 卡（脸偏下）
const HEAD_FOCUS_HIGH := 18.0 # SR / SSR

## 空位占位图（小凳子）：Avatars 里没人的格子摆这个；来人后那格换成头像、凳子消失
@export var stool_texture: Texture2D

var linked_logic = null   # 当前绑定的 TrainingRoomLogic

@onready var _avatars: HBoxContainer = $VBoxContainer/AvatarsContainer/Avatars
# 三个属性按钮现在是 SelectTrainingButton（不再是普通 Button），用无类型引用两者都兼容
@onready var _eff = $VBoxContainer/ConfigBox/VBoxContainer/AttributeContainer/AttributeSelector/Eff
@onready var _qual = $VBoxContainer/ConfigBox/VBoxContainer/AttributeContainer/AttributeSelector/Qual
@onready var _exp = $VBoxContainer/ConfigBox/VBoxContainer/AttributeContainer/AttributeSelector/Exp
@onready var _minus: TextureButton = $VBoxContainer/ConfigBox/VBoxContainer/TurnSelector/Minus
@onready var _plus: TextureButton = $VBoxContainer/ConfigBox/VBoxContainer/TurnSelector/Plus
# 中间的圆环+数字表盘（取代原来的进度条）；用 or_null，你还没在场景里加它时也不报错
@onready var _gauge = get_node_or_null("VBoxContainer/ConfigBox/VBoxContainer/TurnSelector/RoundGauge")
@onready var _start_btn = $VBoxContainer/StatusContainer/StatusSelector/StartButton
@onready var _end_btn = $VBoxContainer/StatusContainer/StatusSelector/EndButton

func _ready() -> void:
	add_to_group("training_panel")
	# 三个属性按钮是 SelectTrainingButton：点谁就把培训目标设成谁
	for b in [_eff, _qual, _exp]:
		if b and b.has_signal("attribute_chosen"):
			b.attribute_chosen.connect(_on_attr_chosen)
	_minus.pressed.connect(_on_minus)
	_plus.pressed.connect(_on_plus)
	_start_btn.pressed.connect(_on_start)
	_end_btn.pressed.connect(_on_end)
	_plus.button_text = ""
	_minus.button_text = ""
	# 开始/结束用 NormalButton 的 button_text（它自带 tr() 且会随语言自动刷新）
	_start_btn.button_text = "Sidebar_TRAINING_START"
	_end_btn.button_text = "Sidebar_TRAINING_END"
	_apply_labels()

# 语言切换时刷新普通按钮的文字与提示（tr 写死的不会自动重译；Start/End 由 NormalButton 自己刷）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_labels()

func _apply_labels() -> void:
	# 三个属性按钮（SelectTrainingButton）自己管标签，这里不再设它们的文字
	_minus.tooltip_text = "-"
	_plus.tooltip_text = "+"
	_eff.tooltip_text = tr("Sidebar_TRAINING_ATTR_TIP")
	_qual.tooltip_text = tr("Sidebar_TRAINING_ATTR_TIP")
	_exp.tooltip_text = tr("Sidebar_TRAINING_ATTR_TIP")
	_minus.tooltip_text = tr("Sidebar_TRAINING_ROUNDS_TIP")
	_plus.tooltip_text = tr("Sidebar_TRAINING_ROUNDS_TIP")
	_start_btn.tooltip_text = tr("Sidebar_TRAINING_START_TIP")
	_end_btn.tooltip_text = tr("Sidebar_TRAINING_END_TIP")

func _process(_dt: float) -> void:
	# 圆环进度实时刷新（只在可见 + 已绑定时）
	if visible and linked_logic != null and _gauge:
		_gauge.set_progress(linked_logic.get_progress())

# office_panel 打开培训页签时调用，把当前房间的逻辑绑过来
func bind_logic(logic) -> void:
	linked_logic = logic
	refresh_from_logic(logic)

# 逻辑侧状态变化（拖入/移除/选属性/加减轮/每轮结算…）会回调这里刷新
func refresh_from_logic(logic) -> void:
	if logic != linked_logic or linked_logic == null:
		return
	# 开始后锁住加减/属性/开始，允许结束；未开始反之
	var running: bool = linked_logic.is_running
	for b in [_minus, _plus, _eff, _qual, _exp, _start_btn]:
		b.disabled = running
	# 加减按钮开始后变灰（视觉上也灰掉），选择阶段恢复
	var dim: Color = Color(0.55, 0.55, 0.55) if running else Color.WHITE
	_minus.modulate = dim
	_plus.modulate = dim
	# 中间数字：选择阶段 = 要练的总轮数；进行中 = 剩余轮数（每完成一轮 -1，倒数）
	if _gauge:
		var shown: int = linked_logic.rounds_total
		if running:
			shown = maxi(linked_logic.rounds_total - linked_logic.rounds_done, 1)
		_gauge.set_number(shown)
		_gauge.set_active(running)     # 进度百分比只在训练时显示
		if not running:
			_gauge.set_progress(0.0)   # 回到选择态：清空绿环
	_sync_attr_selection()   # 按当前所选属性，刷新三个按钮的文件夹开合
	_rebuild_avatars()

# ==========================================
# 头像区：照会议室的头像逻辑，动态生成在训员工头像 + 名字 + 所选属性当前值
# ==========================================
func _rebuild_avatars() -> void:
	for c in _avatars.get_children():
		c.queue_free()
	if linked_logic == null:
		return
	# 固定摆出 MAX_CAPACITY 个格子：有人的放头像，空的放小凳子占位
	var cap: int = TrainingRoomLogic.MAX_CAPACITY
	for i in range(cap):
		if i < linked_logic.occupants.size() and is_instance_valid(linked_logic.occupants[i]):
			_build_avatar_entry(linked_logic.occupants[i])
		else:
			_build_empty_slot()

func _build_avatar_entry(emp) -> void:
	# 头像框（裁到头部+面部）。单击→打开员工面板；双击(开始前)→移出培训室。
	# 名字/属性省去以省空间；名字改放到 tooltip，悬停可见。
	var frame := Control.new()
	frame.clip_contents = true
	# 格子在 y 轴多留一段放进度条；立绘的定位数学仍按 AVATAR_FRAME_SIZE 顶端对齐，比例布局不变
	frame.custom_minimum_size = Vector2(AVATAR_FRAME_SIZE.x, AVATAR_FRAME_SIZE.y + AVATAR_SLOT_EXTRA_Y)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.tooltip_text = emp.get_display_name() if emp.has_method("get_display_name") else str(emp.employee_name)

	# 立绘裁剪壳：立绘只显示上方 56px，格子下缘多出的空间保持干净背景（不透出胸口）
	var portrait_clip := Control.new()
	portrait_clip.clip_contents = true
	portrait_clip.size = AVATAR_FRAME_SIZE
	portrait_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait_clip)

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = AVATAR_FRAME_SIZE
	var focus_y: float = HEAD_FOCUS_R if int(emp.rarity) == int(Employee.Rarity.R) else HEAD_FOCUS_HIGH
	holder.pivot_offset = Vector2(AVATAR_FRAME_SIZE.x * 0.5, focus_y)
	holder.position = Vector2(0.0, AVATAR_FRAME_SIZE.y * 0.5 - focus_y)
	holder.scale = Vector2(HEAD_ZOOM, HEAD_ZOOM)
	portrait_clip.add_child(holder)
	AvatarHelper.apply_portrait(holder, emp.portrait, emp.rarity)

	frame.gui_input.connect(func(ev): _on_avatar_input(ev, emp))

	# 悬停时右上角出现半透明黑底"×"踢人按钮——仅未开始时给（培训中不给）。
	# 踢出 = remove_occupant：回工位、不结算（它自己也拦了 is_running）。
	if not linked_logic.is_running:
		var kick := Button.new()
		kick.text = "X"
		kick.custom_minimum_size = Vector2(18, 18)
		kick.size = Vector2(18, 18)
		kick.position = Vector2(AVATAR_FRAME_SIZE.x - 20.0, 2.0)   # 头像框内右上角
		kick.focus_mode = Control.FOCUS_NONE
		kick.visible = false
		kick.tooltip_text = tr("Sidebar_TRAINING_KICK_TIP")
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45)   # 黑，半透明（想更淡就把 a 调小）
		sb.set_corner_radius_all(9)          # = 半径的一半 → 圆形
		kick.add_theme_stylebox_override("normal", sb)
		kick.add_theme_stylebox_override("hover", sb)
		kick.add_theme_stylebox_override("pressed", sb)
		kick.add_theme_color_override("font_color", Color.WHITE)
		kick.add_theme_font_size_override("font_size", 12)
		frame.add_child(kick)
		kick.pressed.connect(func():
			if linked_logic:
				linked_logic.remove_occupant(emp)
		)
		# 悬停显隐：移到"×"上也算还在头像范围内，不隐藏；真正离开整块头像才隐藏
		var show_kick := func(): kick.visible = true
		var maybe_hide := func():
			if not frame.get_global_rect().has_point(frame.get_global_mouse_position()):
				kick.visible = false
		frame.mouse_entered.connect(show_kick)
		frame.mouse_exited.connect(maybe_hide)
		kick.mouse_entered.connect(show_kick)
		kick.mouse_exited.connect(maybe_hide)

	# 迷你属性条叠在格子下缘多出的那段空间里（不进容器布局 → 不占排版，也不压头像）
	var bar := _make_mini_bar(emp)
	bar.position = Vector2(2.0, AVATAR_FRAME_SIZE.y + AVATAR_SLOT_EXTRA_Y - MINI_BAR_HEIGHT + 0)
	bar.size = Vector2(AVATAR_FRAME_SIZE.x - 4.0, MINI_BAR_HEIGHT)
	frame.add_child(bar)
	_avatars.add_child(frame)

func _make_mini_bar(emp) -> TrainingMiniBar:
	var key: String = linked_logic._attr_key(linked_logic.chosen_attr)
	var total := 0
	var trained := 0
	match key:
		"eff":
			total = emp.efficiency
			trained = emp.trained_eff
		"qual":
			total = emp.quality
			trained = emp.trained_qual
		"exp":
			total = emp.experience
			trained = emp.trained_exp
	var bar := TrainingMiniBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.setup(ATTR_BAR_COLORS.get(key, Color.WHITE), total, trained, linked_logic.get_session_gain(emp))
	return bar

# 空位：摆一个小凳子占位（纯 texture，不可交互）
func _build_empty_slot() -> void:
	var stool := TextureRect.new()
	stool.texture = stool_texture
	stool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stool.custom_minimum_size = AVATAR_FRAME_SIZE
	stool.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stool.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 行变高后仍顶端对齐，和头像齐平
	stool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stool.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatars.add_child(stool)

# 单击头像 → 打开员工面板（踢人改用悬停出现的"×"按钮，见 _build_avatar_entry）
func _on_avatar_input(ev: InputEvent, emp) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_show_employee_panel(emp)

# 打开全局员工信息面板（和点工位上的员工、会议室头像用的是同一个）
func _show_employee_panel(emp) -> void:
	if not is_instance_valid(emp):
		return
	var panel = get_tree().get_first_node_in_group("employee_panel")
	if panel and panel.has_method("open_panel"):
		panel.open_panel(emp)

# ==========================================
# 按钮回调
# ==========================================
# 点某个属性按钮 → 设为培训目标（SelectTrainingButton.Attr 与 TrainAttr 顺序一致，可直接传）
func _on_attr_chosen(attr: int) -> void:
	if linked_logic:
		linked_logic.set_attr(attr)   # set_attr 会回调 refresh → _sync_attr_selection 刷新选中态

# 按 logic 当前选的属性，点亮对应按钮（打开文件夹），其余合上
func _sync_attr_selection() -> void:
	if linked_logic == null:
		return
	_set_sel(_eff, TrainingRoomLogic.TrainAttr.EFF)
	_set_sel(_qual, TrainingRoomLogic.TrainAttr.QUAL)
	_set_sel(_exp, TrainingRoomLogic.TrainAttr.EXP)

func _set_sel(btn, a: int) -> void:
	if btn and btn.has_method("set_selected"):
		btn.set_selected(linked_logic.chosen_attr == a)

func _on_minus() -> void:
	if linked_logic: linked_logic.sub_round()

func _on_plus() -> void:
	if linked_logic: linked_logic.add_round()

func _on_start() -> void:
	if linked_logic: linked_logic.start_training()

func _on_end() -> void:
	if linked_logic: linked_logic.end_training()
