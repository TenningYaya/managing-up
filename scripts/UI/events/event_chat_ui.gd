# event_chat_ui.gd
# 微信式"公司群"事件弹窗：
#   1. 顶部标题 = 玩家项目名 + "公司群"
#   2. 员工依次冒泡说话（复用 dialogue_intro_ui 的气泡淡入/滚动逻辑 + chat_bubble.tscn 样式，
#      但把气泡里的 TextureRect2 换成随机在职员工的头像）
#   3. 底部是一个"假输入框"（按钮，贴图 bubble_mobile_sidebar.png）
#   4. 点假输入框弹出两个选项按钮，玩家选一个 → 该选项以玩家气泡形式进入对话，随后事件结束
extends Control

signal event_finished

const CHAT_BUBBLE_SCENE: PackedScene = preload("res://scenes/starter/chat_bubble.tscn")

const MSG_INTERVAL := 0.8      # 员工每条消息之间的间隔（秒）
const FADE_TIME := 0.42        # 气泡淡入时长（与 intro 对话一致）
const END_DELAY := 0.9         # 玩家选完之后停留多久再关闭
# 气泡在本弹窗里的最大宽度（窗口 640 宽，留出头像+边距后约 460）：超过就自动换行
const BUBBLE_MAX_WIDTH := 460.0

# 事件内容与 buff 都在 scripts/events/event_definitions.gd 的 EVENTS 里配置，
# 文本（中英文）在 language/events.csv 里填。这里只负责把它们显示出来 + 应用 buff。

@onready var dimmer: ColorRect = $Dimmer
@onready var title_label: Label = $Window/VBox/Header/TitleLabel
@onready var chat_scroll: ScrollContainer = $Window/VBox/ChatArea/ChatScroll
@onready var message_list: VBoxContainer = $Window/VBox/ChatArea/ChatScroll/MessageList
@onready var fake_input: BaseButton = $Window/VBox/BottomBar/FakeInput
@onready var input_placeholder: Label = $Window/VBox/BottomBar/FakeInput/Placeholder
@onready var options_container: VBoxContainer = $Window/OptionsContainer
@onready var option_btn_1: Button = $Window/OptionsContainer/Option1
@onready var option_btn_2: Button = $Window/OptionsContainer/Option2
@onready var bubble_sound: AudioStreamPlayer = $BubbleSound

var _options: Array = []
var _current_event_id: String = ""  # 🏆 本次事件的稳定标识(首条消息key)，供"全部事件"成就统计
var _busy := false        # 员工消息还在播放：禁止点输入框
var _answered := false     # 玩家已经选过：不再响应
var _closed := false       # 已经关闭：正在播放的协程要及时中止

func _ready() -> void:
	# 挂到 CanvasLayer 下时根节点不一定会自动铺满视口，强制铺满，
	# 这样底部对齐的遮罩/窗口才会落在可见的游戏窗口区域，而不是飘到透明桌面上
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	position = Vector2.ZERO

	# 隐藏滚动条，保留滚动功能
	chat_scroll.get_v_scroll_bar().modulate.a = 0.0
	chat_scroll.get_h_scroll_bar().modulate.a = 0.0

	input_placeholder.text = tr("Event_input_placeholder")

	fake_input.pressed.connect(_on_fake_input_pressed)
	option_btn_1.pressed.connect(_on_option_1_pressed)
	option_btn_2.pressed.connect(_on_option_2_pressed)
	# 注意：不再连 dimmer 的点击关闭。遮罩只负责挡住点击（mouse_filter=STOP），
	# 事件必须由玩家选一个选项才会关，点别处一律无效。

	options_container.visible = false
	_set_input_enabled(false)

	# 打开事件弹窗期间禁止和世界里的员工互动（避免点击穿透到背后员工）
	Gamemanager.is_employee_interaction_disabled = true

# 从事件表里随机抽一个事件并打开
func open_random_event(project_name: String) -> void:
	var events: Array = EventDefinitions.EVENTS
	if events.is_empty():
		_close()
		return
	var event_data: Dictionary = events[randi() % events.size()]
	open_event(event_data, project_name)

func open_event(event_data: Dictionary, project_name: String) -> void:
	# 标题：xx公司群（用后缀拼接，避免翻译未导入时 %s 格式化报错）
	title_label.text = project_name + tr("Event_group_chat_suffix")

	_options = event_data.get("options", [])
	# 🏆 记录本次事件标识(首条消息 key)，供"全部事件"成就统计
	var msgs: Array = event_data.get("messages", [])
	_current_event_id = str(msgs[0]) if not msgs.is_empty() else ""
	option_btn_1.text = _option_text(0)
	option_btn_2.text = _option_text(1)
	option_btn_2.visible = _options.size() > 1

	# 清空旧气泡
	for child in message_list.get_children():
		child.queue_free()

	_answered = false
	show()

	_play_employee_messages(event_data.get("messages", []))

# 取第 index 个选项要显示的文字（用 events.csv 的 key 翻译）
func _option_text(index: int) -> String:
	if index >= _options.size():
		return ""
	return tr(str(_options[index].get("text", "")))

# ---------------------------------------------------------------------
# 员工消息依次冒泡
# ---------------------------------------------------------------------
func _play_employee_messages(messages: Array) -> void:
	_busy = true
	_set_input_enabled(false)
	for key in messages:
		if _closed:
			return
		await _add_employee_message(tr(str(key)))   # key 是 events.csv 里的文本 key
		if _closed:
			return
		await get_tree().create_timer(MSG_INTERVAL).timeout
	if _closed:
		return
	_busy = false
	_set_input_enabled(true)

func _add_employee_message(text: String) -> void:
	var bubble := CHAT_BUBBLE_SCENE.instantiate()
	message_list.add_child(bubble)
	bubble.max_bubble_width = BUBBLE_MAX_WIDTH   # 说太多就换行，别超出窗口
	bubble.setup(text)              # 复用 chat_bubble 的样式/尺寸逻辑
	_apply_random_employee_avatar(bubble)

	# 复用 intro 对话的淡入 + 滚动到底
	bubble.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _closed or not is_instance_valid(bubble):
		return
	_scroll_to_bottom()
	if is_instance_valid(bubble_sound):
		bubble_sound.play()
	var tween := create_tween()
	tween.tween_property(bubble, "modulate:a", 1.0, FADE_TIME)
	await tween.finished
	# 气泡高度是延迟一两帧按真实行数校正的，等它稳定后再对齐到底部
	if not _closed:
		_scroll_to_bottom()

# 把 chat_bubble 里 TextureRect2（原本是老板图）换成随机在职员工的头像
func _apply_random_employee_avatar(bubble: Node) -> void:
	var tex2 := bubble.get_node_or_null("MarginContainer/TextureRect2") as TextureRect
	if tex2 == null:
		return
	var emp = _pick_random_employee()
	if emp != null and emp.portrait != null:
		AvatarHelper.apply_portrait(tex2, emp.portrait, emp.rarity)
	# 否则：没有在职员工/头像未生成时，保留 chat_bubble 自带的默认头像（保底）

func _pick_random_employee():
	var list: Array = EmployeeManager.my_employees
	if list == null or list.is_empty():
		return null
	return list[randi() % list.size()]

# ---------------------------------------------------------------------
# 假输入框 → 选项 → 玩家气泡
# ---------------------------------------------------------------------
func _on_fake_input_pressed() -> void:
	if _busy or _answered:
		return
	options_container.visible = not options_container.visible

func _on_option_1_pressed() -> void:
	_on_option_chosen(0)

func _on_option_2_pressed() -> void:
	_on_option_chosen(1)

func _on_option_chosen(index: int) -> void:
	if _answered or index >= _options.size():
		return
	_answered = true
	SteamManager.mark_event_seen(_current_event_id)  # 🏆 全部事件：记录体验过的事件
	options_container.visible = false
	_set_input_enabled(false)

	var opt: Dictionary = _options[index]
	# 1. 玩家选的话进入对话
	await _add_player_message(_option_text(index))

	# 2. 应用这个选项对应的 buff（全体员工，持续 3 分钟）
	var stat := str(opt.get("stat", ""))
	var amount := int(opt.get("amount", 0))
	if stat != "" and amount != 0:
		OfficeManager.apply_event_buff(stat, amount)
		await _add_system_message(_buff_toast_text(stat, amount))

	await get_tree().create_timer(END_DELAY).timeout
	_close()

# 拼出 buff 提示文字，例如 "全体员工 效率 +1（持续 3 分钟）"
func _buff_toast_text(stat: String, amount: int) -> String:
	var stat_name := stat
	match stat:
		"efficiency": stat_name = tr("Event_stat_efficiency")
		"quality":    stat_name = tr("Event_stat_quality")
		"experience": stat_name = tr("Event_stat_experience")
	var amt_str := ("+" if amount > 0 else "") + str(amount)
	return tr("Event_buff_prefix") + stat_name + " " + amt_str + tr("Event_buff_suffix")

# 往对话里加一条居中的灰色系统提示（buff 生效）
func _add_system_message(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1))
	lbl.add_theme_font_size_override("font_size", 18)
	message_list.add_child(lbl)
	await get_tree().process_frame
	if _closed:
		return
	_scroll_to_bottom()

func _add_player_message(text: String) -> void:
	var bubble := CHAT_BUBBLE_SCENE.instantiate()
	message_list.add_child(bubble)
	bubble.max_bubble_width = BUBBLE_MAX_WIDTH   # 说太多就换行，别超出窗口
	bubble.setup(text)
	# 玩家气泡：靠右对齐、隐藏头像
	bubble.alignment = BoxContainer.ALIGNMENT_END
	var avatar := bubble.get_node_or_null("MarginContainer") as Control
	if avatar != null:
		avatar.visible = false

	bubble.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _closed or not is_instance_valid(bubble):
		return
	_scroll_to_bottom()
	if is_instance_valid(bubble_sound):
		bubble_sound.play()
	var tween := create_tween()
	tween.tween_property(bubble, "modulate:a", 1.0, FADE_TIME)
	await tween.finished
	if not _closed:
		_scroll_to_bottom()

# ---------------------------------------------------------------------
# 杂项
# ---------------------------------------------------------------------
func _scroll_to_bottom() -> void:
	var max_scroll := chat_scroll.get_v_scroll_bar().max_value
	chat_scroll.scroll_vertical = int(max_scroll)

func _set_input_enabled(enabled: bool) -> void:
	fake_input.disabled = not enabled
	fake_input.modulate.a = 1.0 if enabled else 0.55

func _close() -> void:
	if _closed:
		return
	_closed = true
	Gamemanager.is_employee_interaction_disabled = false
	event_finished.emit()
	queue_free()
