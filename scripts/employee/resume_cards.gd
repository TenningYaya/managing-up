# resume_card.gd
# 专门用于“招聘面板”里显示候选人简历的脚本

extends Control

# 直接用固定的节点路径，简单粗暴！
# （⚠️ 记得把下面的 $路径 换成你新场景里真实的节点路径）
@onready var name_label: Label = $HBoxContainer/VBoxContainer/NameLabel
@onready var rarity_label: Label = $HBoxContainer/AvatarArea/RarityLabel
@onready var eff_bar: ProgressBar = $HBoxContainer/VBoxContainer/StatsBars/EfficiencyBar
@onready var qual_bar: ProgressBar = $HBoxContainer/VBoxContainer/StatsBars/QualityBar
@onready var exp_bar: ProgressBar = $HBoxContainer/VBoxContainer/StatsBars/ExperienceBar
@onready var hire_price_label: Label = $HBoxContainer/VBoxContainer/HirePriceLabel
@onready var avatar_img: TextureRect = $HBoxContainer/AvatarArea/Avatar

# 提供给 ResumeViewer 调用的接口
func setup(employee_data: Employee) -> void:
	if employee_data == null: 
		return
	
	# 1. 设置名字
	name_label.text = employee_data.employee_name
	
	# 2. 设置稀有度显示 (根据你的游戏设定，SSR 只有猎头才能出)
	match employee_data.rarity:
		Employee.Rarity.R:
			rarity_label.text = " R "
			rarity_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
		Employee.Rarity.SR:
			rarity_label.text = " SR "
			rarity_label.add_theme_color_override("font_color", Color.MEDIUM_PURPLE)
		Employee.Rarity.SSR:
			rarity_label.text = " SSR "
			rarity_label.add_theme_color_override("font_color", Color.GOLD)
			
	# 3. 设置属性条
	eff_bar.max_value = 10
	eff_bar.value = employee_data.efficiency
	
	qual_bar.max_value = 10
	qual_bar.value = employee_data.quality
	
	exp_bar.max_value = 10
	exp_bar.value = employee_data.experience
	
	var total_stats = employee_data.efficiency + employee_data.quality + employee_data.experience
	var cost_kpi = total_stats * 10
	
	# 将计算结果填入那个 1000 KPI 的位置
	if hire_price_label:
		hire_price_label.text = str(cost_kpi) + " KPI"
		
	if employee_data.portrait:
		# 1. 无论什么级别，先显示主体（身体）
		avatar_img.texture = employee_data.portrait
		
		# 2. 自动化层叠处理：检查是否有头发和衣服的 Meta 数据
		# 这样即使是同学做的 UI，只要用了这个逻辑，就能自动兼容你的多层随机小人
		_update_avatar_layers(employee_data.portrait)
	
func _update_avatar_layers(main_tex: Texture2D):
	# 查找或创建层叠节点（避免在编辑器里手动摆放一堆空的 TextureRect）
	# 如果你已经在场景里摆好了 Hair 和 Clothes 节点，可以直接 get_node
	var hair_layer = avatar_img.get_node_or_null("Hair")
	var cloth_layer = avatar_img.get_node_or_null("Clothes")

	# 处理头发层
	if main_tex.has_meta("hair_tex"):
		if not hair_layer: # 如果没有就动态建一个，省去美术手动加节点的麻烦
			hair_layer = _create_layer_node("Hair")
		
		var atlas = AtlasTexture.new()
		atlas.atlas = main_tex.get_meta("hair_tex")
		atlas.region = main_tex.get_meta("hair_rect")
		hair_layer.texture = atlas
	elif hair_layer:
		hair_layer.texture = null # 没头发就清空

	# 处理衣服层
	if main_tex.has_meta("clothes_tex"):
		if not cloth_layer:
			cloth_layer = _create_layer_node("Clothes")
			
		var atlas = AtlasTexture.new()
		atlas.atlas = main_tex.get_meta("clothes_tex")
		atlas.region = main_tex.get_meta("clothes_rect")
		cloth_layer.texture = atlas
	elif cloth_layer:
		cloth_layer.texture = null

# 动态创建层叠节点的工具函数
func _create_layer_node(layer_name: String) -> TextureRect:
	var tr = TextureRect.new()
	tr.name = layer_name
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE # 保持和父节点一致
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # 铺满父节点
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE # 别挡住点击
	avatar_img.add_child(tr)
	return tr
