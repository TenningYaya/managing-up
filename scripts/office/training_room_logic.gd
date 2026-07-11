# training_room_logic.gd
# 员工培训室：把员工拖进来（最多 2 人），选一项属性 + 用加减选轮数 → 开始培训。
# 每轮 ROUND_SECONDS 秒结算一次，按 (100 - 属性值*10)% 概率把所选属性 +1（封顶 10）。
# 跑满玩家选的轮数自动结束；中途点"结束"则当前未完成的一轮无收益（已完成轮的 +1 已生效）。
# 培训期间员工不产 KPI（占着不干活 = 机会成本）。不唯一：可以有多间。
extends OfficeLogic
class_name TrainingRoomLogic

# —— 可调参数 ——
const MAX_CAPACITY := 2          # 一次最多培训几人
const ROUND_SECONDS := 10.0      # 一轮时长（测试用 10 秒；正式改 600 = 10 分钟）
const ATTR_MAX := 10             # 属性上限

enum TrainAttr { EFF, QUAL, EXP }

var occupants: Array = []        # 正在培训的 Employee
var is_running: bool = false     # 是否已开始（开始后不能再拖人/改设置）
var chosen_attr: TrainAttr = TrainAttr.EFF
var rounds_total: int = 1        # 玩家用加减选的总轮数
var rounds_done: int = 0
var round_elapsed: float = 0.0

func setup(office: Control) -> void:
	super.setup(office)
	# 在训员工被开除时清位
	if not EmployeeManager.employee_removed.is_connected(_on_employee_removed):
		EmployeeManager.employee_removed.connect(_on_employee_removed)
	_refresh_empty_hint()

func cleanup() -> void:
	_release_all()   # 切换房间/清理：立刻把所有人放回工位
	if EmployeeManager.employee_removed.is_connected(_on_employee_removed):
		EmployeeManager.employee_removed.disconnect(_on_employee_removed)
	if is_instance_valid(my_office) and my_office.has_method("set_empty_hint_active"):
		my_office.set_empty_hint_active(false)
	queue_free()

func _process(delta: float) -> void:
	if not is_running:
		return
	round_elapsed += delta
	# 一帧内可能跨过多轮（正常一次一轮）
	while is_running and round_elapsed >= ROUND_SECONDS:
		round_elapsed -= ROUND_SECONDS
		_complete_one_round()

# ==========================================
# 拖入 / 移除
# ==========================================
func can_drop_employee(data: Variant) -> bool:
	if is_running:
		return false   # 开始后不能再拖人
	if data is Node and data.has_method("enter_training"):
		var has_seat = data.get("current_seat") != null or data.get("drag_start_seat") != null
		if has_seat and occupants.size() < MAX_CAPACITY and not occupants.has(data):
			return true
	return false

func drop_employee(data: Variant) -> void:
	var emp = data
	occupants.append(emp)
	emp.enter_training()
	_refresh_empty_hint()
	_notify_panel()

# 未开始时移除某人（面板双击头像可调）
func remove_occupant(emp) -> void:
	if is_running or not occupants.has(emp):
		return
	occupants.erase(emp)
	if is_instance_valid(emp):
		emp.exit_training()
	_refresh_empty_hint()
	_notify_panel()

# ==========================================
# 轮数 / 属性选择（仅未开始时可改）
# ==========================================
func add_round() -> void:
	if is_running: return
	rounds_total = mini(rounds_total + 1, 99)
	_notify_panel()

func sub_round() -> void:
	if is_running: return
	rounds_total = maxi(rounds_total - 1, 1)
	_notify_panel()

func set_attr(attr: TrainAttr) -> void:
	if is_running: return
	chosen_attr = attr
	_notify_panel()

# ==========================================
# 开始 / 结束
# ==========================================
func start_training() -> void:
	if is_running or occupants.is_empty():
		return
	is_running = true
	rounds_done = 0
	round_elapsed = 0.0
	_notify_panel()

# 结束：玩家点"结束培训"或跑满自动结束。
# 中途结束 → 当前未完成的一轮不结算（已完成的轮 +1 已经生效，不退）。
func end_training() -> void:
	is_running = false
	round_elapsed = 0.0
	rounds_done = 0
	rounds_total = 1
	_release_all()
	_refresh_empty_hint()
	_notify_panel()

# ==========================================
# 每轮结算
# ==========================================
func _complete_one_round() -> void:
	for emp in occupants:
		if is_instance_valid(emp):
			_roll_for(emp)
	rounds_done += 1
	if rounds_done >= rounds_total:
		end_training()   # 跑满，自动结束（人放回工位）
	else:
		_notify_panel()

func _roll_for(emp) -> void:
	var val: int = _attr_value(emp, chosen_attr)
	if val >= ATTR_MAX:
		return   # 已满，掷了也没用
	var chance: float = float(100 - val * 10)   # (100 - 属性值*10)%
	if randf() * 100.0 < chance:
		emp.raise_attribute(_attr_key(chosen_attr))

func _attr_value(emp, attr: TrainAttr) -> int:
	match attr:
		TrainAttr.EFF: return int(emp.efficiency)
		TrainAttr.QUAL: return int(emp.quality)
		TrainAttr.EXP: return int(emp.experience)
	return ATTR_MAX

func _attr_key(attr: TrainAttr) -> String:
	match attr:
		TrainAttr.EFF: return "eff"
		TrainAttr.QUAL: return "qual"
		TrainAttr.EXP: return "exp"
	return "eff"

# ==========================================
# 读档恢复（不存离线进度：把人放回房间的"未开始"状态，玩家重新点开始）
# ==========================================
func restore_occupant(emp) -> void:
	if emp == null or occupants.has(emp) or occupants.size() >= MAX_CAPACITY:
		return
	if not emp.is_training:
		emp.enter_training()
	occupants.append(emp)
	if emp.get("current_seat") != null and emp.current_seat.has_method("set_meeting_state"):
		emp.current_seat.set_meeting_state(true)
	_refresh_empty_hint()
	_notify_panel()

# ==========================================
# 杂项
# ==========================================
func _on_employee_removed(emp) -> void:
	if not occupants.has(emp):
		return
	if is_instance_valid(emp) and emp.get("current_seat") != null \
	and emp.current_seat.has_method("set_meeting_state"):
		emp.current_seat.set_meeting_state(false)
	occupants.erase(emp)
	if occupants.is_empty():
		is_running = false
	_refresh_empty_hint()
	_notify_panel()

func _release_all() -> void:
	for emp in occupants:
		if is_instance_valid(emp):
			emp.exit_training()
	occupants.clear()

func _refresh_empty_hint() -> void:
	if is_instance_valid(my_office) and my_office.has_method("set_empty_hint_active"):
		my_office.set_empty_hint_active(occupants.is_empty())

func get_progress() -> float:
	if not is_running:
		return 0.0
	return clampf(round_elapsed / ROUND_SECONDS, 0.0, 1.0)

# 通知面板刷新（若正开着本房间的培训页）
func _notify_panel() -> void:
	var panel = get_tree().get_first_node_in_group("training_panel")
	if panel and panel.has_method("refresh_from_logic"):
		panel.refresh_from_logic(self)
