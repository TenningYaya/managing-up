# stock_logic.gd —— 炒股办公室逻辑（对应 PantryLogic / CultureCenterLogic，与 OfficeLogic 联动）
# 职责：
#   1. 登记/注销全局唯一标志 has_stock_office（change_office_button 据此置灰，防止再建第二个）。
#   2. 接管办公室上的 StockButton：悬停显示、离开收起（点击→开 Stock 页签的逻辑在 office.gd 里，
#      完全仿照文化室 ManageButton 那一套）。
#   3. 驻场分红：每 DIVIDEND_INTERVAL 秒随机发放 [DIVIDEND_MIN, DIVIDEND_MAX] 美金；
#      办公室被拆 / 改功能时（cleanup）计时立即停止、进度不保留（决策③）。
extends OfficeLogic
class_name StockOfficeLogic

# —— 驻场分红参数（会议决策：每 2 分钟随机发 $3~6）——
const DIVIDEND_INTERVAL := 120.0
const DIVIDEND_MIN := 3
const DIVIDEND_MAX := 6

# 飘字反馈：复用员工掉钱用的同一个特效
const DOLLAR_REWARD_SCENE := preload("res://scenes/vfx/dollar_reward.tscn")

var stock_btn: TextureButton
var _dividend_timer: Timer

func setup(office: Control) -> void:
	super.setup(office)
	my_office = office
	# 登记为已存在（全局唯一）
	OfficeManager.has_stock_office = true

	# 抓住办公室上的炒股按钮（悬停显隐由本逻辑管，点击开页由 office.gd 管）
	stock_btn = my_office.stock_btn

	# 启动驻场分红计时器
	_dividend_timer = Timer.new()
	_dividend_timer.wait_time = DIVIDEND_INTERVAL
	_dividend_timer.one_shot = false
	_dividend_timer.timeout.connect(_on_dividend)
	add_child(_dividend_timer)
	_dividend_timer.start()

func cleanup() -> void:
	# 撤场：停止并销毁分红计时器（进度不保留，下次重建从头计时）
	if is_instance_valid(_dividend_timer):
		_dividend_timer.stop()
		_dividend_timer.queue_free()
		_dividend_timer = null

	# 注销标志
	OfficeManager.has_stock_office = false

	# 归还按钮：藏起来（pressed 信号常驻在 office.gd，这里不断开）
	if is_instance_valid(stock_btn):
		stock_btn.hide()

	queue_free()

# —— 悬停显隐炒股按钮（仿文化室）——
func on_mouse_entered() -> void:
	if is_instance_valid(stock_btn):
		stock_btn.show()

func on_mouse_exited(mouse_pos: Vector2) -> void:
	if not is_instance_valid(stock_btn) or not is_instance_valid(my_office):
		return
	# 鼠标既不在按钮上、也不在办公室上，才收起按钮
	if not stock_btn.get_global_rect().has_point(mouse_pos) \
	and not my_office.get_global_rect().has_point(mouse_pos):
		stock_btn.hide()

# —— 驻场分红 ——
func _on_dividend() -> void:
	var amount := randi_range(DIVIDEND_MIN, DIVIDEND_MAX)
	Gamemanager.add_dollar(amount)
	_spawn_dividend_vfx()

func _spawn_dividend_vfx() -> void:
	if not is_instance_valid(my_office):
		return
	var vfx := DOLLAR_REWARD_SCENE.instantiate()
	my_office.get_tree().root.add_child(vfx)
	# 飘在办公室中心偏上
	vfx.global_position = my_office.global_position + Vector2(my_office.size.x * 0.5, my_office.size.y * 0.4)
	if vfx.has_method("play"):
		vfx.play()
