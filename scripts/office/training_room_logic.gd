# training_room_logic.gd
# 员工培训室：把员工拖进来（最多 2 人），选一项属性 + 用加减选轮数 → 开始培训。
# 每轮 ROUND_SECONDS 秒结算一次，按 (100 - 属性值*10)% 概率把所选属性 +1（封顶 10）。
# 跑满玩家选的轮数自动结束；中途点"结束"则当前未完成的一轮无收益（已完成轮的 +1 已生效）。
# 培训期间员工不产 KPI（占着不干活 = 机会成本）。不唯一：可以有多间。
extends OfficeLogic
class_name TrainingRoomLogic

# —— 可调参数 ——
const MAX_CAPACITY := 5          # 一次最多培训几人
const ROUND_SECONDS := 6.0     # 一轮时长（正式值 10 分钟；调试想快改回 10.0）
const ATTR_MAX := 10             # 属性上限
# 每轮成功"名字 +1"飘字用的字体（与培训面板一致的像素字体）
const POPUP_FONT := preload("res://assets/fonts/doto_pixel_variation.tres")
const POPUP_HOLD := 2.0          # 飞字到位后多停留几秒再淡出

enum TrainAttr { EFF, QUAL, EXP }

var occupants: Array = []        # 正在培训的 Employee
var is_running: bool = false     # 是否已开始（开始后不能再拖人/改设置）
var chosen_attr: TrainAttr = TrainAttr.EFF
var rounds_total: int = 1        # 玩家用加减选的总轮数
var rounds_done: int = 0
var session_gains: Dictionary = {}    # 本次培训（点开始起）每人涨了几点：emp -> int。面板白色闪烁段 & 结算用
var _round_popup_points: Array = []   # 本轮已生成飘字的落点（相对办公室中心的偏移），用于防重叠
var round_elapsed: float = 0.0
var training_btn: TextureButton = null   # 办公室上悬停显隐的“培训”按钮（点击开页由 office.gd 管）

func setup(office: Control) -> void:
	super.setup(office)
	# 抓办公室上的“培训”按钮，初始藏起来（悬停才显示）
	if office != null:
		training_btn = office.training_btn
	if is_instance_valid(training_btn):
		training_btn.hide()
	# 在训员工被开除时清位
	if not EmployeeManager.employee_removed.is_connected(_on_employee_removed):
		EmployeeManager.employee_removed.connect(_on_employee_removed)
	_refresh_empty_hint()

# —— 悬停显隐“培训”按钮（仿炒股室/文化室）——
func on_mouse_entered() -> void:
	if is_instance_valid(training_btn):
		training_btn.show()

func on_mouse_exited(mouse_pos: Vector2) -> void:
	if not is_instance_valid(training_btn) or not is_instance_valid(my_office):
		return
	# 鼠标既不在按钮上、也不在办公室上，才收起
	if not training_btn.get_global_rect().has_point(mouse_pos) \
	and not my_office.get_global_rect().has_point(mouse_pos):
		training_btn.hide()

func cleanup() -> void:
	_release_all()   # 切换房间/清理：立刻把所有人放回工位
	if is_instance_valid(training_btn):
		training_btn.hide()
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
	# [员工吐槽中心]：被拖去培训（专属吐槽，区别于开会）
	BanterManager.trigger_banter("training_start", 1, [emp])
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
	session_gains.clear()   # 新一期培训：清空上期收获记录
	_notify_panel()

# 结束：玩家点"结束培训"或跑满自动结束。
# 中途结束 → 当前未完成的一轮不结算（已完成的轮 +1 已经生效，不退）。
func end_training() -> void:
	var was_running := is_running
	is_running = false
	round_elapsed = 0.0
	rounds_done = 0
	rounds_total = 1
	_release_all()
	_refresh_empty_hint()
	_notify_panel()
	if was_running:
		_show_settlement()   # 有收获才会真弹

# 培训结束的结算弹窗：把本期 session_gains 交给结算面板（零收获不弹）
func _show_settlement() -> void:
	var results: Array = []
	var key := _attr_key(chosen_attr)
	for emp in session_gains:
		if is_instance_valid(emp) and int(session_gains[emp]) > 0:
			results.append({"emp": emp, "key": key, "gain": int(session_gains[emp])})
	if results.is_empty():
		return
	var sp = get_tree().get_first_node_in_group("training_settlement_panel")
	if sp and sp.has_method("show_results"):
		sp.show_results(results)

# ==========================================
# 每轮结算
# ==========================================
func _complete_one_round() -> void:
	# 本轮练的是 chosen_attr；成功的人在办公室上方冒一条对应颜色的"名字 +1"
	var col := _attr_color(chosen_attr)
	_round_popup_points.clear()   # 新一轮：清掉上轮落点记录
	var success_i := 0
	for emp in occupants:
		if is_instance_valid(emp) and _roll_for(emp):
			_spawn_round_popup("%s +1" % _name_of(emp), col, success_i)
			success_i += 1
	rounds_done += 1
	if rounds_done >= rounds_total:
		end_training()   # 跑满，自动结束（人放回工位）
	else:
		_notify_panel()

# 掷骰：成功则 +1 并返回 true；失败/已满返回 false
func _roll_for(emp) -> bool:
	var val: int = _attr_value(emp, chosen_attr)
	if val >= ATTR_MAX:
		return false   # 已满，掷了也没用
	var chance: float = float(100 - val * 10)   # (100 - 属性值*10)%
	if randf() * 100.0 < chance:
		emp.raise_attribute(_attr_key(chosen_attr))
		session_gains[emp] = int(session_gains.get(emp, 0)) + 1
		return true
	return false

# 本次培训（点开始起）该员工涨了几点
func get_session_gain(emp) -> int:
	return int(session_gains.get(emp, 0))

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

# 属性 → 飘字颜色（效率蓝 / 品质金 / 经验绿；想改就改这里）
func _attr_color(attr: TrainAttr) -> Color:
	match attr:
		TrainAttr.EFF: return Color("4aa3ff")
		TrainAttr.QUAL: return Color("ffcf4a")
		TrainAttr.EXP: return Color("5cd06b")
	return Color.WHITE

func _name_of(emp) -> String:
	if emp.has_method("get_display_name"):
		return emp.get_display_name()
	return str(emp.employee_name)

# 与本轮已生成词条的落点比较：同时 |Δx|<50 且 |Δy|<20 → 会叠住
func _landing_conflicts(p: Vector2) -> bool:
	for q in _round_popup_points:
		if absf(p.x - q.x) < 50.0 and absf(p.y - q.y) < 20.0:
			return true
	return false

# 每轮成功飘字：从办公室中心以抛物线往外"蹦"，左右交错、字号渐大、末尾淡出（爆竹感）
func _spawn_round_popup(text: String, color: Color, index: int) -> void:
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(my_office):
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 950
	lbl.z_as_relative = false
	lbl.add_theme_font_override("font", POPUP_FONT)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 5)   # 黑描边，压在办公室上也看得清
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	scene.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size * 0.5                    # 绕自身中心缩放
	var center := my_office.get_global_rect().get_center()
	var start := center - lbl.size * 0.5                 # 文字中心对准办公室中点
	lbl.global_position = start
	lbl.scale = Vector2(0.6, 0.6)

	# 左右交错 + 随机幅度的抛物线；落点与本轮其他词条错开（不许同时 |Δx|<50 且 |Δy|<20）
	var dir := 1.0 if index % 2 == 0 else -1.0
	var horiz := 0.0
	var rise := 0.0
	for _try in range(16):   # 随机重掷，直到落点不和已有词条叠住
		horiz = dir * randf_range(45.0, 95.0)            # 水平往外
		rise = randf_range(-80.0, 80.0)                  # 整体上移（范围大 = 落点高度参差）
		if not _landing_conflicts(Vector2(horiz, -rise)):
			break
	var lift := 0
	while _landing_conflicts(Vector2(horiz, -rise)) and lift < 12:
		rise += 22.0   # 实在挤不开就一层层往上抬（保底，防极端运气）
		lift += 1
	_round_popup_points.append(Vector2(horiz, -rise))
	var peak := randf_range(55.0, 90.0)                  # 抛物线拱高
	var dur := randf_range(0.9, 1.15)
	var arc_cb := func(t: float):
		if is_instance_valid(lbl):
			var x := start.x + horiz * t
			var y := start.y - peak * 4.0 * t * (1.0 - t) - rise * t
			lbl.global_position = Vector2(x, y)

	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_method(arc_cb, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector2(1.4, 1.4), dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45).set_delay(dur + POPUP_HOLD)   # 到位后停留 POPUP_HOLD 秒再淡出
	tw.chain().tween_callback(lbl.queue_free)

# ==========================================
# 读档恢复（不存离线进度：把人放回房间的"未开始"状态，玩家重新点开始）
# ==========================================
func restore_occupant(emp) -> void:
	if emp == null or occupants.has(emp) or occupants.size() >= MAX_CAPACITY:
		return
	if not emp.is_training:
		emp.enter_training()
	occupants.append(emp)
	if emp.get("current_seat") != null and emp.current_seat.has_method("set_training_state"):
		emp.current_seat.set_training_state(true)
	_refresh_empty_hint()
	_notify_panel()

# ==========================================
# 杂项
# ==========================================
func _on_employee_removed(emp) -> void:
	if not occupants.has(emp):
		return
	if is_instance_valid(emp) and emp.get("current_seat") != null \
	and emp.current_seat.has_method("set_training_state"):
		emp.current_seat.set_training_state(false)
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
