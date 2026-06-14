#dialogue_intro_ui.gd
extends Control

signal intro_dialogue_finished

const CHAT_BUBBLE_SCENE: PackedScene = preload("res://scenes/starter/chat_bubble.tscn")
const CHAT_BUBBLE_AI_SCENE = preload("res://scenes/starter/KPIhelper_chat_bubble.tscn")

@onready var chat_scroll: ScrollContainer = $Background/MainMargin/ChatScroll
@onready var message_list: VBoxContainer = $Background/MainMargin/ChatScroll/MessageList
@onready var bubble_sound: AudioStreamPlayer = $BubbleSound

# 新加的：抓取我们刚刚创建的操作提示标签
@onready var hint_label: Label = $HintLabel

var current_speaker: int = 0
# 1. 我们的对话现在只需要一个简单的文本列表 (List)
var boss_messages := []

var current_index := 0
var is_animating := false
var is_finished := false

# 用于记录空格键按下的时间
var space_pressed_time := 0.0
var is_space_pressed := false
const SKIP_HOLD_TIME := 1.0 # 按住1秒就跳过

func _ready() -> void:
	# 隐藏滚动条，但保留滚动功能
	chat_scroll.get_v_scroll_bar().modulate.a = 0
	chat_scroll.get_h_scroll_bar().modulate.a = 0

	# ==== 新加的代码：让提示文本呼吸闪烁 ====
	# 如果成功抓到了这个节点，就开始播放循环动画
	if hint_label:
		var tween = create_tween().set_loops()
		tween.tween_property(hint_label, "modulate:a", 0.3, 0.8)
		tween.tween_property(hint_label, "modulate:a", 1.0, 0.8)

func start_dialogue(lines: Array[String], position_enum: int, offset_x: float, offset_y: float, speaker_enum: int) -> void:
	current_speaker = speaker_enum
	# 灌入这一步的台词
	boss_messages = lines
	current_index = 0
	is_finished = false
	
	# 重置并显示界面
	show()
	
	# 清理旧的气泡（防止上一步的残留气泡还在列表里）
	for child in message_list.get_children():
		child.queue_free()
		
	# 🌟 处理位置微调（基于你填的预设和 Offset）
	$Background.position = Vector2.ZERO 
	$Background.position.x += offset_x
	$Background.position.y += offset_y

	# 开始播放第一句话
	show_next_message()
	
# _process 会在游戏运行时一直循环执行，适合用来计算时间
func _process(delta: float) -> void:
	if is_finished:
		return

	# 2. 如果玩家按住了空格键，我们就开始计时
	if is_space_pressed:
		space_pressed_time += delta
		if space_pressed_time >= SKIP_HOLD_TIME:
			skip_dialogue()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if is_finished:
		return
#
	## 3. 检查空格键是按下还是松开
	## ====================================================
	## 💥【空格全面封锁阵】：长按交信，短按原地超度！
	# ====================================================
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			is_space_pressed = true
		elif not event.pressed:
			is_space_pressed = false
			space_pressed_time = 0.0 # 松开就时间归零
			
		# 🌟 核心绝杀：把这个空格事件标记为“已处理”！
		# 这样 Godot 引擎底层的 ui_accept 机制和全场所有的 UI 焦点，
		# 就会认为这个空格键压根没发生过，绝对无法触发任何按钮的连点或翻篇！
		get_viewport().set_input_as_handled()
		return # 💥 强行打断！空格事件到此为止，绝对不允许往下走！
	# ====================================================

	if is_animating:
		return

	# 4. 检查鼠标左键点击，显示下一句
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_animating:
				return
			show_next_message()
			bubble_sound.play()

func show_next_message() -> void:
	if current_index >= boss_messages.size():
		finish_intro_dialogue()
		return

	is_animating = true

	var text: String = boss_messages[current_index]
	current_index += 1
	
	await add_message(text)

	is_animating = false

func add_message(text: String) -> void:
	var bubble = null
	if current_speaker == 1: # 假设 1 是 KPI_BAO
		bubble = CHAT_BUBBLE_AI_SCENE.instantiate()
	else:
		bubble = CHAT_BUBBLE_SCENE.instantiate()
		
	message_list.add_child(bubble)
	bubble.setup(text)
	
	# 刚出现时透明度为0（看不见）
	bubble.modulate.a = 0.0

	# 等待一瞬间，让系统计算好气泡的大小
	await get_tree().process_frame
	await get_tree().process_frame

	# 5. 让滚动条滚到底部。
	scroll_to_bottom()

	# 气泡渐渐出现的动画
	var tween = create_tween()
	tween.tween_property(bubble, "modulate:a", 1.0, 0.42)
	await tween.finished

func scroll_to_bottom() -> void:
	var max_scroll = chat_scroll.get_v_scroll_bar().max_value
	chat_scroll.scroll_vertical = int(max_scroll)

func skip_dialogue() -> void:
	if is_finished: return
	
	is_space_pressed = false 
	finish_intro_dialogue()

func finish_intro_dialogue() -> void:
	is_finished = true

	# 🌟 核心修改 A：立刻把对话主界面隐藏起来
	hide() 
	
	# 🌟 核心修改 B：发出信号
	intro_dialogue_finished.emit()
