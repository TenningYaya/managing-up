# gamemanager.gd
extends Node

signal request_employee_drop(data)
# 1. 定义信号，用来告诉 UI 刷新数字
signal kpi_changed(new_value)
signal dollar_changed(new_value)

var has_recruitment_office: bool = false
var has_bulletin_board: bool = false

# 2. 定义变量 (自带 setter 广播)
var kpi: int = 1000:
	set(value):
		kpi = value
		kpi_changed.emit(kpi)

# 把初始启动资金放在这里
var dollar: int = 1000:
	set(value):
		dollar = value
		dollar_changed.emit(dollar)

enum OfficeType {
	NONE,           # 未分配（空置）
	PANTRY,         # 茶水间
	MEETING_ROOM,   # 会议室
	RECRUITMENT,    # 招聘办公室
	BULLETIN_BOARD  # 公告栏
}


func hire_employee(data):
	print("Gamemanager.hire_employee called with: ", data)
	request_employee_drop.emit(data)
	print("request_employee_drop emitted")

func _ready() -> void:
	# 游戏启动时，广播一下初始资金和 KPI，让 UI 显示正确
	call_deferred("emit_signal", "dollar_changed", dollar)
	call_deferred("emit_signal", "kpi_changed", kpi)


# ================= KPI 管理API =================
func has_enough_kpi(amount: int) -> bool:
	return kpi >= amount

func add_kpi(amount: int) -> void:
	kpi += amount
	print("获得了 ", amount, " KPI，当前总额: ", kpi)

func spend_kpi(amount: int) -> bool:
	if kpi >= amount:
		kpi -= amount # 这里会自动触发 kpi_changed 信号
		print("花费了 ", amount, " KPI，当前剩余: ", kpi)
		return true
	else:
		print("KPI 不足！需要 ", amount, "，当前只有 ", kpi)
		return false

# ================= Dollar 管理API =================
func has_enough_dollar(amount: int) -> bool:
	return dollar >= amount

func add_dollar(amount: int) -> void:
	dollar += amount
	print("赚了 $", amount, "，当前余额 $", dollar)

func spend_dollar(amount: int) -> bool:
	if dollar >= amount:
		dollar -= amount # 这里会自动触发 dollar_changed 信号
		print("花了 $", amount, "，当前余额 $", dollar)
		return true
	else:
		print("Dollar 不足！需要 $", amount, "，只有 $", dollar)
		return false
