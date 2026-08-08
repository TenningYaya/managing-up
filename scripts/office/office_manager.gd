# office_manager.gd
extends Node

# 定义信号：当办公室状态改变时通知全服（主要是通知招聘面板）
signal recruitment_office_status_changed(is_active: bool)
signal culture_center_status_changed(is_active: bool)
signal stock_office_status_changed(is_active: bool)

var culture_efficiency: int = 0
var culture_quality: int = 0
var culture_experience: int = 0

# =====================================================
# 事件 buff：全体员工的临时加成（被 employee.get_final_* 累加），每份持续 3 分钟后自动撤销
# =====================================================
signal event_buff_changed
const EVENT_BUFF_DURATION := 180.0   # 一个 buff 持续 3 分钟
var event_buff_efficiency: int = 0
var event_buff_quality: int = 0
var event_buff_experience: int = 0

# 给全体员工加一份事件 buff：stat 为 "efficiency"/"quality"/"experience"，amount 可正可负。
# 多份 buff 独立叠加，各自 3 分钟后自动消失。
func apply_event_buff(stat: String, amount: int) -> void:
	if amount == 0:
		return
	_change_event_buff(stat, amount)
	event_buff_changed.emit()
	# 3 分钟后撤销这一份（SceneTreeTimer 跨场景切换仍然有效）
	get_tree().create_timer(EVENT_BUFF_DURATION).timeout.connect(func():
		_change_event_buff(stat, -amount)
		event_buff_changed.emit()
	)

func _change_event_buff(stat: String, delta: int) -> void:
	match stat:
		"efficiency": event_buff_efficiency += delta
		"quality":    event_buff_quality += delta
		"experience": event_buff_experience += delta

var total_pantries: int = 0
var active_snack_buffs: int = 0

var active_snack_targets = {} # 格式: {Buff类型: Employee引用}

func assign_snack(employee: Employee, buff_type: Employee.SnackBuff):
	active_snack_targets[buff_type] = employee
	active_snack_buffs += 1

var has_recruitment_office: bool:
	get:
		return Gamemanager.has_recruitment_office
	set(value):
		if Gamemanager.has_recruitment_office != value:
			Gamemanager.has_recruitment_office = value
			recruitment_office_status_changed.emit(value)

var has_culture_center: bool:
	get:
		return Gamemanager.has_culture_center
	set(value):
		if Gamemanager.has_culture_center != value:
			Gamemanager.has_culture_center = value
			culture_center_status_changed.emit(value)
		
var has_stock_office: bool:
	get:
		return Gamemanager.has_stock_office
	set(value):
		if Gamemanager.has_stock_office != value:
			Gamemanager.has_stock_office = value
			stock_office_status_changed.emit(value)
				
func can_dispense_snack() -> bool:
	# 如果没有食堂（total_pantries == 0），那就肯定没法发零食
	if total_pantries <= 0:
		return false
	
	# 名额判定：当前激活的 buff 数量 < 总共的食堂容量
	return active_snack_buffs < total_pantries
