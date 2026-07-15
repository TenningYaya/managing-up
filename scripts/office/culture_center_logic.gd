#culture_center_logic.gd

extends OfficeLogic
class_name CultureCenterLogic

var manage_btn: TextureButton
var cur_type: CultureType = CultureType.NONE # 变量名也给你缩了

enum CultureType { 
	NONE, 
	EFF_UP,  # 效率+2
	QUAL_UP, # 质量+2
	EXP_UP   # 经验+2
}

func setup(office: Control) -> void:
	super.setup(office)
	my_office = office
	OfficeManager.has_culture_center = true
	
	if manage_btn:
		print("[Debug] 正在为文化室绑定按钮信号: ", manage_btn.name)
	# 🌟 修正 1：不要用 var btn，直接赋值给脚本顶部那个 manage_btn 变量！
	manage_btn = my_office.manage_btn 
	
	if manage_btn.pressed.is_connected(_on_manage_btn_pressed):
		manage_btn.pressed.disconnect(_on_manage_btn_pressed)
	manage_btn.pressed.connect(_on_manage_btn_pressed)
	switch_culture(CultureType.EFF_UP)
	
func switch_culture(type: CultureType) -> void:
	
	if cur_type == type: return
	
	_apply_culture_effect(cur_type, -1) # 撤销旧的
	cur_type = type
	_apply_culture_effect(cur_type, 1)  # 应用新的
	#[员工吐槽中心]：文化室文化变更
	BanterManager.trigger_banter("culture_change", 2)

func _apply_culture_effect(type: CultureType, dir: int) -> void:
	if type == CultureType.NONE: return
	
	var val = 2 * dir
	match type:
		CultureType.EFF_UP:  OfficeManager.culture_efficiency += val
		CultureType.QUAL_UP: OfficeManager.culture_quality += val
		CultureType.EXP_UP:  OfficeManager.culture_experience += val

func cleanup() -> void:
	_apply_culture_effect(cur_type, -1) 
	OfficeManager.has_culture_center = false
	
	# ======= 🚨 关键改动：归还按钮，不要销毁 =======
	var btn = my_office.manage_btn
	btn.hide() # 藏起来
	
	# 断开点击信号，防止变成别的办公室后点击错乱
	if btn.pressed.is_connected(_on_manage_btn_pressed):
		btn.pressed.disconnect(_on_manage_btn_pressed)
		
	# 断开悬停信号
	#my_office.mouse_entered.disconnect(_on_office_mouse_entered)
	#my_office.mouse_exited.disconnect(_on_office_mouse_exited)

func _on_btn_mouse_exited() -> void:
	# 鼠标离开按钮时：如果没回到 office 区域内，就隐藏按钮
	if is_instance_valid(my_office) and is_instance_valid(manage_btn):
		var mouse_pos = my_office.get_global_mouse_position()
		if not my_office.get_global_rect().has_point(mouse_pos):
			manage_btn.hide()

func on_mouse_entered() -> void:
	# 只有当功能是文化室时，这套逻辑才会生效
	manage_btn.show() # 使用脚本顶部的 manage_btn

# 改名并接收鼠标位置参数
func on_mouse_exited(mouse_pos: Vector2) -> void:
	# 判定鼠标是不是挪到按钮上了
	var btn_rect = manage_btn.get_global_rect()
	var office_rect = my_office.get_global_rect()
	
	# 如果鼠标既不在按钮上，也不在办公室上，才隐藏
	if not btn_rect.has_point(mouse_pos) and not office_rect.has_point(mouse_pos):
		manage_btn.hide()

func _on_manage_btn_pressed() -> void:

	# 🌟 修正 2：用回你 office 里原来正确的写法，通过组去找面板
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		# 🌟 修正 3：极度重要！传过去的一定要是 my_office（办公室本体），绝不能是 self！
		panel.open_panel(my_office, true)
