# officemanager.gd
extends Node

# 定义信号：当办公室状态改变时通知全服（主要是通知招聘面板）
signal recruitment_office_status_changed(is_active: bool)
signal bulletin_board_status_changed(is_active: bool)

# 全局唯一状态
var has_recruitment_office: bool = false:
	set(value):
		if has_recruitment_office != value:
			has_recruitment_office = value
			recruitment_office_status_changed.emit(has_recruitment_office)

var has_bulletin_board: bool = false:
	set(value):
		if has_bulletin_board != value:
			has_bulletin_board = value
			bulletin_board_status_changed.emit(has_bulletin_board)
