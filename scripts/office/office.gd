# office.gd
extends Control
class_name Office

@export_group("Visuals")
@export var tex_locked: Texture2D # 拖入那张纯灰色不可用贴图
@export var tex_empty: Texture2D
@export var tex_pantry: Texture2D
@export var tex_meeting: Texture2D
@export var tex_recruitment: Texture2D
@export var tex_culture: Texture2D

@export var unlock_at_level: int = 1 # 🌟 在编辑器里设置：M1=1, M2=2...

# 引用下方的子节点用来换图
@onready var texture_display: TextureRect = $TextureRect
@onready var manage_btn: TextureButton = $ManageButton

var current_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
var logic_node: OfficeLogic = null 

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
	
	#if manage_btn:
		#manage_btn.pressed.connect(_on_manage_btn_pressed)
		
	# 监听全局等级变化
	if Gamemanager.has_signal("level_changed"):
		Gamemanager.level_changed.connect(_on_level_changed)
	
	# 1. 初始化职级判断 (这会修改 is_locked 的值)
	_on_level_changed(Gamemanager.player_level)
	
	# 🌟 核心修复：在这里强制执行全套视觉与交互同步！
	# 这样哪怕 Setter 因为值没变而拦截了，我们在ready里也强行刷一次最终状态
	_sync_visual_and_interaction()
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# 全局等级变动时，自动判断生死
func _on_level_changed(new_level: int) -> void:
	# 这里只修改数据，表现交给 Setter 和 Ready
	self.is_locked = (new_level < unlock_at_level) 
	
	if not is_locked:
		print("[Office] ", name, " 已解锁，当前职级：M", new_level)

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
	else:
		mouse_filter = Control.MOUSE_FILTER_STOP 
		if manage_btn: manage_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
# ==========================================
# 交互与点击
# ==========================================
func _gui_input(event: InputEvent) -> void:
	if is_locked: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if manage_btn and manage_btn.visible:
			if manage_btn.get_global_rect().has_point(get_global_mouse_position()):
				return 
		
		_on_office_clicked()
		
func _on_office_clicked() -> void:
	print("[Office] 点击主体，打开选型页签")
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		panel.open_panel(self, false)

#func _on_manage_btn_pressed() -> void:
	#print("[Office] 点击管理按钮，打开文化页签")
	#var panel = get_tree().get_first_node_in_group("office_panel")
	#if panel:
		#panel.open_panel(self, true)

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
	if logic_node and logic_node.has_method("on_mouse_entered"):
		logic_node.on_mouse_entered()

func _on_mouse_exited() -> void:
	if is_locked: return
	if logic_node and logic_node.has_method("on_mouse_exited"):
		logic_node.on_mouse_exited(get_global_mouse_position())

# ==========================================
# 视觉与功能切换
# ==========================================
func change_function(new_type: Gamemanager.OfficeType) -> void:
	if current_type == new_type: return
	
	if new_type == Gamemanager.OfficeType.RECRUITMENT and OfficeManager.has_recruitment_office: return
	if new_type == Gamemanager.OfficeType.CULTURE_CENTER and OfficeManager.has_culture_center: return
		
	if logic_node != null:
		logic_node.cleanup()
		logic_node = null
	
	current_type = new_type
	_update_visuals()
	
	match current_type:
		Gamemanager.OfficeType.PANTRY: logic_node = PantryLogic.new()
		Gamemanager.OfficeType.MEETING_ROOM: logic_node = MeetingRoomLogic.new()
		Gamemanager.OfficeType.RECRUITMENT: logic_node = RecruitmentOfficeLogic.new()
		Gamemanager.OfficeType.CULTURE_CENTER: logic_node = CultureCenterLogic.new()
	
	if logic_node != null:
		add_child(logic_node)
		logic_node.setup(self)
	
	print("办公室 ", name, " 已切换至: ", current_type)

# ==========================================
# 视觉显示逻辑 (核心：锁住强制显示灰图)
# ==========================================
func _update_visuals() -> void:
	# 锁住状态：强制换灰图，强制藏按钮
	if is_locked:
		if texture_display:
			# 🌟 关键：确保这里拿到了 tex_locked！
			texture_display.texture = tex_locked
			texture_display.show()
		#if manage_btn: manage_btn.hide()
		return
		
	# 解锁状态：恢复地板贴图
	var target_tex: Texture2D = tex_empty
	
	match current_type:
		Gamemanager.OfficeType.PANTRY: target_tex = tex_pantry
		Gamemanager.OfficeType.MEETING_ROOM: target_tex = tex_meeting
		Gamemanager.OfficeType.RECRUITMENT: target_tex = tex_recruitment
		Gamemanager.OfficeType.CULTURE_CENTER: target_tex = tex_culture
		_: target_tex = tex_empty
	
	if texture_display:
		texture_display.texture = target_tex
		texture_display.show()
		
	## 根据是否有功能决定管理按钮的显示
	if manage_btn:
		manage_btn.hide()
