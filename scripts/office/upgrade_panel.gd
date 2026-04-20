extends Control
class_name UpgradePanel

@onready var level_label = $VBoxContainer/LevelLabel
@onready var cost_label = $VBoxContainer/CostLabel
@onready var upgrade_button = $VBoxContainer/UpgradeButton

var target_slot: Control = null
var current_cost: int = 0

func _ready():
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	# 如果有 CloseButton，也要连上 hide()

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
		# 真正扣除 KPI [cite: 4]
		if Gamemanager.spend_kpi(current_cost):
			target_slot.upgrade_all()
			# 升级完刷新一下面板状态，或者你也可以直接 hide() 关闭它
			open(target_slot)
