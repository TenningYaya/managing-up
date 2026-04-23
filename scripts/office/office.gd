# office.gd
extends Control
class_name Office

# 在编辑器里拖入对应的贴图
@export_group("Visuals")
@export var tex_empty: Texture2D
@export var tex_pantry: Texture2D
@export var tex_meeting: Texture2D
@export var tex_recruitment: Texture2D
@export var tex_culture: Texture2D

# 引用下方的子节点用来换图
@onready var texture_display: TextureRect = $TextureRect
@onready var manage_btn: TextureButton = $ManageButton

# 核心数据
# 注意：确保你的单例名大小写一致，如果是 Gamemanager 就用 Gamemanager
var current_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
var logic_node: OfficeLogic = null 

func _ready() -> void:
	add_to_group("offices")
	set_deferred("mouse_filter", Control.MOUSE_FILTER_STOP)
	_update_visuals()
	
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		
		# 🌟 保底防误触：如果鼠标确实点在了暴露的管理按钮上，直接退出
		# (其实只要管理按钮的 Mouse Filter 是 Stop，这一步连写都不用写，
		# 因为按钮会把点击吃掉，_gui_input 根本就不会触发。但加上更保险)
		if manage_btn and manage_btn.visible:
			if manage_btn.get_global_rect().has_point(get_global_mouse_position()):
				return 
		
		# 正常触发打开功能面板
		_on_office_clicked()
		
# 点击事件
func _on_office_clicked() -> void:
	print("【测试】触发了打开普通办公室面板！")
	get_tree().call_group("office_panel", "open_panel", self)
	

# 切换功能的核心函数
func change_function(new_type: Gamemanager.OfficeType) -> void:
	if current_type == new_type:
		return
	
	# --- 最终防线：检查唯一性 ---
	if new_type == Gamemanager.OfficeType.RECRUITMENT and OfficeManager.has_recruitment_office:
		return
	if new_type == Gamemanager.OfficeType.CULTURE_CENTER and OfficeManager.has_culture_center:
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
		Gamemanager.OfficeType.RECRUITMENT:
			logic_node = RecruitmentOfficeLogic.new()
		Gamemanager.OfficeType.CULTURE_CENTER:
			logic_node = CultureCenterLogic.new()
	
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
		Gamemanager.OfficeType.CULTURE_CENTER: target_tex = tex_culture
		_: target_tex = tex_empty
	
	# 修改 TextureRect 的贴图
	if texture_display:
		texture_display.texture = target_tex
