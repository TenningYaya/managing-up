#seat.gd
extends Control
class_name DeskSeat

signal upgrade_level_changed(new_level: int)

@export_range(1, 4, 1) var upgrade_level: int = 1

@onready var drop_area: Control = $DropArea
@onready var snap_point: Control = $SnapPoint

@onready var computer: CanvasItem = $Computer as CanvasItem
@onready var coffee_cup: CanvasItem = get_node_or_null("CoffeeCup") as CanvasItem
@onready var advanced_computer: CanvasItem = get_node_or_null("AdvancedComputer") as CanvasItem
@onready var plant: CanvasItem = get_node_or_null("Plant") as CanvasItem
@onready var meeting_icon: Control = get_node_or_null("MeetingIcon") as Control  # 需按自身中心旋转，故用 Control 取 pivot/size

@onready var milktea_buff: CanvasItem = get_node_or_null("MilkteaBuff") as CanvasItem
@onready var sausage_buff: CanvasItem = get_node_or_null("SausageBuff") as CanvasItem
@onready var cake_buff: CanvasItem = get_node_or_null("CakeBuff") as CanvasItem

# 员工摸鱼（roaming 离座）时显示在工位上的“鱼”图标，提示玩家这个座位有人、只是溜了
@onready var roaming_icon: TextureRect = get_node_or_null("RoamingIcon") as TextureRect

# 鱼图标候选（预加载，导出后也能用；运行时随机抽一条）
const FISH_TEXTURES := [
	preload("res://assets/UI/ingame/fishs/item1044.png"),
	preload("res://assets/UI/ingame/fishs/item1045.png"),
	preload("res://assets/UI/ingame/fishs/item1046.png"),
	preload("res://assets/UI/ingame/fishs/item1047.png"),
	preload("res://assets/UI/ingame/fishs/item1048.png"),
	preload("res://assets/UI/ingame/fishs/item1049.png"),
	preload("res://assets/UI/ingame/fishs/item1050.png"),
	preload("res://assets/UI/ingame/fishs/item1051.png"),
	preload("res://assets/UI/ingame/fishs/item1052.png"),
	preload("res://assets/UI/ingame/fishs/item1053.png"),
	preload("res://assets/UI/ingame/fishs/item1054.png"),
	preload("res://assets/UI/ingame/fishs/item1055.png"),
	preload("res://assets/UI/ingame/fishs/item1058.png"),
	preload("res://assets/UI/ingame/fishs/item1059.png"),
	preload("res://assets/UI/ingame/fishs/item1060.png"),
	preload("res://assets/UI/ingame/fishs/item1061.png"),
	preload("res://assets/UI/ingame/fishs/item1062.png"),
	preload("res://assets/UI/ingame/fishs/item1063.png"),
	preload("res://assets/UI/ingame/fishs/item1065.png"),
	preload("res://assets/UI/ingame/fishs/item1066.png"),
	preload("res://assets/UI/ingame/fishs/item1067.png"),
	preload("res://assets/UI/ingame/fishs/item1069.png"),
	preload("res://assets/UI/ingame/fishs/item1070.png"),
	preload("res://assets/UI/ingame/fishs/item1071.png"),
	preload("res://assets/UI/ingame/fishs/item1072.png"),
	preload("res://assets/UI/ingame/fishs/item1073.png"),
	preload("res://assets/UI/ingame/fishs/item1074.png"),
	preload("res://assets/UI/ingame/fishs/item1075.png"),
	preload("res://assets/UI/ingame/fishs/item1076.png"),
	preload("res://assets/UI/ingame/fishs/item1077.png"),
	preload("res://assets/UI/ingame/fishs/item1078.png"),
	preload("res://assets/UI/ingame/fishs/item1079.png"),
	preload("res://assets/UI/ingame/fishs/item1080.png"),
	preload("res://assets/UI/ingame/fishs/item1081.png"),
	preload("res://assets/UI/ingame/fishs/item1082.png"),
	preload("res://assets/UI/ingame/fishs/item1084.png"),
	preload("res://assets/UI/ingame/fishs/item1085.png"),
	preload("res://assets/UI/ingame/fishs/item1086.png"),
	preload("res://assets/UI/ingame/fishs/item1091.png"),
	preload("res://assets/UI/ingame/fishs/item1092.png"),
	preload("res://assets/UI/ingame/fishs/item1100.png"),
]

var occupant: Control = null

var _roam_icon_base_y: float = 0.0   # 鱼图标设计初始 y，浮动动画围绕它来回
var _roam_icon_tween: Tween = null



func _ready() -> void:
	add_to_group("desk_seats")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_upgrade_visuals()
	if roaming_icon != null:
		_roam_icon_base_y = roaming_icon.position.y
		roaming_icon.visible = false


func _draw() -> void:
	#var rect: Rect2 = Rect2(drop_area.position, drop_area.size)
	#draw_rect(rect, Color(0, 1, 0, 0.3), false, 2.0)
	#draw_circle(snap_point.position, 5.0, Color.RED)
	pass

func _process(_delta: float) -> void:
	queue_redraw()


func is_free() -> bool:
	return occupant == null


func set_occupant(employee: Control) -> void:
	occupant = employee
	employee.z_index = z_index + 1  # 椅(z) < 员工(z+1) < 桌(z+3)
	if occupant and occupant.has_signal("buff_status_changed"):
		if not occupant.buff_status_changed.is_connected(_sync_buff_icons):
			occupant.buff_status_changed.connect(_sync_buff_icons)
			
	# 坐下的瞬间主动刷新一次，防止员工换座位时把零食变没了
	_sync_buff_icons()

func clear_occupant() -> void:
	if occupant:
		occupant.z_index = 1  # 恢复默认
		if occupant.has_signal("buff_status_changed"):
			if occupant.buff_status_changed.is_connected(_sync_buff_icons):
				occupant.buff_status_changed.disconnect(_sync_buff_icons)
	occupant = null
	# 安全兜底：员工被拖走 / 开除 / 收回时离座，鱼图标必须一起消失
	hide_roaming_icon()


# 员工摸鱼离座：在工位上放一条随机鱼，并让它上下浮动
func show_roaming_icon() -> void:
	if roaming_icon == null:
		return
	if not FISH_TEXTURES.is_empty():
		roaming_icon.texture = FISH_TEXTURES[randi() % FISH_TEXTURES.size()]
	roaming_icon.position.y = _roam_icon_base_y
	roaming_icon.visible = true
	_start_roam_icon_float()


# 员工回到座位：收起鱼图标，停掉浮动动画
func hide_roaming_icon() -> void:
	if _roam_icon_tween:
		_roam_icon_tween.kill()
		_roam_icon_tween = null
	if roaming_icon == null:
		return
	roaming_icon.visible = false
	roaming_icon.position.y = _roam_icon_base_y


func _start_roam_icon_float() -> void:
	if roaming_icon == null:
		return
	if _roam_icon_tween:
		_roam_icon_tween.kill()
	_roam_icon_tween = create_tween()
	_roam_icon_tween.set_loops()
	_roam_icon_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_roam_icon_tween.tween_property(roaming_icon, "position:y", _roam_icon_base_y - 6.0, 0.6)
	_roam_icon_tween.tween_property(roaming_icon, "position:y", _roam_icon_base_y, 0.6)

func get_snap_global_position() -> Vector2:
	return snap_point.global_position


func contains_global_point(point: Vector2) -> bool:
	# 向上检查层级树：透明 或 所属工位(DeskSlot)未解锁 → 判定为不可放置
	var current_node = self
	while current_node and current_node is CanvasItem:
		if current_node.modulate.a <= 0.01:
			return false
		# 🌟 未解锁的桌子不能放员工（锁定时只是变灰、alpha 仍为 1，光看透明度查不出来）
		if current_node is DeskSlot and current_node.is_locked:
			return false
		current_node = current_node.get_parent()

	var rect: Rect2 = Rect2(drop_area.global_position, drop_area.size)
	return rect.has_point(point)


func set_upgrade_level(new_level: int) -> void:
	var clamped_level: int = clampi(new_level, 1, 4)
	if upgrade_level == clamped_level:
		return

	upgrade_level = clamped_level
	_apply_upgrade_visuals()
	upgrade_level_changed.emit(upgrade_level)


func upgrade_one_level() -> void:
	if upgrade_level < 4:
		upgrade_level += 1
		_apply_upgrade_visuals()
		upgrade_level_changed.emit(upgrade_level)


func _apply_upgrade_visuals() -> void:
	# 先重置到默认状态
	if computer != null:
		computer.visible = true

	if coffee_cup != null:
		coffee_cup.visible = false

	if advanced_computer != null:
		advanced_computer.visible = false

	if plant != null:
		plant.visible = false

	# 1级：默认，不做额外修改

	# 2级：显示咖啡杯
	if upgrade_level >= 2:
		if coffee_cup != null:
			coffee_cup.visible = true

	# 3级：普通电脑隐藏，高级电脑显示
	if upgrade_level >= 3:
		if computer != null:
			computer.visible = false
		if advanced_computer != null:
			advanced_computer.visible = true

	# 4级：显示绿植
	if upgrade_level >= 4:
		if plant != null:
			plant.visible = true

# 获取效率加成
func get_efficiency_buff() -> int:
	if upgrade_level >= 2:
		return 2
	return 0

# 获取质量加成
func get_quality_buff() -> int:
	if upgrade_level >= 3:
		return 2
	return 0

func set_meeting_state(is_meeting: bool) -> void:
	if meeting_icon != null:
		meeting_icon.visible = is_meeting
		if is_meeting:
			# 开会时藏起电脑（普通/高级都藏），别和会议图标抢镜
			if computer != null: computer.visible = false
			if advanced_computer != null: advanced_computer.visible = false
		else:
			# 散会：按升级等级重新决定该显示普通还是高级电脑（不能无脑全开）
			_apply_upgrade_visuals()

func _sync_buff_icons() -> void:
	# 1. 每次刷新前，闭着眼睛先把桌子扫空
	if milktea_buff: milktea_buff.hide()
	if sausage_buff: sausage_buff.hide()
	if cake_buff: cake_buff.hide()
	
	# 2. 如果座位上没人，或者进来的只是个普通节点（没有吃零食属性），直接下班
	if occupant == null or not "current_snack_buff" in occupant:
		return
		
	# 3. 看看这人在吃啥，变魔术把对应的食物放在桌上！
	match occupant.current_snack_buff:
		Employee.SnackBuff.MILK_TEA:
			if milktea_buff: milktea_buff.show()
		Employee.SnackBuff.CAKE:
			if cake_buff: cake_buff.show()
		Employee.SnackBuff.SAUSAGE:
			if sausage_buff: sausage_buff.show()
