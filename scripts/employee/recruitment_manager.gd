# recruitment_manager.gd
# 建议在项目设置里设为 Autoload，名字叫 RecruitmentManager
extends Node

# 数据池：所有新简历都存在这里
var normal_pool: Array[Employee] = []
var headhunt_pool: Array[Employee] = []

# 猎头状态
enum State { IDLE, RECRUITING, READY }
var current_state = State.IDLE
var headhunt_time_left: float = 0.0

func _process(delta):
	if current_state == State.RECRUITING:
		headhunt_time_left -= delta
		if headhunt_time_left <= 0:
			current_state = State.READY
			_on_headhunt_finished()

# --- 核心业务：普通招聘 (自动触发) ---
func auto_generate_normal():
	var rarity = Employee.Rarity.R
	if randf() <= 0.1: rarity = Employee.Rarity.SR
	
	var new_emp = _create_data(rarity)
	normal_pool.append(new_emp)
	print("人事部收到一份新简历")

# --- 核心业务：猎头招聘 (玩家触发) ---
func start_headhunt(amount: int, duration: float):
	current_state = State.RECRUITING
	headhunt_time_left = duration
	# 记录我们要招几个，这里可以加个临时变量
	_pending_amount = amount 

var _pending_amount = 0

func _on_headhunt_finished():
	for i in range(_pending_amount):
		var roll = randf()
		var rarity = Employee.Rarity.R
		if roll <= 0.02: rarity = Employee.Rarity.SSR
		elif roll <= 0.17: rarity = Employee.Rarity.SR
		headhunt_pool.append(_create_data(rarity))
	print("猎头招聘完成，收到 ", _pending_amount, " 份简历")

# --- 辅助：创建数据 ---
func _create_data(rarity) -> Employee:
	var e = Employee.new()
	e.employee_name = ["Bob", "Alice", "David"].pick_random() + str(randi()%100)
	e.setup_employee(rarity)
	return e
