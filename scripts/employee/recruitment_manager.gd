# recruitment_manager.gd
extends Node

signal new_resumes_arrived

# 数据池：所有新简历都存在这里
var normal_pool: Array[Employee] = []
var headhunt_pool: Array[Employee] = []

var is_tutorial_mode: bool = false
var has_loaded_tutorial_resumes: bool = false

@export var tutorial_recruits_queue: Array[PackedScene] = []

# 猎头状态
enum State { IDLE, RECRUITING, READY }
var current_state = State.IDLE
var headhunt_time_left: float = 0.0
var _pending_amount = 0

# --- 普通招募：免费简历自动出现计时器 ---
# 出现节奏：前 3 个每 2 分钟，第 4~10 个每 10 分钟，之后每 15 分钟。
# 剩余时间与已出现数量都会被 SaveManager 记进存档。
const FREE_RECRUIT_INTERVAL_EARLY: float = 120.0   # 前 3 个：每 2 分钟
const FREE_RECRUIT_INTERVAL_MID: float = 600.0     # 第 4~10 个：每 10 分钟
const FREE_RECRUIT_INTERVAL_LATE: float = 900.0    # 之后：每 15 分钟
var free_recruit_count: int = 0                     # 已自动出现过的免费普通简历数量
var free_recruit_time_left: float = FREE_RECRUIT_INTERVAL_EARLY  # 距离下一个免费简历出现的剩余秒数

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

	# 普通招募：教程完成后才开始计时，时间一到就免费送一份简历到普通招募板（左侧）
	if Gamemanager.is_tutorial_completed:
		free_recruit_time_left -= delta
		if free_recruit_time_left <= 0:
			_spawn_free_recruit()

# --- 核心业务：普通招聘 (自动触发) ---
func auto_generate_normal():
	if is_tutorial_mode:
		return
		
	var rarity = Employee.Rarity.R
	if randf() <= 0.1: rarity = Employee.Rarity.SR
	
	var new_emp = _create_data(rarity)
	normal_pool.append(new_emp)
	new_resumes_arrived.emit()

# 计时结束：免费生成一份普通简历，并把计时器重置到下一个间隔
func _spawn_free_recruit() -> void:
	auto_generate_normal()  # 复用既有普通招募逻辑（R 90% / SR 10%），会塞进 normal_pool 并发 new_resumes_arrived
	free_recruit_count += 1
	free_recruit_time_left = _get_free_recruit_interval()

# 根据已出现数量决定下一个免费简历要等多久
func _get_free_recruit_interval() -> float:
	if free_recruit_count < 3:
		return FREE_RECRUIT_INTERVAL_EARLY   # 前 3 个：每 2 分钟
	elif free_recruit_count < 10:
		return FREE_RECRUIT_INTERVAL_MID     # 第 4~10 个：每 10 分钟
	else:
		return FREE_RECRUIT_INTERVAL_LATE    # 之后：每 15 分钟

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
	# ====================================================
	# 🌟【老板的终极防变脸结界】
	# 如果发现之前已经生成过教程简历，并且库里有人，直接打断施法！
	# ====================================================
	if has_loaded_tutorial_resumes and normal_pool.size() > 0:
		new_resumes_arrived.emit() # 强行再发一次信号，让面板刷新 UI 就行
		return
		
	# 盖章记录：这是第一次生成！
	has_loaded_tutorial_resumes = true
	# ====================================================

	normal_pool.clear()
	var pre_made_scenes = [TUTORIAL_EMP_1, TUTORIAL_EMP_2, TUTORIAL_EMP_3]
	
	# 给个固定的种子值，保证这仨人不仅有人样，而且每次重启游戏长得都一样
	var seed_counter = 101 
	
	for scene in pre_made_scenes:
		if not scene: continue
		var new_emp = scene.instantiate() as Employee
		
		# =========================================================
		# 💥 1. 揪出预制体里那个陈年老皮套，直接扬了！
		# =========================================================
		var old_visual = new_emp.get_node_or_null("SrVisual")
		if not old_visual:
			for child in new_emp.get_children():
				if child.has_method("generate_portrait_texture"):
					old_visual = child
					break
					
		if old_visual:
			old_visual.name = "TrashVisual" # 改名防冲突
			old_visual.queue_free() # 送它上路
			
		# =========================================================
		# 💥 2. 换回你原本的字典，根据员工稀有度直接拿新皮套！
		# =========================================================
		var target_scene = visual_scenes[new_emp.rarity] # 👈 用你现有的字典获取
		var fresh_visual = target_scene.instantiate()
		new_emp.add_child(fresh_visual)
		
		# 🌟【致命命脉】：把灵魂（Employee）和皮套（Visual）的神经元接上！
		# 之前普通员工正常就是因为有这一句，教程员工少了这一句，工位就没办法控制它裁剪！
		new_emp.visual_component = fresh_visual 
		
		# =========================================================
		# 💥 3. 穿衣、理发、拍照
		# =========================================================
		if fresh_visual.has_method("setup_visual"):
			fresh_visual.setup_visual(seed_counter, new_emp.dna, new_emp.rarity)
			seed_counter += 1 
			
		if fresh_visual.has_method("generate_portrait_texture"):
			new_emp.portrait = fresh_visual.generate_portrait_texture()
			
		normal_pool.append(new_emp)
		
	new_resumes_arrived.emit()

func calculate_hire_cost(emp: Employee) -> int:
	# 以后想要修改招聘价格公式，只需要改这里这一行！
	return (emp.efficiency + emp.quality + emp.experience) * 50

func get_unread_count() -> int:
	# 只要池子里还有简历，就视为有“未处理”的（或者你可以给 Employee 加一个 is_read 属性，如果不需要就直接看池子大小）
	return normal_pool.size() + headhunt_pool.size()
