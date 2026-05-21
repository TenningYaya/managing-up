# gamemanager.gd
extends Node

signal request_employee_drop(data)
signal kpi_changed(new_value)
signal dollar_changed(new_value)
signal level_changed(new_level)
# 记录教程是否已经完成

enum OfficeType {
	NONE,
	PANTRY,
	MEETING_ROOM,
	RECRUITMENT,
	CULTURE_CENTER
}

const OFFICE_UNLOCK_LEVELS = {
	OfficeType.PANTRY: 2,          # M2 解锁
	OfficeType.RECRUITMENT: 3,     # M3 解锁
	OfficeType.MEETING_ROOM: 4,    # M4 解锁
	OfficeType.CULTURE_CENTER: 5   # M5 解锁
}

var has_recruitment_office: bool = false
var has_culture_center: bool = false
var is_tutorial_completed: bool = false

# 定义总览面板需要的变量
var total_hits: int = 0
var total_time: float = 0.0

var player_level: int = 1:
	set(value):
		player_level = value
		level_changed.emit(player_level)
		
var kpi: int = 10000:
	set(value):
		kpi = value
		kpi_changed.emit(kpi)

var dollar: int = 10000:
	set(value):
		dollar = value
		dollar_changed.emit(dollar)

var max_desk_level: int = 1
var unlocked_desk_slots: int = 1 # 解锁的工位排数



func _ready() -> void:
	call_deferred("emit_signal", "dollar_changed", dollar)
	call_deferred("emit_signal", "kpi_changed", kpi)
	call_deferred("emit_signal", "level_changed", player_level)
	
# 每一帧自动更新游戏总时长
func _process(delta: float) -> void:
	total_time += delta

# 全局监听鼠标点击，不需要其他文件调用
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 只要鼠标左键按下，hit 就加 1
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			total_hits += 1

func hire_employee(data):
	request_employee_drop.emit(data)

# ================= KPI & Dollar 管理 =================
func has_enough_kpi(amount: int) -> bool:
	return kpi >= amount

func add_kpi(amount: int) -> void:
	kpi += amount

func spend_kpi(amount: int) -> bool:
	if kpi >= amount:
		kpi -= amount
		return true
	return false

func has_enough_dollar(amount: int) -> bool:
	return dollar >= amount

func add_dollar(amount: int) -> void:
	dollar += amount

func spend_dollar(amount: int) -> bool:
	if dollar >= amount:
		dollar -= amount
		return true
	return false
