# recruitment_manager.gd
extends Node

signal new_resumes_arrived

# 数据池：所有新简历都存在这里
var normal_pool: Array[Employee] = []
var headhunt_pool: Array[Employee] = []

# 猎头状态
enum State { IDLE, RECRUITING, READY }
var current_state = State.IDLE
var headhunt_time_left: float = 0.0
var _pending_amount = 0

@onready var employee_scene = preload("res://scenes/employee/employee.tscn")

# 🌟 字典映射：后期加其他等级（比如 UR），只需在这里加上对应的场景路径
@onready var visual_scenes = {
	Employee.Rarity.R: preload("res://scenes/employee/r_visual.tscn"),
	Employee.Rarity.SR: preload("res://scenes/employee/sr_visual.tscn"),
	Employee.Rarity.SSR: preload("res://scenes/employee/sr_visual.tscn")
}

func _ready():
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
	_pending_amount = amount 

func _on_headhunt_finished():
	for i in range(_pending_amount):
		var roll = randf()
		var rarity = Employee.Rarity.R
		
		# 写死的爆率逻辑
		if roll <= 0.02: 
			rarity = Employee.Rarity.SSR
		elif roll <= 0.17: 
			rarity = Employee.Rarity.SR
			
		headhunt_pool.append(_create_data(rarity))
	new_resumes_arrived.emit()

func _create_data(rarity: Employee.Rarity) -> Employee:
	var e = employee_scene.instantiate() as Employee
	var visual_scene = visual_scenes[rarity]
	var visual_instance = visual_scene.instantiate()
	
	e.add_child(visual_instance) 
	e.visual_component = visual_instance
	
	# 🌟 防弹衣 1：如果对方写了 setup_visual 才调用
	if visual_instance.has_method("setup_visual"):
		visual_instance.setup_visual(randi(), {})
	
	# 🌟 防弹衣 2：如果对方写了生成头像的方法，就拿过来；没有就给个保底或者空着
	if visual_instance.has_method("generate_portrait_texture"):
		e.portrait = visual_instance.generate_portrait_texture()
	else:
		# 比如你同学可以直接在节点上放一个 @export var default_portrait: Texture2D
		if "default_portrait" in visual_instance:
			e.portrait = visual_instance.default_portrait
		else:
			print("警告：该级别的员工缺少头像数据！")
	
	e.employee_name = NameBank.get_random_name()
	e.setup_employee(rarity)
	
	return e
