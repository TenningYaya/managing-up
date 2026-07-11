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
const HEAD_ZOOM := 2.0
const HEAD_FOCUS_R := 16.0    # R 卡（脸偏下）
const HEAD_FOCUS_HIGH := 18.0 # SR / SSR

var linked_logic = null   # 当前绑定的 TrainingRoomLogic

@onready var _avatars: HBoxContainer = $VBoxContainer/Avatars
@onready var _eff: Button = $VBoxContainer/AttributeSelector/Eff
@onready var _qual: Button = $VBoxContainer/AttributeSelector/Qual
@onready var _exp: Button = $VBoxContainer/AttributeSelector/Exp
@onready var _minus: Button = $VBoxContainer/TurnSelector/Minus
@onready var _round_count: Label = $VBoxContainer/TurnSelector/RoundCount
@onready var _plus: Button = $VBoxContainer/TurnSelector/Plus
@onready var _progress: ProgressBar = $VBoxContainer/Progress
@onready var _start_btn = $VBoxContainer/StatusSelector/StartButton
@onready var _end_btn = $VBoxContainer/StatusSelector/EndButton

func _ready() -> void:
	add_to_group("training_panel")
	_eff.pressed.connect(_on_eff)
	_qual.pressed.connect(_on_qual)
	_exp.pressed.connect(_on_exp)
	_minus.pressed.connect(_on_minus)
	_plus.pressed.connect(_on_plus)
	_start_btn.pressed.connect(_on_start)
	_end_btn.pressed.connect(_on_end)

func _process(_dt: float) -> void:
	# 进度条实时刷新（只在可见 + 已绑定时）
	if visible and linked_logic != null:
		_progress.value = linked_logic.get_progress() * 100.0

# office_panel 打开培训页签时调用，把当前房间的逻辑绑过来
func bind_logic(logic) -> void:
	linked_logic = logic
	refresh_from_logic(logic)

# 逻辑侧状态变化（拖入/移除/选属性/加减轮/每轮结算…）会回调这里刷新
func refresh_from_logic(logic) -> void:
	if logic != linked_logic or linked_logic == null:
		return
	_round_count.text = str(linked_logic.rounds_total)
	# 开始后锁住加减/属性/开始，允许结束；未开始反之
	var running: bool = linked_logic.is_running
	for b in [_minus, _plus, _eff, _qual, _exp, _start_btn]:
		b.disabled = running
	_rebuild_avatars()

# ==========================================
# 头像区：照会议室的头像逻辑，动态生成在训员工头像 + 名字 + 所选属性当前值
# ==========================================
func _rebuild_avatars() -> void:
	for c in _avatars.get_children():
		c.queue_free()
	if linked_logic == null:
		return
	var key: String = linked_logic._attr_key(linked_logic.chosen_attr)
	for emp in linked_logic.occupants:
		if is_instance_valid(emp):
			_build_avatar_entry(emp, key)

func _build_avatar_entry(emp, key: String) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# ---- 头像框（裁到头部+面部，双击可在开始前移除该员工）----
	var frame := Control.new()
	frame.clip_contents = true
	frame.custom_minimum_size = AVATAR_FRAME_SIZE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_STOP

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = AVATAR_FRAME_SIZE
	var focus_y: float = HEAD_FOCUS_R if int(emp.rarity) == int(Employee.Rarity.R) else HEAD_FOCUS_HIGH
	holder.pivot_offset = Vector2(AVATAR_FRAME_SIZE.x * 0.5, focus_y)
	holder.position = Vector2(0.0, AVATAR_FRAME_SIZE.y * 0.5 - focus_y)
	holder.scale = Vector2(HEAD_ZOOM, HEAD_ZOOM)
	frame.add_child(holder)
	AvatarHelper.apply_portrait(holder, emp.portrait, emp.rarity)

	frame.gui_input.connect(func(ev): _on_avatar_input(ev, emp))
	col.add_child(frame)

	# ---- 名字 + 所选属性当前值（培训涨点时会随每轮刷新）----
	var lbl := Label.new()
	var nm = emp.get_display_name() if emp.has_method("get_display_name") else str(emp.employee_name)
	var val := 0
	match key:
		"eff": val = emp.efficiency
		"qual": val = emp.quality
		"exp": val = emp.experience
	lbl.text = "%s\n%s %d/10" % [nm, key, val]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.custom_minimum_size = Vector2(AVATAR_FRAME_SIZE.x, 0)
	col.add_child(lbl)

	_avatars.add_child(col)

# 双击头像 → 开始前把该员工移出培训室（开始后 remove_occupant 自己会拦掉）
func _on_avatar_input(ev: InputEvent, emp) -> void:
	if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
		if linked_logic:
			linked_logic.remove_occupant(emp)

# ==========================================
# 按钮回调
# ==========================================
func _on_eff() -> void:
	if linked_logic: linked_logic.set_attr(TrainingRoomLogic.TrainAttr.EFF)

func _on_qual() -> void:
	if linked_logic: linked_logic.set_attr(TrainingRoomLogic.TrainAttr.QUAL)

func _on_exp() -> void:
	if linked_logic: linked_logic.set_attr(TrainingRoomLogic.TrainAttr.EXP)

func _on_minus() -> void:
	if linked_logic: linked_logic.sub_round()

func _on_plus() -> void:
	if linked_logic: linked_logic.add_round()

func _on_start() -> void:
	if linked_logic: linked_logic.start_training()

func _on_end() -> void:
	if linked_logic: linked_logic.end_training()
