# office.gd
extends Control
class_name Office

@export_group("Visuals")
# —— RoomTexture（房间底图）的三种状态 ——
@export var tex_locked: Texture2D # 未解锁：拖入那张纯灰色不可用贴图
@export var tex_empty: Texture2D  # 已解锁但还没分配功能（空置）
@export var tex_assigned: Texture2D # 已分配功能时的房间底图（留空则沿用 tex_empty）

# —— RoomIcon（功能图标）——只在"已分配功能"时显示，空置/未解锁一律隐藏
@export var tex_pantry: Texture2D
@export var tex_meeting: Texture2D
@export var tex_recruitment: Texture2D
@export var tex_culture: Texture2D
@export var tex_stock: Texture2D
@export var tex_training: Texture2D

@export var unlock_at_level: int = 1 # 🌟 在编辑器里设置：M1=1, M2=2...

# 引用下方的子节点用来换图
@onready var texture_display: TextureRect = $RoomIcon   # 房间功能图标（悬停时会放大到与 RoomTexture 重合）
@onready var room_texture: TextureRect = $RoomTexture   # 房间底图，作为图标放大的目标矩形
# 功能图标的底座/投影。跟着 RoomIcon 一起显隐（没这个节点也不报错）
@onready var room_icon_shade: CanvasItem = get_node_or_null("RoomIconShade")
@onready var manage_btn: TextureButton = $ManageButton
@onready var stock_btn: TextureButton = $StockButton
@onready var training_btn: TextureButton = $TrainingButton
@onready var empty_hint: TextureRect = $EmptyOfficeHint
@onready var updated: CanvasItem = $Updated

var current_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
var logic_node: OfficeLogic = null 
var _hint_tween: Tween = null
var _is_initialized: bool = false

# —— RoomIcon 的悬停放大 / 按下反馈 ——
const ICON_HOVER_TIME := 0.25            # 悬停缓进缓出时长（秒）
const ICON_PRESS_TIME := 0.08            # 按下/回弹时长（要短才有"按"的手感）
const ICON_PRESS_SINK := 3.0             # 按下时下沉几像素
const ICON_PRESS_DIM := Color(0.82, 0.82, 0.82, 1.0)   # 按下时压暗到这个色调
const ICON_OUTLINE_WIDTH := 2.0          # 悬停描边宽度（贴图像素）
var _icon_home_pos := Vector2.ZERO       # 图标原始位置/尺寸（鼠标移开后恢复到这里）
var _icon_home_size := Vector2.ZERO
var _icon_hovered := false
var _icon_pressed := false
var _icon_tween: Tween = null

# ==========================================
# 🌟 核心中枢：确保数据和表现同步，无死循环
# ==========================================
var is_locked: bool = true:
	set(value):
		if is_locked == value: return # 值没变，直接拦截
		
		is_locked = value
		
		# 🌟 值改变了，必须全套刷新
		_sync_visual_and_interaction()

# ==========================================
# 初始化与信号监听
# ==========================================
func _ready() -> void:
	add_to_group("offices")
	
	# EmptyOfficeHint 只是装饰性提示，绝不能拦鼠标——否则培训室空置时它盖在办公室中央，
	# 会把"拖员工进来"的落点吃掉（拖拽命中的是提示图而不是它背后的办公室）。
	if empty_hint:
		empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if manage_btn:
		manage_btn.pressed.connect(_on_manage_btn_pressed)
	if stock_btn:
		stock_btn.pressed.connect(_on_stock_btn_pressed)
	if training_btn:
		training_btn.pressed.connect(_on_training_btn_pressed)
		training_btn.button_text = "OFFICE_TRAINING"   # 按钮文字：培训 / Training（本地化 key）

	# 监听全局等级变化
	if Gamemanager.has_signal("level_changed"):
		Gamemanager.level_changed.connect(_on_level_changed)
	
	# 1. 初始化职级判断 (这会修改 is_locked 的值)
	_on_level_changed(Gamemanager.player_level)
	
	# 🌟 读档自愈：如果存档里已经有本办公室的记录，就在这里覆盖应用。
	# 这一步与 load_game() 的执行先后无关：
	#   - 若 load_game 先跑：数据已缓存，这里直接取用恢复。
	#   - 若 load_game 后跑：load_game 会再扫一遍 offices 组补上。
	# 两种顺序都能保证解锁/功能不丢。
	_apply_saved_state_if_any()
	
	# 🌟 核心修复：在这里强制执行全套视觉与交互同步！
	# 这样哪怕 Setter 因为值没变而拦截了，我们在ready里也强行刷一次最终状态
	_sync_visual_and_interaction()
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# 记下图标的原始矩形（鼠标移开后恢复用）。RoomIcon 不受容器管理，
	# 这里直接按场景里的 offset 推算，不依赖布局是否已完成，最稳。
	if texture_display:
		_icon_home_pos = Vector2(texture_display.offset_left, texture_display.offset_top)
		_icon_home_size = Vector2(
			texture_display.offset_right - texture_display.offset_left,
			texture_display.offset_bottom - texture_display.offset_top
		)
		# ⚠️ 场景里的 ShaderMaterial 是 SubResource，多个办公室实例默认【共享同一份】。
		#    不复制的话，鼠标悬停一间办公室会让所有办公室一起亮描边。这里给每间一份独立副本。
		if texture_display.material != null:
			texture_display.material = texture_display.material.duplicate()

	_is_initialized = true
	
# 全局等级变动时，自动判断生死
func _on_level_changed(new_level: int) -> void:
	if new_level >= unlock_at_level:
		# 🌟【核心判断】：之前锁着 + 已初始化 + 不是在读档,才是"真·实时升级瞬间"。
		# (读档时设置等级也会进这里,但 is_loading_save 会拦掉,避免一进游戏就放特效)
		if is_locked and _is_initialized and not Gamemanager.is_loading_save:
			_play_upgrade_bounce_fx() # 爆裂闪烁！
			
		self.is_locked = false

# ==========================================
# 🌟 读档自愈：向 SaveManager 索取本办公室的存档状态并应用
# ==========================================
func _get_save_manager() -> Node:
	# 不靠 autoload 名字硬编码，直接在 /root 下找带有恢复方法的单例，
	# 这样无论你的 SaveManager 注册成什么名字都能找到。
	for child in get_tree().root.get_children():
		if child.has_method("get_saved_office_state"):
			return child
	return null

func _apply_saved_state_if_any() -> void:
	var sm = _get_save_manager()
	if sm == null:
		return
	var saved = sm.get_saved_office_state(name)
	if saved.is_empty():
		return
	# 只解锁、不回锁：存档说解锁就解锁
	if not bool(saved.get("is_locked", true)):
		self.is_locked = false
	# 恢复功能类型
	var saved_type := int(saved.get("current_type", Gamemanager.OfficeType.NONE))
	if not is_locked and saved_type != Gamemanager.OfficeType.NONE:
		change_function(saved_type)

# ==========================================
# 🌟 核心修复：数据表现一键同步 (代替原本分散的两个函数)
# ==========================================
func _sync_visual_and_interaction():
	# 1. 刷新视觉 (视觉函数保留原样，但在内部被调用)
	_update_visuals()
	
	# 2. 同步交互开关
	if is_locked:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if manage_btn: manage_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if stock_btn: stock_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if training_btn: training_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		mouse_filter = Control.MOUSE_FILTER_STOP
		if manage_btn: manage_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if stock_btn: stock_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if training_btn: training_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
# ==========================================
# 交互与点击
# ==========================================
func _gui_input(event: InputEvent) -> void:
	if is_locked: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if manage_btn and manage_btn.visible:
			if manage_btn.get_global_rect().has_point(get_global_mouse_position()):
				_on_manage_btn_pressed()   # 点在管理按钮上 → 直接开 Culture 页签
				return

		if stock_btn and stock_btn.visible:
			if stock_btn.get_global_rect().has_point(get_global_mouse_position()):
				_on_stock_btn_pressed()   # 点在炒股按钮上 → 直接开 Stock 页签
				return

		if training_btn and training_btn.visible:
			if training_btn.get_global_rect().has_point(get_global_mouse_position()):
				_on_training_btn_pressed()   # 点在培训按钮上 → 直接开培训页签
				return

		# 点在主区域（不是那几个悬停按钮）：图标下沉+压暗，给出"按下去了"的反馈
		_icon_pressed = true
		_apply_icon_state(true)
		_on_office_clicked()

	# 松开左键：图标回弹。单独一个分支，因为上面那段只处理 pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _icon_pressed:
			_icon_pressed = false
			_apply_icon_state(true)
		
func _on_office_clicked() -> void:
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		# 点主区域一律打开“选择办公室”页签；要进培训页请点悬停出来的“培训”按钮
		panel.open_panel(self, false)

# 供 TrainingRoomLogic 调用：培训室没人时摇晃 EmptyOfficeHint、有人时收起
func set_empty_hint_active(active: bool) -> void:
	if not empty_hint:
		return
	if active:
		empty_hint.show()
		_play_hint_wobble_animation()
	else:
		empty_hint.hide()
		if _hint_tween and _hint_tween.is_valid():
			_hint_tween.kill()
		empty_hint.rotation = 0.0

# 企业文化室专属：点管理按钮直接打开 Culture 页签（而不是选办公室那一页）
func _on_manage_btn_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		panel.open_panel(self, true)  # true = 直接定位到 Culture 页签

# 炒股办公室专属：点炒股按钮直接打开 Stock 页签
func _on_stock_btn_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		panel.open_panel(self, false, true)  # 第三参数 true = 直接定位到 Stock 页签

# 培训室专属：点培训按钮直接打开 Training 页签
func _on_training_btn_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		panel.open_panel(self, false, false, true)  # 第四参数 true = 直接定位到培训页签

# ==========================================
# 拖拽与悬停
# ==========================================
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if is_locked: return false
	if logic_node and logic_node.has_method("can_drop_employee"):
		return logic_node.can_drop_employee(data)
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if logic_node and logic_node.has_method("drop_employee"):
		logic_node.drop_employee(data)

func _on_mouse_entered() -> void:
	if is_locked: return
	_icon_hovered = true
	_apply_icon_state()
	if logic_node and logic_node.has_method("on_mouse_entered"):
		logic_node.on_mouse_entered()

func _on_mouse_exited() -> void:
	if is_locked: return
	var mouse_pos := get_global_mouse_position()
	# ⚠️ 鼠标移到子按钮（管理/炒股/培训…）上时，父级 Office 也会收到 mouse_exited。
	#    此时鼠标其实还在办公室范围内，不该收回图标，否则会来回抖动。
	if not get_global_rect().has_point(mouse_pos):
		_icon_hovered = false
		_icon_pressed = false   # 按住不放直接划出去：也要松开，否则图标卡在按下态
		_apply_icon_state()
	if logic_node and logic_node.has_method("on_mouse_exited"):
		logic_node.on_mouse_exited(mouse_pos)

# RoomIcon 的表现只由 (_icon_hovered, _icon_pressed) 两个状态决定，统一在这里算目标值。
# 用【单个】tween 同时补间位置/尺寸/色调，避免"悬停动画"和"按下动画"抢同一个属性打架。
func _apply_icon_state(fast: bool = false) -> void:
	if texture_display == null or not texture_display.visible:
		return   # 空置/未解锁时图标是藏着的，没必要为它跑动画
	if _icon_home_size == Vector2.ZERO:
		return

	# 未按下时的基准矩形：悬停 = 与 RoomTexture 完全重合；否则 = 原始矩形
	var base_pos := _icon_home_pos
	var base_size := _icon_home_size
	if _icon_hovered and room_texture != null:
		base_pos = room_texture.position
		base_size = room_texture.size

	var target_pos: Vector2 = base_pos + (Vector2(0.0, ICON_PRESS_SINK) if _icon_pressed else Vector2.ZERO)
	var target_mod: Color = ICON_PRESS_DIM if _icon_pressed else Color.WHITE
	var dur: float = ICON_PRESS_TIME if fast else ICON_HOVER_TIME

	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()
	_icon_tween = create_tween().set_parallel(true)
	_icon_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_icon_tween.tween_property(texture_display, "position", target_pos, dur)
	_icon_tween.tween_property(texture_display, "size", base_size, dur)
	_icon_tween.tween_property(texture_display, "modulate", target_mod, dur)

	_set_icon_outline(_icon_hovered)

# 悬停描边开关（改 shader 的 outline_width 参数；材质已在 _ready 里复制成每间独立）
func _set_icon_outline(active: bool) -> void:
	if texture_display == null:
		return
	var mat = texture_display.material
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(
			"outline_width", ICON_OUTLINE_WIDTH if active else 0.0
		)

# ==========================================
# 视觉与功能切换
# ==========================================
func change_function(new_type: Gamemanager.OfficeType) -> void:
	if current_type == new_type: return

	if current_type == Gamemanager.OfficeType.RECRUITMENT:
		OfficeManager.has_recruitment_office = false
		Gamemanager.has_recruitment_office = false # 两个单例同步扒掉，防错乱
	elif current_type == Gamemanager.OfficeType.CULTURE_CENTER:
		OfficeManager.has_culture_center = false
		Gamemanager.has_culture_center = false
	elif current_type == Gamemanager.OfficeType.STOCK_OFFICE:
		OfficeManager.has_stock_office = false
		Gamemanager.has_stock_office = false
		
	if is_instance_valid(logic_node) and logic_node.has_method("cleanup"):
		logic_node.cleanup()
	elif is_instance_valid(logic_node):
		# 如果活着但没写 cleanup，直接超度
		logic_node.queue_free()
		
	# 强行清空引用，彻底斩断残影
	logic_node = null
	manage_btn.hide()
	if stock_btn: stock_btn.hide()
	if training_btn: training_btn.hide()
			
	# ====================================================
	# 💥 2. 迎新：如果新建的是唯一办公室，立刻把坑位占死！
	# （如果你已经在其他地方写了占位逻辑，这里可以不写；如果没有，建议统管）
	# ====================================================
	if new_type == Gamemanager.OfficeType.RECRUITMENT:
		OfficeManager.has_recruitment_office = true
		Gamemanager.has_recruitment_office = true
	elif new_type == Gamemanager.OfficeType.CULTURE_CENTER:
		OfficeManager.has_culture_center = true
		Gamemanager.has_culture_center = true
		
	# ====================================================
	# 3. 下面继续保留你原本的更换节点、加载场景等核心逻辑...
	# ====================================================
	current_type = new_type
	
	current_type = new_type
	_update_visuals()
	
	match current_type:
		Gamemanager.OfficeType.PANTRY: logic_node = PantryLogic.new()
		Gamemanager.OfficeType.MEETING_ROOM: logic_node = MeetingRoomLogic.new()
		Gamemanager.OfficeType.RECRUITMENT: logic_node = RecruitmentOfficeLogic.new()
		Gamemanager.OfficeType.CULTURE_CENTER: logic_node = CultureCenterLogic.new()
		Gamemanager.OfficeType.STOCK_OFFICE: logic_node = StockOfficeLogic.new()
		Gamemanager.OfficeType.TRAINING_ROOM: logic_node = TrainingRoomLogic.new()
		
	if logic_node != null:
		add_child(logic_node)
		logic_node.setup(self)

# ==========================================
# 视觉显示逻辑 (核心：锁住强制显示灰图)
# ==========================================
# 功能类型 → RoomIcon 上显示的功能图标
func _function_icon(t: Gamemanager.OfficeType) -> Texture2D:
	match t:
		Gamemanager.OfficeType.PANTRY:         return tex_pantry
		Gamemanager.OfficeType.MEETING_ROOM:   return tex_meeting
		Gamemanager.OfficeType.RECRUITMENT:    return tex_recruitment
		Gamemanager.OfficeType.CULTURE_CENTER: return tex_culture
		Gamemanager.OfficeType.STOCK_OFFICE:   return tex_stock
		Gamemanager.OfficeType.TRAINING_ROOM:  return tex_training
		_:                                     return null

func _update_visuals() -> void:
	# 分工：RoomTexture = 房间底图（未解锁 / 空置 / 已分配 三态）
	#      RoomIcon    = 功能图标（只在已分配功能时出现，其余一律隐藏）

	# 锁住状态：底图换灰图，功能图标藏起来
	if is_locked:
		if room_texture:
			room_texture.texture = tex_locked
		if texture_display:
			texture_display.hide()
		if room_icon_shade:
			room_icon_shade.hide()
		if empty_hint:
			empty_hint.hide()
			if _hint_tween and _hint_tween.is_valid():
				_hint_tween.kill()
		return

	var has_function := current_type != Gamemanager.OfficeType.NONE

	# 房间底图：已分配用 tex_assigned（没配就退回 tex_empty，不至于变空白），空置用 tex_empty
	if room_texture:
		if has_function:
			room_texture.texture = tex_assigned if tex_assigned != null else tex_empty
		else:
			room_texture.texture = tex_empty

	# 功能图标（连同它的底座/投影）：只有分配了功能才显示
	if room_icon_shade:
		room_icon_shade.visible = has_function
	if texture_display:
		if has_function:
			texture_display.texture = _function_icon(current_type)
			texture_display.show()
			# 重新出现时若鼠标不在房间上，先回到原始矩形，避免停在上次悬停放大的状态
			if not _icon_hovered:
				_apply_icon_state(true)
		else:
			texture_display.hide()

	if empty_hint:
		if current_type == Gamemanager.OfficeType.NONE:
			empty_hint.show()
			_play_hint_wobble_animation() # 启动摇摆！
		elif current_type == Gamemanager.OfficeType.TRAINING_ROOM:
			pass  # 培训室的空置提示交给 TrainingRoomLogic 按"有没有人在训"来驱动
		else:
			empty_hint.hide()
			# 有功能了，杀掉动画，把角度归零，省内存且干净
			if _hint_tween and _hint_tween.is_valid():
				_hint_tween.kill()
			empty_hint.rotation = 0.0
			
	## 管理按钮只在企业文化室出现（此处已过 is_locked 判定，锁定时上面已 return）
	if manage_btn:
		manage_btn.visible = (current_type == Gamemanager.OfficeType.CULTURE_CENTER)
	## 炒股按钮只在炒股办公室出现
	if stock_btn:
		stock_btn.visible = (current_type == Gamemanager.OfficeType.STOCK_OFFICE)

func _play_hint_wobble_animation():
	if not empty_hint: return
	
	empty_hint.pivot_offset = empty_hint.size / 2.0
	
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
		
	# 确保起始角度是 0
	empty_hint.rotation = 0.0
	
	_hint_tween = create_tween().set_loops()
	
	var angle = deg_to_rad(10.0)
	var t_short = 0.12 # 从中心到两侧的时间，速度比之前快了好几倍
	var t_long = 0.24  # 从左侧直接甩到右侧的时间（距离翻倍，时间翻倍，保持速度一致）
	
	# ================= 第 1 次晃动 =================
	# 1. 往右甩
	_hint_tween.tween_property(empty_hint, "rotation", angle, t_short).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 2. 从右边直接甩到最左边
	_hint_tween.tween_property(empty_hint, "rotation", -angle, t_long).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 3. 回到正中心
	_hint_tween.tween_property(empty_hint, "rotation", 0.0, t_short).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# ================= 第 2 次晃动 =================
	# 1. 往右甩
	_hint_tween.tween_property(empty_hint, "rotation", angle, t_short).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 2. 从右边直接甩到最左边
	_hint_tween.tween_property(empty_hint, "rotation", -angle, t_long).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 3. 回到正中心
	_hint_tween.tween_property(empty_hint, "rotation", 0.0, t_short).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# ================= 停顿休息 =================
	# 原地停顿 1 秒钟
	_hint_tween.tween_interval(1.0)

func _play_upgrade_bounce_fx() -> void:
	if not updated: return
	
	# 1. 激活显示，并把不透明度(Alpha)拉满
	updated.show()
	updated.modulate.a = 1.0
	
	# 2. 自动让序列帧/粒子重新播放
	if updated.has_method("play"):
		updated.play()
	elif updated.has_method("restart"):
		updated.restart()
		
	# 3. 🎬 重新编排高级动画序列：
	var fx_tween = create_tween()
	
	# ⏳ 核心改动：前 3.5 秒什么都不做，让特效大放异彩
	fx_tween.tween_interval(3.5)
	
	# 📉 最后的 1.5 秒内，快速平滑地淡出到 0.0 (总计刚好 5 秒)
	fx_tween.tween_property(updated, "modulate:a", 0.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# 4. 彻底消失后隐藏节点，省下显卡渲染力
	fx_tween.tween_callback(updated.hide)
