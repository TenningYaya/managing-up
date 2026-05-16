extends Control

const CHAT_BUBBLE_SCENE: PackedScene = preload("res://scenes/starter/chat_bubble.tscn")

@onready var chat_scroll: ScrollContainer = $Background/MainMargin/ChatScroll
@onready var message_list: VBoxContainer = $Background/MainMargin/ChatScroll/MessageList


# 一个 turn = Boss 先说一句，然后玩家点击后 Employee 回复一句
var dialogue_turns := [
	{
		"boss": "早上坏，欢迎来新写字楼、新办公室",
		"employee": "……早上坏？"
	},
	{
		"boss": "我知道早上上班的心情总是很艹蛋，因为我也是",
		"employee": "原来老板也知道。"
	},
	{
		"boss": "所以，新项目组的工作就全交给你了",
		"employee": "等一下，这个“所以”是怎么推出来的？"
	},
	{
		"boss": "给它取个名字吧",
		"employee": "我连项目组是干什么的都还不知道。"
	},
	{
		"boss": "什么？你说你不会管人也不会取名字？",
		"employee": "我刚来第一天，这很合理吧。"
	},
	{
		"boss": "嗯……你要知道，把你招进来的时候，我对你是有很高的期望的",
		"employee": "这句话听起来不像鼓励，像压力。"
	},
	{
		"boss": "再说了，现在AI什么的不是很好用吗？有事问AI去吧",
		"employee": "所以我的入职培训是问 AI？"
	},
	{
		"boss": "好了，我这边的游轮慈善晚宴都要开始了",
		"employee": "游轮……慈善……晚宴？"
	},
	{
		"boss": "好好学，好好干",
		"employee": "听起来像是没有人会教我。"
	},
	{
		"boss": "绩效好的话一切都好说，bye~",
		"employee": "那绩效不好呢？喂？老板？"
	}
]

var current_turn_index := 0

# Boss 说完后，才允许玩家点击发送 Employee 回复
var waiting_for_employee_reply := false

# 动画播放中不允许重复点击
var is_animating := false
var is_finished := false

# Employee 回复后，Boss 下一句出现前的等待时间
var boss_next_delay := 0.8


func _ready() -> void:
	# 隐藏滚动条，但保留自动滚动功能
	chat_scroll.get_v_scroll_bar().modulate.a = 0
	chat_scroll.get_h_scroll_bar().modulate.a = 0

	# 开场：Boss 先发第一句话
	start_next_boss_message()


func _unhandled_input(event: InputEvent) -> void:
	if is_finished:
		return

	if is_animating:
		return

	if not waiting_for_employee_reply:
		return

	if _is_advance_input(event):
		send_employee_reply()


func _is_advance_input(event: InputEvent) -> bool:
	# 鼠标左键
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			return true

	# 空格键
	if event is InputEventKey:
		if event.keycode == KEY_SPACE and event.pressed and not event.echo:
			return true

	return false


func start_next_boss_message() -> void:
	if current_turn_index >= dialogue_turns.size():
		finish_intro_dialogue()
		return

	is_animating = true
	waiting_for_employee_reply = false

	var boss_text: String = dialogue_turns[current_turn_index]["boss"]
	await add_message("boss", boss_text)

	is_animating = false
	waiting_for_employee_reply = true


func send_employee_reply() -> void:
	is_animating = true
	waiting_for_employee_reply = false

	var employee_text: String = dialogue_turns[current_turn_index]["employee"]
	await add_message("employee", employee_text)

	current_turn_index += 1

	await get_tree().create_timer(boss_next_delay).timeout

	start_next_boss_message()


func add_message(speaker: String, dialogue_text: String) -> void:
	var bubble = CHAT_BUBBLE_SCENE.instantiate()
	message_list.add_child(bubble)

	# Boss：先显示正在输入
	# Employee：先显示空文字，后面再打字机显示
	if speaker == "boss":
		bubble.setup(speaker, ".....")
	elif speaker == "employee":
		bubble.setup(speaker, "")
	else:
		bubble.setup(speaker, dialogue_text)

	# 气泡出现动画
	bubble.modulate.a = 0.0
	# bubble.position.y += 12

	await get_tree().process_frame

	chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bubble, "modulate:a", 1.0, 0.22)
	#tween.tween_property(bubble, "position:y", bubble.position.y - 12, 0.22)

	await tween.finished

	# Boss：播放 ..... 输入动画，然后替换成正式内容
	if speaker == "boss":
		await play_boss_typing_animation(bubble)
		bubble.set_dialogue_text(dialogue_text)

		await get_tree().process_frame
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

	# Employee：一个字母一个字母打出来
	elif speaker == "employee":
		await bubble.type_dialogue_text(dialogue_text, 0.035)

		await get_tree().process_frame
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func play_boss_typing_animation(bubble) -> void:
	var typing_frames := [
		".",
		"..",
		"...",
		"....",
		"....."
	]

	for i in range(2):
		for frame in typing_frames:
			bubble.set_dialogue_text(frame)
			await get_tree().create_timer(0.18).timeout


func finish_intro_dialogue() -> void:
	is_finished = true
	waiting_for_employee_reply = false
	is_animating = false

	print("Intro dialogue finished. Start tutorial here.")

	# 之后可以在这里隐藏剧情对话 UI，进入新手引导
	# hide()
	# TutorialUI.show()
