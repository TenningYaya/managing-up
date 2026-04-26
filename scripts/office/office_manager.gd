# officemanager.gd
extends Node

# 定义信号：当办公室状态改变时通知全服（主要是通知招聘面板）
signal recruitment_office_status_changed(is_active: bool)
signal culture_center_status_changed(is_active: bool)

var culture_efficiency: int = 0
var culture_quality: int = 0
var culture_experience: int = 0

var total_pantries: int = 0
var active_snack_buffs: int = 0

# 全局唯一状态
var has_recruitment_office: bool = false:
	set(value):
		if has_recruitment_office != value:
			has_recruitment_office = value
			recruitment_office_status_changed.emit(has_recruitment_office)

var has_culture_center: bool = false:
	set(value):
		if has_culture_center != value:
			has_culture_center = value
			culture_center_status_changed.emit(has_culture_center)

func can_dispense_snack() -> bool:
	return active_snack_buffs < total_pantries
