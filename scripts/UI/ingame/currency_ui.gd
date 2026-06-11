extends Control

@export var up_arrow_texture: Texture2D
@export var down_arrow_texture: Texture2D

@onready var kpi_label: Label = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/KPI/KPILabel
@onready var dollar_label: Label = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/dollar/DollarLabel
@onready var kpi_arrow: TextureRect = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/KPI/KPIArrow
@onready var dollar_arrow: TextureRect = $ColorRect/CenterContainer/MarginContainer/VBoxContainer/dollar/DollarsArrow

var last_kpi: float = 0
var last_dollar: float = 0
var last_eff: float = 0


func _ready():
	last_kpi = Gamemanager.kpi
	last_dollar = Gamemanager.dollar

	update_labels()

	Gamemanager.kpi_changed.connect(_on_kpi_updated)
	Gamemanager.dollar_changed.connect(_on_dollar_updated)


func _on_kpi_updated(new_value: float) -> void:
	var delta := new_value - last_kpi
	update_value_label(kpi_label, kpi_arrow, last_kpi, new_value)
	if delta != 0:
		_spawn_float_label(kpi_label, delta)
	last_kpi = new_value


func _on_dollar_updated(new_value: float) -> void:
	var delta := new_value - last_dollar
	update_value_label(dollar_label, dollar_arrow, last_dollar, new_value)
	if delta != 0:
		_spawn_float_label(dollar_label, delta)
	last_dollar = new_value


# 在 anchor Label 正上方生成一个浮动变化量文字，动画：上移+淡入 → 原位淡出
func _spawn_float_label(anchor: Label, delta: float) -> void:
	var lbl := Label.new()
	lbl.text = ("+" if delta > 0 else "") + format_number(delta)
	lbl.add_theme_color_override("font_color", Color.RED if delta > 0 else Color.GREEN)
	lbl.add_theme_font_override("font", anchor.get_theme_font("font"))
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.modulate.a = 0.0
	add_child(lbl)

	await get_tree().process_frame  # 等 Godot 计算出 lbl.size

	# 在本节点局部坐标系中，水平居中对齐 anchor，紧贴其上方 4px
	var anchor_rect := anchor.get_global_rect()
	var start := Vector2(
		anchor_rect.position.x + (anchor_rect.size.x - lbl.size.x) * 0.5,
		anchor_rect.position.y - lbl.size.y - 4.0
	) - global_position
	lbl.position = start

	# 阶段一（0.45s）：向上移动 30px 同时淡入
	var tween := create_tween()
	tween.tween_property(lbl, "position:y", start.y - 30.0, 0.45)
	tween.parallel().tween_property(lbl, "modulate:a", 1.0, 0.3)
	# 阶段二（0.35s）：停留
	tween.tween_interval(0.35)
	# 阶段三（0.4s）：原位淡出
	tween.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tween.tween_callback(lbl.queue_free)


func update_labels():
	kpi_label.text = format_number(Gamemanager.kpi)
	dollar_label.text = format_number(Gamemanager.dollar)
	kpi_arrow.hide()
	dollar_arrow.hide()


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
	var abs_value: float = abs(value)

	if abs_value >= 1000000000:
		return str(round(value / 100000000.0) / 10.0) + "B"
	elif abs_value >= 1000000:
		return str(round(value / 100000.0) / 10.0) + "M"
	elif abs_value >= 10000:
		return "%.1fK" % (value / 1000.0)
	elif abs_value >= 1000:
		return "%.2fK" % (value / 1000.0)
	else:
		return str(int(value))


func _on_all_coworkers_pressed() -> void:
	var warehouse: Node = get_tree().get_first_node_in_group("employee_warehouse")

	if warehouse:
		warehouse.refresh_display()
		warehouse.show()
