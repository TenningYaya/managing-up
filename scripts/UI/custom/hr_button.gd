# hr_button.gd
extends TextureButton

signal viewer_ready

enum CharacterSet { NORMAL, HEAD }
enum AnimState { WALK, RUN, RUNRUNRUN }

@export var character_set: CharacterSet = CharacterSet.NORMAL

@export var button_text: String = "InputButtonName":
	set(value):
		button_text = value
		if is_inside_tree() and has_node("MarginContainer/HBoxContainer/Label"):
			$MarginContainer/HBoxContainer/Label.text = tr(button_text)

@export_group("NinePatch Background")
@export var bg_normal: Texture2D
@export var bg_pressed: Texture2D

@onready var bg_rect: NinePatchRect = $NinePatchRect
@onready var normal_anim: AnimatedSprite2D = $Control/NormalAnim
@onready var head_anim: AnimatedSprite2D = $Control/HeadAnim

const SPEED_UP_AMOUNT := 2.0
const CONSECUTIVE_THRESHOLD := 1.0
const RUN_THRESHOLD := 5
const RUNRUNRUN_THRESHOLD := 15

var _anim_state: AnimState = AnimState.WALK
var _click_count: int = 0
var _last_click_time: float = -999.0
var _active_anim: AnimatedSprite2D = null
var is_in_end_sequence: bool = false  # public，供 panel 检查

func _ready() -> void:
	if has_node("MarginContainer/HBoxContainer/Label"):
		$MarginContainer/HBoxContainer/Label.text = tr(button_text)

	if bg_normal:
		bg_rect.texture = bg_normal

	button_down.connect(_on_btn_down)
	button_up.connect(_on_btn_up)
	mouse_exited.connect(_on_btn_up)
	pressed.connect(_on_clicked)

	_setup_anim()
	match character_set:
		CharacterSet.NORMAL:
			RecruitmentManager.about_to_spawn_free_recruit.connect(_on_about_to_complete)
		CharacterSet.HEAD:
			RecruitmentManager.about_to_finish_headhunt.connect(_on_about_to_complete)

func _setup_anim() -> void:
	match character_set:
		CharacterSet.NORMAL:
			_active_anim = normal_anim
			head_anim.hide()
		CharacterSet.HEAD:
			_active_anim = head_anim
			normal_anim.hide()
	_active_anim.show()
	_active_anim.play("walk")

func _on_btn_down() -> void:
	if not disabled and bg_pressed:
		bg_rect.texture = bg_pressed

func _on_btn_up() -> void:
	if not disabled and bg_normal:
		bg_rect.texture = bg_normal

func _on_clicked() -> void:
	if is_in_end_sequence:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_click_time <= CONSECUTIVE_THRESHOLD:
		_click_count += 1
	else:
		_click_count = 1
	_last_click_time = now

	_speed_up_timer()
	_update_anim_state()

func _speed_up_timer() -> void:
	match character_set:
		CharacterSet.NORMAL:
			RecruitmentManager.free_recruit_time_left = maxf(0.0, RecruitmentManager.free_recruit_time_left - SPEED_UP_AMOUNT)
		CharacterSet.HEAD:
			if RecruitmentManager.current_state == RecruitmentManager.State.RECRUITING:
				RecruitmentManager.headhunt_time_left = maxf(0.0, RecruitmentManager.headhunt_time_left - SPEED_UP_AMOUNT)

func _update_anim_state() -> void:
	var new_state := _anim_state
	if _click_count >= RUNRUNRUN_THRESHOLD:
		new_state = AnimState.RUNRUNRUN
	elif _click_count >= RUN_THRESHOLD:
		new_state = AnimState.RUN

	if new_state != _anim_state:
		_anim_state = new_state
		match _anim_state:
			AnimState.RUN:       _active_anim.play("run")
			AnimState.RUNRUNRUN: _active_anim.play("runrunrun")

func _on_about_to_complete() -> void:
	if not is_visible_in_tree():
		return
	if _anim_state == AnimState.WALK:
		# 走路状态直接让 panel 正常显示，不拦截
		viewer_ready.emit()
		_reset_state()
	else:
		# 立刻把旗子立起来，此时 new_resumes_arrived 还没发出去
		is_in_end_sequence = true
		_play_end_sequence()

func _play_end_sequence() -> void:
	is_in_end_sequence = true
	disabled = true

	_active_anim.play("faint")
	await _active_anim.animation_finished

	for i in 2:
		_active_anim.play("sleep")
		await _active_anim.animation_finished

	viewer_ready.emit()
	_reset_state()

func _reset_state() -> void:
	is_in_end_sequence = false
	disabled = false
	_anim_state = AnimState.WALK
	_click_count = 0
	_last_click_time = -999.0
	_active_anim.play("walk")
