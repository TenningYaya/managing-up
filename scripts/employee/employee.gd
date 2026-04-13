extends Control
class_name Employee

# 定义稀有度枚举
enum Rarity { R, SR, SSR }

# --- 核心属性 ---
var employee_name: String = "Marry"
var rarity: Rarity

var efficiency: int = 1 # 工作效率 (1-10)
var quality: int = 1    # 工作质量 (1-10)
var experience: int = 1 # 工作经验 (1-10)

# --- 位置与状态变量 ---
var current_seat: DeskSeat = null # 当前所在的工位
var is_dragging: bool = false      # 是否正在被拖拽
var original_position: Vector2 = Vector2.ZERO # 拖拽前的原始位置

func _ready() -> void:
	add_to_group("employees")
	# 确保随机数种子刷新
	randomize() 

# 当你招聘到新同事时，调用此函数初始化属性
func setup_employee(new_rarity: Rarity) -> void:
	rarity = new_rarity
	_generate_attributes()

# 根据 GDD 文档规则生成属性的算法
func _generate_attributes() -> void:
	var target_sum: int = 0
	
	# 1. 根据稀有度确定属性总和的区间
	match rarity:
		Rarity.R:
			target_sum = randi_range(3, 12)
		Rarity.SR:
			target_sum = randi_range(13, 21)
		Rarity.SSR:
			target_sum = randi_range(14, 30)
			
	# 2. 分配属性点
	# 所有属性初始设为 1（确保满足 1-10 的区间要求）
	efficiency = 1
	quality = 1
	experience = 1
	
	var current_sum: int = 3
	var remaining_points: int = target_sum - current_sum
	
	# 随机分配剩余的点数，同时确保单项属性不超过 10
	while remaining_points > 0:
		# 随机选择一个属性（0:效率, 1:质量, 2:经验）
		var stat_to_increase = randi() % 3
		
		if stat_to_increase == 0 and efficiency < 10:
			efficiency += 1
			remaining_points -= 1
		elif stat_to_increase == 1 and quality < 10:
			quality += 1
			remaining_points -= 1
		elif stat_to_increase == 2 and experience < 10:
			experience += 1
			remaining_points -= 1

# --- 交互逻辑 ---

# 玩家点击并开始拖拽同事时触发
func pick_up() -> void:
	is_dragging = true
	original_position = global_position
	
	# 如果原本在工位上，离开时清除工位的占用状态
	if current_seat != null:
		current_seat.clear_occupant()
		current_seat = null
		
		# 执行 GDD 规则：如果生产被打断，根据进度结算部分 KPI
		_interrupt_production()

# 玩家松开鼠标放置同事时触发
func put_down(target_seat: DeskSeat) -> void:
	is_dragging = false
	
	# 检查目标工位是否合法且为空
	if target_seat != null and target_seat.is_free():
		# 成功放置到新工位
		current_seat = target_seat
		current_seat.set_occupant(self)
		# 自动吸附到工位的中心点
		global_position = current_seat.get_snap_global_position()
		
		# 开始文件生产循环
		_start_production()
	else:
		# 如果放置位置无效，返回原位或仓库
		global_position = original_position

# --- 生产逻辑占位符 ---

func _start_production() -> void:
	# TODO: 实现基础生产时间 600s 及其效率修正公式
	pass 

func _interrupt_production() -> void:
	# TODO: 清理进度条并根据 (当前进度 * 50%) 结算 KPI
	pass
