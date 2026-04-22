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
	
	# ======= 1. 动态生成“悬停按钮” =======
	manage_btn = Button.new()
	manage_btn.text = "制定文化"
	manage_btn.hide()
	
	# 加入场景树，并设置在办公室正下方
	office.add_child(manage_btn)
	manage_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# 往下挪一点，刚好挂在办公室框的下面 (具体数值可根据你的 UI 尺寸微调)
	manage_btn.position.y = office.size.y + 5 
	
	# ======= 2. 绑定 UI 信号 =======
	office.mouse_entered.connect(_on_office_mouse_entered)
	office.mouse_exited.connect(_on_office_mouse_exited)
	manage_btn.mouse_exited.connect(_on_btn_mouse_exited)
	
	# 绑定点击事件
	manage_btn.pressed.connect(_on_manage_btn_pressed)
	
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
	_apply_culture_effect(cur_type, -1) # 拆除时自动回滚数值，防止刷属性
	OfficeManager.has_culture_center = false
	if is_instance_valid(manage_btn):
		manage_btn.queue_free()
	super.cleanup()

func _on_office_mouse_entered() -> void:
	if is_instance_valid(manage_btn):
		manage_btn.show()

func _on_office_mouse_exited() -> void:
	# Godot 悬停神坑：鼠标从 office 挪到 button 上，会触发 office 的 exited！
	# 所以必须判定：鼠标是不是挪到按钮上了？如果没挪到按钮上，才隐藏。
	if is_instance_valid(manage_btn):
		var mouse_pos = manage_btn.get_global_mouse_position()
		if not manage_btn.get_global_rect().has_point(mouse_pos):
			manage_btn.hide()

func _on_btn_mouse_exited() -> void:
	# 鼠标离开按钮时：如果没回到 office 区域内，就隐藏按钮
	if is_instance_valid(my_office) and is_instance_valid(manage_btn):
		var mouse_pos = my_office.get_global_mouse_position()
		if not my_office.get_global_rect().has_point(mouse_pos):
			manage_btn.hide()

func _on_manage_btn_pressed() -> void:
	print("弹出企业文化面板！")
	
	# 🚨 在这里呼叫你的右侧面板！
	# 比如：UIManager.open_culture_panel(self)
	# 面板做出来后，面板上的三个选项按钮点下去，
	# 只需要调用传过去的这个类的 switch_culture(CultureType.EFF_UP) 即可！
