# office.gd
extends Control
class_name Office

# 在编辑器里拖入对应的贴图
@export_group("Visuals")
@export var tex_empty: Texture2D
@export var tex_pantry: Texture2D
@export var tex_meeting: Texture2D
@export var tex_recruitment: Texture2D
@export var tex_bulletin: Texture2D

# 引用下方的子节点用来换图
@onready var texture_display: TextureRect = $TextureRect

# 核心数据
# 注意：确保你的单例名大小写一致，如果是 Gamemanager 就用 Gamemanager
var current_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
var logic_node: OfficeLogic = null 

func _ready() -> void:
	add_to_group("offices")
	set_deferred("mouse_filter", Control.MOUSE_FILTER_STOP)
	_update_visuals()

# 替代 TextureButton 的 pressed 信号
#func _gui_input(event: InputEvent) -> void:
	#if event is InputEventMouseButton:
		## 判断是鼠标左键且是按下动作
		#if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			#_on_office_clicked()
			## 标记事件已处理，防止穿透
			#accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 如果当前已经点中了某个 UI（比如面板），就不再触发办公室逻辑
		# get_viewport().gui_get_focus_owner() 或者检查全局 UI 状态
		
		var m_pos = get_global_mouse_position()
		if get_global_rect().has_point(m_pos):
			# 只有当办公室是可见的，且没有被面板盖住时才执行
			print("【强行拦截】点到了办公室: ", name)
			_on_office_clicked()
			get_viewport().set_input_as_handled()
			
# 点击事件
func _on_office_clicked() -> void:
	print("--- 准备发送信号 ---")
	print("当前点击的节点名字: ", name)
	get_tree().call_group("office_panel", "open_panel", self)
	print("信号已发送给 office_panel 组")

# 切换功能的核心函数
func change_function(new_type: Gamemanager.OfficeType) -> void:
	if current_type == new_type:
		return
	
	# 1. 卸载旧逻辑
	if logic_node != null:
		logic_node.cleanup()
		logic_node = null
	
	# 2. 更新状态
	current_type = new_type
	_update_visuals()
	
	# 3. 装载新逻辑
	match current_type:
		Gamemanager.OfficeType.PANTRY:
			logic_node = PantryLogic.new()
		Gamemanager.OfficeType.MEETING_ROOM:
			logic_node = MeetingRoomLogic.new()
	
	# 4. 激活新逻辑
	if logic_node != null:
		add_child(logic_node)
		logic_node.setup(self)
	
	print("办公室 ", name, " 已切换至: ", current_type)

# 更新贴图
func _update_visuals() -> void:
	var target_tex: Texture2D = tex_empty
	
	match current_type:
		Gamemanager.OfficeType.PANTRY: target_tex = tex_pantry
		Gamemanager.OfficeType.MEETING_ROOM: target_tex = tex_meeting
		Gamemanager.OfficeType.RECRUITMENT: target_tex = tex_recruitment
		Gamemanager.OfficeType.BULLETIN_BOARD: target_tex = tex_bulletin
		_: target_tex = tex_empty
	
	# 修改 TextureRect 的贴图
	if texture_display:
		texture_display.texture = target_tex
