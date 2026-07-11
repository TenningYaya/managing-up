# gamemanager.gd
extends Node

signal request_employee_drop(data)
signal kpi_changed(new_value)
signal dollar_changed(new_value)
signal level_changed(new_level)
# 记录教程是否已经完成

enum OfficeType {
	NONE,
	PANTRY,
	MEETING_ROOM,
	RECRUITMENT,
	CULTURE_CENTER,
	STOCK_OFFICE,
	TRAINING_ROOM
}

enum SnackBuff {
	NONE = 0,
	MILK_TEA = 1,
	CAKE = 2,
	SAUSAGE = 3
}

const OFFICE_UNLOCK_LEVELS = {
	OfficeType.PANTRY: 1,          # M2 解锁
	OfficeType.RECRUITMENT: 3,     # M3 解锁
	OfficeType.MEETING_ROOM: 4,    # M4 解锁
	OfficeType.CULTURE_CENTER: 5,   # M5 解锁
	OfficeType.STOCK_OFFICE: 1,
	OfficeType.TRAINING_ROOM: 4    # 培训室解锁等级（想改就改这里）
}

var has_recruitment_office: bool = false
var has_culture_center: bool = false
var is_tutorial_completed: bool = false
var is_employee_interaction_disabled: bool = false
var is_reject_button_disabled: bool = false
var tutorial_allow_camera_drag: bool = false
var has_stock_office: bool = false

var project_name: String = "NewProject"
var player_avatar_index: int = 0
var player_avatar_texture: Texture2D = preload("res://assets/tutorial/avatars/player_avatar_1.png")
var has_selected_avatar: bool = false
# 🌟 当前头像是不是玩家自己上传的自定义图(true 时图片落地在 user://player_avatar.png,index 记 -1)
var player_avatar_is_custom: bool = false
# 定义总览面板需要的变量
var total_hits: int = 0
var total_time: float = 0.0
var total_speedups: int = 0   # 催工次数：点击同事成功加速生产的总次数

var player_level: int = 1:
	set(value):
		player_level = value
		level_changed.emit(player_level)

# 🌟 读档期间为 true:此时设置 player_level 等值会触发 level_changed,
#    但办公室/工位不该播"升级特效",用这个标记拦截(见 office.gd / DeskSlot.gd)。
var is_loading_save: bool = false
		
var kpi: int = 2000:
	set(value):
		kpi = value
		kpi_changed.emit(kpi)

var dollar: int = 100:
	set(value):
		dollar = value
		dollar_changed.emit(dollar)

var max_desk_level: int = 1
var unlocked_desk_slots: int = 1 # 解锁的工位排数
var sticky_note_text: String = ""
var phone_battery: float = 100.0   # 手机电量 0~100（纯氛围功能，存档保留），由 mobilesidebar 实时同步
var camera_pos: Vector2 = Vector2.ZERO   # 下线时相机(视角)位置，读档恢复
var has_saved_camera: bool = false        # 是否有待恢复的相机位置（读档设 true，玩家一拖动就消费掉）



func _ready() -> void:
	call_deferred("emit_signal", "dollar_changed", dollar)
	call_deferred("emit_signal", "kpi_changed", kpi)
	call_deferred("emit_signal", "level_changed", player_level)
	
# 每一帧自动更新游戏总时长
func _process(delta: float) -> void:
	total_time += delta

# 全局监听鼠标点击，不需要其他文件调用
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 只要鼠标左键按下，hit 就加 1
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			total_hits += 1

func hire_employee(data):
	request_employee_drop.emit(data)

# ================= KPI & Dollar 管理 =================
func has_enough_kpi(amount: int) -> bool:
	return kpi >= amount

func add_kpi(amount: int) -> void:
	kpi += amount

func spend_kpi(amount: int) -> bool:
	if kpi >= amount:
		kpi -= amount
		return true
	return false

func has_enough_dollar(amount: int) -> bool:
	return dollar >= amount

func add_dollar(amount: int) -> void:
	dollar += amount

func spend_dollar(amount: int) -> bool:
	if dollar >= amount:
		dollar -= amount
		return true
	return false
