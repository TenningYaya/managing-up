extends Control
class_name UpgradePanel

@onready var level_label: Label = $VBoxContainer/LevelLabel
@onready var cost_label: Label = $VBoxContainer/CostLabel
@onready var upgrade_button: Button = $VBoxContainer/UpgradeButton
@onready var close_button: Button = $CloseButton # 如果你有的话

var current_target_slot: Control = null
var upgrade_cost: int = 0

# 假设你有一个全局脚本 Global 或者 GameManager 来存当前 KPI
# var current_kpi: int = Global.current_kpi 

func _ready() -> void:
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	if close_button:
		close_button.pressed.connect(hide)

# 当点击 DeskSlot 时调用这个函数来显示面板
func open_panel(slot: Control, current_kpi: int) -> void:
	current_target_slot = slot
	
	# 获取目标工位的当前等级
	var current_level = slot.get_current_level()
	level_label.text = "当前等级: " + str(current_level)
	
	if current_level >= 4:
		cost_label.text = "已满级"
		upgrade_button.disabled = true
	else:
		# 假设升级花费是根据等级计算的，比如 1->2 要 100，2->3 要 200
		upgrade_cost = current_level * 100 
		cost_label.text = "升级需要: " + str(upgrade_cost) + " KPI"
		
		# 如果 KPI 不够，按钮置灰 (disabled)
		upgrade_button.disabled = (current_kpi < upgrade_cost)
	
	show()

func _on_upgrade_button_pressed() -> void:
	if current_target_slot and current_target_slot.get_current_level() < 4:
		# 这里应该调用全局脚本扣除 KPI
		# Global.current_kpi -= upgrade_cost
		
		# 让工位升级
		current_target_slot.upgrade_slot()
		
		# 刷新面板显示，或者升级完直接关闭面板
		hide()
