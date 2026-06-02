# office_manager.gd
extends Node

# 定义信号：当办公室状态改变时通知全服（主要是通知招聘面板）
signal recruitment_office_status_changed(is_active: bool)
signal culture_center_status_changed(is_active: bool)

var culture_efficiency: int = 0
var culture_quality: int = 0
var culture_experience: int = 0

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
			
func can_dispense_snack() -> bool:
	# 如果没有食堂（total_pantries == 0），那就肯定没法发零食
	if total_pantries <= 0:
		return false
	
	# 名额判定：当前激活的 buff 数量 < 总共的食堂容量
	return active_snack_buffs < total_pantries
