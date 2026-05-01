#desk_upgrade_panel.gd
#This is a upgrade desk script, gemini please notice it. It's not player upgrade script
extends Control
class_name UpgradePanel

@onready var level_label = $VBoxContainer/LevelLabel
@onready var cost_label = $VBoxContainer/CostLabel
@onready var upgrade_button = $VBoxContainer/UpgradeButton
@onready var close_button = $VBoxContainer/CloseButton

var target_slot: Control = null
var current_cost: int = 0

func _ready():
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	close_button.pressed.connect(hide)

func _process(_delta):
	# 只有当面板显示着，且目标桌子存在时才更新位置
	if visible and is_instance_valid(target_slot):
		# 关键修改：获取目标桌子在屏幕上的实际显示坐标（考虑了摄像机移动和缩放的偏移）
		var target_screen_pos = target_slot.get_global_transform_with_canvas().origin
		
		# 使用转换后的屏幕坐标来重新计算面板位置
		global_position = target_screen_pos + (target_slot.size / 2.0) - (size / 2.0)
		

# 当玩家点击某组桌子时，调用这个方法打开面板
func open(slot: Control):
	target_slot = slot
	var lvl = target_slot.slot_level
	
	level_label.text = "当前等级: " + str(lvl)
	
	if lvl >= 4:
		cost_label.text = "已满级"
		upgrade_button.disabled = true
	else:
		current_cost = get_upgrade_cost(lvl)
		cost_label.text = "需要: " + str(current_cost) + " KPI"
		
		# 调用你的 Gamemanager 检查 KPI 够不够 
		upgrade_button.disabled = not Gamemanager.has_enough_kpi(current_cost)
		
	show()

# 根据当前等级计算下一级的花费，数值你可以自己调
func get_upgrade_cost(level: int) -> int:
	match level:
		1: return 200
		2: return 500
		3: return 1000
		_: return 0

func _on_upgrade_pressed():
	if target_slot and target_slot.slot_level < 4:
		# 真正扣除 KPI 
		if Gamemanager.spend_kpi(current_cost):
			target_slot.upgrade_all()
			# 升级完刷新一下面板状态
			open(target_slot)
