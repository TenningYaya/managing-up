#culture_center_logic.gd

extends OfficeLogic
class_name CultureCenterLogic

var manage_btn: Button

enum CultureType { 
	NONE, 
	EFF_UP,  # 效率+2
	QUAL_UP, # 质量+2
	EXP_UP   # 经验+2
}

var cur_type: CultureType = CultureType.NONE # 变量名也给你缩了

func setup(office: Control) -> void:
	super.setup(office)
	my_office = office
	OfficeManager.has_culture_center = true
	
	var btn = my_office.manage_btn 
	
	# 绑定悬停和点击信号
	my_office.mouse_entered.connect(_on_office_mouse_entered)
	my_office.mouse_exited.connect(_on_office_mouse_exited)
	
	# 为了防止重复绑定报错，绑定前先断开可能残留的信号 (防御性编程)
	if btn.pressed.is_connected(_on_manage_btn_pressed):
		btn.pressed.disconnect(_on_manage_btn_pressed)
	btn.pressed.connect(_on_manage_btn_pressed)
	
func switch_culture(type: CultureType) -> void:
	if cur_type == type: return
	
	_apply_culture_effect(cur_type, -1) # 撤销旧的
	cur_type = type
	_apply_culture_effect(cur_type, 1)  # 应用新的

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
	my_office.mouse_entered.disconnect(_on_office_mouse_entered)
	my_office.mouse_exited.disconnect(_on_office_mouse_exited)
	
	super.cleanup()

func _on_btn_mouse_exited() -> void:
	# 鼠标离开按钮时：如果没回到 office 区域内，就隐藏按钮
	if is_instance_valid(my_office) and is_instance_valid(manage_btn):
		var mouse_pos = my_office.get_global_mouse_position()
		if not my_office.get_global_rect().has_point(mouse_pos):
			manage_btn.hide()

func _on_office_mouse_entered() -> void:
	# 只有当功能是文化室时，这套逻辑才会生效
	my_office.manage_btn.show()

func _on_office_mouse_exited() -> void:
	var btn = my_office.manage_btn
	# 判定鼠标是不是挪到按钮上了
	var mouse_pos = btn.get_global_mouse_position()
	if not btn.get_global_rect().has_point(mouse_pos):
		btn.hide()

func _on_manage_btn_pressed() -> void:
	print("【测试】点击了制定文化按钮！")
	UiManager.open_culture_panel(self)
