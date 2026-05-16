extends Control

const CHAT_BUBBLE_SCENE: PackedScene = preload("res://scenes/starter/chat_bubble.tscn")

@onready var chat_scroll: ScrollContainer = $Background/MainMargin/ChatScroll
@onready var message_list: VBoxContainer = $Background/MainMargin/ChatScroll/MessageList


# 每一个小数组是一组对话
# 点击一次 / 空格一次，会播放一整组
var dialogue_groups := [
	[
		{
			"speaker": "boss",
			"text": "Welcome to the company."
		},
		{
			"speaker": "employee",
			"text": "Thanks... I think?"
		}
	],
	[
		{
			"speaker": "boss",
			"text": "Your job is simple. Keep the KPI alive."
		},
		{
			"speaker": "employee",
			"text": "That sounds legally suspicious."
		}
	],
	[
		{
			"speaker": "boss",
			"text": "If the numbers go up, you survive."
		},
		{
			"speaker": "employee",
			"text": "Cool. Very normal first day."
		}
	]
]


var current_group_index := 0
var is_finished := false
var is_playing_group := false


func _ready() -> void:
	# 隐藏滚动条，但保留自动滚动功能
	chat_scroll.get_v_scroll_bar().modulate.a = 0
	chat_scroll.get_h_scroll_bar().modulate.a = 0

	# 进入界面时，自动播放第一组对话
	show_next_group()

func _unhandled_input(event: InputEvent) -> void:
	if is_finished:
		return

	if is_playing_group:
		return

	# 鼠标左键点击
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			show_next_group()

	# 空格键
	if event is InputEventKey:
		if event.keycode == KEY_SPACE and event.pressed and not event.echo:
			show_next_group()


func show_next_group() -> void:
	if is_playing_group:
		return

	if current_group_index >= dialogue_groups.size():
		finish_intro_dialogue()
		return

	is_playing_group = true

	var group = dialogue_groups[current_group_index]

	for line in group:
		await add_message(line["speaker"], line["text"])
		await get_tree().create_timer(0.9).timeout

	current_group_index += 1
	is_playing_group = false


func add_message(speaker: String, dialogue_text: String) -> void:
	var bubble = CHAT_BUBBLE_SCENE.instantiate()
	message_list.add_child(bubble)

	bubble.setup(speaker, dialogue_text)

	# 等一帧，让 VBoxContainer 先完成排版
	await get_tree().process_frame

	# 自动滚到底部，让最新对话出现
	chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)


func finish_intro_dialogue() -> void:
	is_finished = true
	print("Intro dialogue finished. Start tutorial here.")

	# 之后你可以在这里：
	# 1. hide() 隐藏这个对话界面
	# 2. show() 显示新手引导界面
	# 3. 或者切换到正式游戏状态
