# recruitment_manager.gd
# 建议在项目设置里设为 Autoload，名字叫 RecruitmentManager
extends Node

signal new_resumes_arrived

# 数据池：所有新简历都存在这里
var normal_pool: Array[Employee] = []
var headhunt_pool: Array[Employee] = []

# 猎头状态
enum State { IDLE, RECRUITING, READY }
var current_state = State.IDLE
var headhunt_time_left: float = 0.0

@onready var employee_scene = preload("res://scenes/employee/employee.tscn")
var sr_visual_scene = preload("res://scenes/employee/sr_visual.tscn")

func _ready():
	# 🌟 别忘了在这里初始化一下，否则名字库是空的
	NameBank.load_names()
	
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
	new_resumes_arrived.emit()

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
	new_resumes_arrived.emit()

func _create_data(rarity) -> Employee:
	var e = employee_scene.instantiate() as Employee
	var visual_instance = sr_visual_scene.instantiate()
	
	# 🌟 必须先 add_child！
	e.add_child(visual_instance) 
	e.visual_component = visual_instance
	
	# 🌟 这时候再 setup_visual，里面的 body 就不是空了
	visual_instance.setup_visual(randi(), {})
	
	e.employee_name = NameBank.get_random_name()
	e.setup_employee(rarity)
	return e
