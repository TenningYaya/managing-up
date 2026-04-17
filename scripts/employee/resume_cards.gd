# resume_card.gd
# 专门用于“招聘面板”里显示候选人简历的脚本

extends Control

# 直接用固定的节点路径，简单粗暴！
# （⚠️ 记得把下面的 $路径 换成你新场景里真实的节点路径）
@onready var name_label: Label = $HBoxContainer/VBoxContainer/NameLabel
@onready var rarity_label: Label = $HBoxContainer/AvatarArea/RarityLabel
@onready var eff_bar: ProgressBar = $HBoxContainer/VBoxContainer/StatsBars/ExperienceBar
@onready var qual_bar: ProgressBar = $HBoxContainer/VBoxContainer/StatsBars/QualityBar
@onready var exp_bar: ProgressBar = $HBoxContainer/VBoxContainer/StatsBars/ExperienceBar

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
