# recruitment_manager.gd
extends Node

signal new_resumes_arrived

# 数据池：所有新简历都存在这里
var normal_pool: Array[Employee] = []
var headhunt_pool: Array[Employee] = []

var is_tutorial_mode: bool = false
@export var tutorial_recruits_queue: Array[PackedScene] = []

# 猎头状态
enum State { IDLE, RECRUITING, READY }
var current_state = State.IDLE
var headhunt_time_left: float = 0.0
var _pending_amount = 0

@onready var employee_scene = preload("res://scenes/employee/employee.tscn")

# 🌟 字典映射：后期加其他等级（比如 UR），只需在这里加上对应的场景路径
@onready var visual_scenes = {
	Employee.Rarity.R: preload("res://scenes/employee/sr_visual.tscn"),
	Employee.Rarity.SR: preload("res://scenes/employee/sr_visual.tscn"),
	Employee.Rarity.SSR: preload("res://scenes/employee/sr_visual.tscn")
}

const TUTORIAL_EMP_1 = preload("res://scenes/starter/tutorial_employees/tutemp1.tscn")
const TUTORIAL_EMP_2 = preload("res://scenes/starter/tutorial_employees/tutemp3.tscn")
const TUTORIAL_EMP_3 = preload("res://scenes/starter/tutorial_employees/tutemp6.tscn")

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
	if is_tutorial_mode:
		return
		
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
		
		# 1. 判定稀有度
		if roll <= 0.02: 
			rarity = Employee.Rarity.SSR
		elif roll <= 0.17: 
			rarity = Employee.Rarity.SR
			
		# 2. 🌟 关键修正：先创建并赋值给 new_emp
		var new_emp = _create_data(rarity) 
		
		# 3. 🌟 打上猎头标记
		new_emp.is_headhunt = true
		
		# 4. 塞进猎头简历池
		headhunt_pool.append(new_emp)
	new_resumes_arrived.emit()

func debug_generate_specified(amount: int, rarity: Employee.Rarity):
	for i in range(amount):
		var new_emp = _create_data(rarity)
		normal_pool.append(new_emp)
	
	new_resumes_arrived.emit()
	
func _create_data(rarity: Employee.Rarity) -> Employee:
	var e = employee_scene.instantiate() as Employee	
	e.setup_employee(rarity)
	e.employee_name = NameBank.get_random_name()
	
	var visual_scene = visual_scenes[rarity]
	var visual_instance = visual_scene.instantiate()
	
	e.add_child(visual_instance) 
	e.visual_component = visual_instance
	
	if visual_instance.has_method("setup_visual"):
		visual_instance.setup_visual(randi(), e.dna, e.rarity)
	
	# 🌟 防弹衣 2：如果对方写了生成头像的方法，就拿过来；没有就给个保底或者空着
	if visual_instance.has_method("generate_portrait_texture"):
		e.portrait = visual_instance.generate_portrait_texture()
	else:
		# 比如你同学可以直接在节点上放一个 @export var default_portrait: Texture2D
		if "default_portrait" in visual_instance:
			e.portrait = visual_instance.default_portrait
		else:
			print("警告：该级别的员工缺少头像数据！")
	
	return e

func load_tutorial_resumes() -> void:
	normal_pool.clear()
	var pre_made_scenes = [TUTORIAL_EMP_1, TUTORIAL_EMP_2, TUTORIAL_EMP_3]
	
	# 给个固定的种子值，保证这仨人不仅有人样，而且每次重启游戏长得都一样
	var seed_counter = 101 
	
	for scene in pre_made_scenes:
		if not scene: continue
		var new_emp = scene.instantiate() as Employee
		
		# 1. 抓取你截图里的那个 SrVisual
		var visual = new_emp.get_node_or_null("SrVisual")
		if not visual: # 防呆：如果名字改了，用地毯式搜索
			for child in new_emp.get_children():
				if child.has_method("generate_portrait_texture"):
					visual = child
					break
					
		if visual:
			# 🌟 核心抢救 1：强行注入 DNA，让他们把衣服和头发穿戴整齐！
			if visual.has_method("setup_visual"):
				visual.setup_visual(seed_counter, new_emp.dna, new_emp.rarity)
				seed_counter += 1 # 换下一个人时长相变动一下
				
			# 🌟 核心抢救 2：穿戴整齐后，立刻咔嚓拍照贴到简历上
			if visual.has_method("generate_portrait_texture"):
				new_emp.portrait = visual.generate_portrait_texture()
		else:
			printerr("【警报】没找到叫 SrVisual 的外观节点！")
			
		normal_pool.append(new_emp)
		
	new_resumes_arrived.emit()
