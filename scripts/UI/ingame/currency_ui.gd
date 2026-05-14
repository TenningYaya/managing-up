extends Control

# 这里先不要写路径，等下我们在 Inspector 里手动拖图片进去
@export var up_arrow_texture: Texture2D 
@export var down_arrow_texture: Texture2D

# Label 引用
@onready var kpi_label: Label = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/KPI/KPILabel
@onready var dollar_label: Label = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/dollar/DollarLabel
@onready var eff_label: Label = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/EFF_/EFF_Label

# Arrow 引用
@onready var kpi_arrow: TextureRect = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/KPI/KPIArrow
@onready var dollar_arrow: TextureRect = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/dollar/DollarsArrow
@onready var eff_arrow: TextureRect = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/EFF_/EFF_Arrow

# 记录上一次的数值，用来判断涨了还是跌了
var last_kpi: float = 0
var last_dollar: float = 0
var last_eff: float = 0


func _ready():
	# 先记录初始值
	last_kpi = Gamemanager.kpi
	last_dollar = Gamemanager.dollar
	
	# 如果你的 Gamemanager 里现在还没有 eff，可以先注释掉这一行
	# last_eff = Gamemanager.eff

	# 初始刷新 UI
	update_labels()

	# 连接信号
	Gamemanager.kpi_changed.connect(_on_kpi_updated)
	Gamemanager.dollar_changed.connect(_on_dollar_updated)

	# 如果你以后有 eff_changed 信号，再打开这一行
	# Gamemanager.eff_changed.connect(_on_eff_updated)


func _on_kpi_updated(new_value):
	update_value_label(kpi_label, kpi_arrow, last_kpi, new_value)
	last_kpi = new_value


func _on_dollar_updated(new_value):
	update_value_label(dollar_label, dollar_arrow, last_dollar, new_value)
	last_dollar = new_value


func _on_eff_updated(new_value):
	update_value_label(eff_label, eff_arrow, last_eff, new_value)
	last_eff = new_value


func update_labels():
	kpi_label.text = format_number(Gamemanager.kpi)
	dollar_label.text = format_number(Gamemanager.dollar)

	# 如果你现在还没有 eff，先让它显示 0
	eff_label.text = format_number(0)

	kpi_arrow.hide()
	dollar_arrow.hide()
	eff_arrow.hide()


func update_value_label(label_node: Label, arrow_node: TextureRect, old_value: float, new_value: float):
	label_node.text = format_number(new_value)

	if new_value > old_value:
		arrow_node.texture = up_arrow_texture
		arrow_node.show()
	elif new_value < old_value:
		arrow_node.texture = down_arrow_texture
		arrow_node.show()
	else:
		arrow_node.hide()


func format_number(value: float) -> String:
	var abs_value = abs(value)

	if abs_value >= 1000000000:
		return str(round(value / 100000000.0) / 10.0) + "B"
	elif abs_value >= 1000000:
		return str(round(value / 100000.0) / 10.0) + "M"
	elif abs_value >= 1000:
		return str(round(value / 100.0) / 10.0) + "K"
	else:
		return str(int(value))


func _on_all_coworkers_pressed() -> void:
	var warehouse = get_tree().get_first_node_in_group("employee_warehouse")
	
	if warehouse:
		warehouse.refresh_display()
		warehouse.show()
