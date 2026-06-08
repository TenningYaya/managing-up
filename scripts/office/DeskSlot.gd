#DeskSlot.gd
extends Control
class_name DeskSlot

# 🌟 在编辑器里设置：这个桌子大槽位到底在玩家几级时开放解锁（比如 2 级）
@export var unlock_at_level: int = 1 

var slot_level: int = 1
var is_locked: bool = true # 🌟 新增：记录当前桌子是锁着还是开着

@onready var grid_container = $CenterContainer/GridContainer
@onready var upgrade_trigger_btn = $UpgradeTriggerBtn 
@onready var updated: CanvasItem = $Updated

var _is_initialized: bool = false

func _ready():
	add_to_group("desk_slots")
	upgrade_trigger_btn.pressed.connect(_on_slot_clicked)
	
	if updated:
		updated.hide() # 刚进游戏默认藏好特效
		
	# 🌟 1. 监听全局玩家等级变化信号
	if Gamemanager.has_signal("level_changed"):
		Gamemanager.level_changed.connect(_on_level_changed)
		
	# 🌟 2. 刚进游戏时，先静默跑一次等级判定（此时 _is_initialized 还是 false，完美拦截读档特效）
	_check_level_unlock(Gamemanager.player_level)
	
	_is_initialized = true

# 🌟 3. 全局等级变动时的核心监听函数
func _on_level_changed(new_level: int) -> void:
	_check_level_unlock(new_level)

# 🌟 4. 专职判定生死的底层函数
func _check_level_unlock(current_player_level: int) -> void:
	if current_player_level >= unlock_at_level:
		if is_locked and _is_initialized:
			_play_upgrade_bounce_fx()

		is_locked = false
		modulate.a = 1.0
		mouse_filter = MOUSE_FILTER_STOP
		upgrade_trigger_btn.disabled = false
	else:
		is_locked = true
		# 用透明度隐藏而不是 hide()，保持在 HBoxContainer 中占位，防止布局变化导致已部署员工位置偏移
		modulate.a = 0.0
		mouse_filter = MOUSE_FILTER_IGNORE
		upgrade_trigger_btn.disabled = true

func _on_slot_clicked():
	var panel = get_tree().get_first_node_in_group("upgrade_panel")
	if panel:
		panel.open(self)

func upgrade_all():
	if slot_level < 4:
		slot_level += 1
		for desk in grid_container.get_children():
			if desk is DeskSeat: 
				desk.set_upgrade_level(slot_level)

# ==========================================
# 🌟 黄金编排：前3.5秒常亮，后1.5秒淡出，安全隐藏
# ==========================================
func _play_upgrade_bounce_fx() -> void:
	if not updated: return
	
	updated.show()
	updated.modulate.a = 1.0
	
	if updated.has_method("play"):
		updated.play()
	elif updated.has_method("restart"):
		updated.restart()
		
	var fx_tween = create_tween()
	fx_tween.tween_interval(3.5) # 前 3.5 秒饱满不透明
	fx_tween.tween_property(updated, "modulate:a", 0.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fx_tween.tween_callback(updated.hide)
