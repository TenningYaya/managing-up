# resume_card.gd
# 专门用于“招聘面板”里显示候选人简历的脚本

extends Control

# 🌟 节点引用：类型已经完美升级为通用的 PropertyBar 组件
@onready var name_label: Label = $HBoxContainer/VBoxContainer/Control/NameLabel
@onready var rarity_label: Label = $HBoxContainer/AvatarArea/RarityLabel
@onready var eff_bar: PropertyBar = $HBoxContainer/VBoxContainer/StatsBars/EfficiencyBar
@onready var qual_bar: PropertyBar = $HBoxContainer/VBoxContainer/StatsBars/QualityBar
@onready var exp_bar: PropertyBar = $HBoxContainer/VBoxContainer/StatsBars/ExperienceBar
@onready var hire_price_label: Label = $HBoxContainer/VBoxContainer/HirePriceLabel
@onready var avatar_img: TextureRect = $HBoxContainer/AvatarArea/Avatar

# 提供给 ResumeViewer 调用的接口
func setup(employee_data: Employee) -> void:
		
	if employee_data == null: 
		return

	# 1. 设置名字（先直接赋值，然后调自适应函数）
	_apply_name_with_auto_scale(employee_data.employee_name)
	
	# 2. 设置稀有度显示
	match employee_data.rarity:
		Employee.Rarity.R:
			rarity_label.text = " R "
			rarity_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
		Employee.Rarity.SR:
			rarity_label.text = " SR "
			rarity_label.add_theme_color_override("font_color", Color.GREEN_YELLOW)
		Employee.Rarity.SSR:
			rarity_label.text = " SSR "
			rarity_label.add_theme_color_override("font_color", Color.GOLD)
			
	# 3. 🌟 核心修改：调用我们全新的、避开冲突的 set_bar_value 传入机制！
	# 进度条的最大值、数字文本刷新、Inspector 调配好的颜色都会在组件内部自动完美处理
	if eff_bar:
		eff_bar.set_bar_value(employee_data.efficiency)
	
	if qual_bar:
		qual_bar.set_bar_value(employee_data.quality)
	
	if exp_bar:
		exp_bar.set_bar_value(employee_data.experience)
	
	# 计算总和与价格
	var cost_kpi = RecruitmentManager.calculate_hire_cost(employee_data)
	
	# 将计算结果填入
	if hire_price_label:
		hire_price_label.text = str(cost_kpi) + " KPI"
		
	if employee_data.portrait:
		AvatarHelper.apply_portrait(avatar_img, employee_data.portrait, employee_data.rarity)

func _apply_name_with_auto_scale(new_name: String):
	name_label.text = new_name
	
	# 关键：等一帧。让外部容器把 Control 的实际大小分配好
	await get_tree().process_frame
	
	if not is_instance_valid(name_label): return
	
	set_employee_name(new_name)

# 动态创建层叠节点的工具函数
func _create_layer_node(layer_name: String) -> TextureRect:
	var tr = TextureRect.new()
	tr.name = layer_name
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_img.add_child(tr)
	return tr

func set_employee_name(new_name: String):
	name_label.text = new_name
	
	# 第一步：重置缩放
	name_label.scale = Vector2.ONE
	
	# 第二步：获取父节点（Control 容器）的宽度作为终极参考
	var wrapper = name_label.get_parent()
	var max_w = wrapper.size.x
	
	# 设置缩放中心。基于外层防弹衣的中心来缩放，保证永远居中
	name_label.pivot_offset = Vector2(max_w / 2.0, name_label.size.y / 2.0)
	
	# 第三步：计算这段文字需要多宽
	var font = name_label.get_theme_font("font")
	var font_size = name_label.get_theme_font_size("font_size")
	var text_w = font.get_string_size(new_name, name_label.horizontal_alignment, -1, font_size).x
	
	# 第四步：如果需要的宽度 > 容器宽度，压扁它！
	if text_w > max_w and max_w > 0:
		name_label.scale.x = max_w / text_w
	else:
		name_label.scale.x = 1.0
