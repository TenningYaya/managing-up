#recruitment_system.gd
extends Control

# ==========================================
# UI 节点引用
# ==========================================
@onready var normal_btn: Button = $VBoxContainer/NormalRecruitBtn
@onready var headhunt_btn: Button = $VBoxContainer/HeadhuntBtn
@onready var fire_all_btn: Button = $VBoxContainer/FireAllBtn

# ==========================================
# 抽卡配置参数
# ==========================================
const NORMAL_COST: int = 100
const NORMAL_COOLDOWN: float = 1.0 # 普通招聘冷却 3 秒

const HEADHUNT_COST: int = 500
const HEADHUNT_COOLDOWN: float = 1.0 # 猎头招聘冷却 10 秒

func _ready() -> void:

	# 更新按钮上的文本，显示价格
	normal_btn.text = "普通招聘 ($" + str(NORMAL_COST) + ")"
	headhunt_btn.text = "猎头招聘 ($" + str(HEADHUNT_COST) + ")"

# ==========================================
# 普通招聘逻辑
# ==========================================
func _on_normal_recruit() -> void:
	# 1. 找 EmployeeManager 扣钱
	if EmployeeManager.spend_money(NORMAL_COST):
		# 2. 扣钱成功，进入冷却
		_start_cooldown(normal_btn, NORMAL_COOLDOWN, "普通招聘 ($" + str(NORMAL_COST) + ")")
		
		# 3. 抽卡概率计算 (80% R, 20% SR)
		var rarity = Employee.Rarity.R
		if randf() > 0.8: 
			rarity = Employee.Rarity.SR
			
		# 4. 生成数据并发送
		_generate_and_deliver(rarity)
	else:
		print("UI提示：老板，账上没钱了！")

# ==========================================
# 猎头招聘逻辑
# ==========================================
func _on_headhunt_recruit() -> void:
	if EmployeeManager.spend_money(HEADHUNT_COST):
		_start_cooldown(headhunt_btn, HEADHUNT_COOLDOWN, "猎头招聘 ($" + str(HEADHUNT_COST) + ")")
		
		# 概率计算 (70% SR, 30% SSR)
		var rarity = Employee.Rarity.SR
		if randf() > 0.7: 
			rarity = Employee.Rarity.SSR
			
		_generate_and_deliver(rarity)
	else:
		print("UI提示：老板，猎头费不够！")

# ==========================================
# 核心生成逻辑
# ==========================================
func _generate_and_deliver(rarity: Employee.Rarity) -> void:
	# 创建纯数据实体
	var new_emp = Employee.new()
	# 模拟生成随机名字，后期你可以接一个名字库数组
	var random_names = ["Bob", "Alice", "Charlie", "David", "Eve"]
	new_emp.employee_name = random_names.pick_random() + "_" + str(randi() % 100)
	
	# 初始化属性
	new_emp.setup_employee(rarity)
	
	# 交给全局管理器入职
	EmployeeManager.hire_employee(new_emp)

# ==========================================
# 冷却时间倒计时器 (利用 Godot 4 的 Tween 实现按钮禁用与倒计时)
# ==========================================
func _start_cooldown(btn: Button, duration: float, original_text: String) -> void:
	btn.disabled = true
	
	# 使用 Tween 动态修改按钮文本显示倒计时
	var tween = create_tween()
	# 让一个虚拟变量从 duration 变到 0
	tween.tween_method(_update_btn_text.bind(btn), duration, 0.0, duration)
	
	# 倒计时结束恢复按钮
	tween.finished.connect(func():
		btn.disabled = false
		btn.text = original_text
	)

# 动态更新按钮文字的辅助函数
func _update_btn_text(time_left: float, btn: Button) -> void:
	btn.text = "冷却中 (%.1f s)" % time_left


func _on_fire_all_btn_pressed() -> void:
	EmployeeManager.fire_all_employees()
