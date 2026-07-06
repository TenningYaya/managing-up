#urge_bubble.gd
extends Node2D
class_name UrgeBubble

@onready var label: Label = $HBoxContainer/BubblePanel/TextLabel
@onready var panel: PanelContainer = $HBoxContainer/BubblePanel
@onready var player_avatar: TextureRect = $HBoxContainer/MarginContainer/PlayerAvatar
@onready var urge_sfx: AudioStreamPlayer = $Urge

# 动画相关变量
var _tween: Tween = null
# —— 微信式堆叠：新气泡从底部冒出，旧气泡被顶上去 ——
var _base_y: float = 0.0            # 堆叠基准 y（被后来的气泡顶上去时改变）
var _base_y_target: float = 0.0
var _float_offset: float = 0.0      # 自身向上漂浮的位移（0→20）
var _stack_tween: Tween = null
var _active_anim := false

func _process(_delta: float) -> void:
	if not _active_anim:
		return
	# 最终 y = 堆叠基准 − 漂浮位移。堆叠(shift_up) 和 漂浮(pop_up) 各自独立 tween 一个变量，
	# 在这里合成成 position.y，从而"被顶上去"和"自己漂浮淡出"互不打架。
	position.y = _base_y - _float_offset

func _ready() -> void:
	
	player_avatar.custom_minimum_size = Vector2(167,167)
	player_avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	player_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	if Gamemanager.player_avatar_texture:
		player_avatar.texture = Gamemanager.player_avatar_texture
	else:
		player_avatar.hide()  # 没选头像就藏起来，不留空白
	
const MAX_TEXT_WIDTH := 900.0   # 文本最大宽度（局部坐标），超过即自动换行；按需调

# 短文本量到多宽就多宽（贴合不留白），长文本封顶并换行
func _fit_label_width() -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var one_line := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label.custom_minimum_size = Vector2(minf(one_line + 4.0, MAX_TEXT_WIDTH), 0.0)

func pop_up(content: String) -> void:
	label.text = content
	_fit_label_width()
	# 播放“鞭打员工”音效（场景里的 Urge 节点不会自动播放，必须手动触发）
	urge_sfx.play()
	if Gamemanager.player_avatar_texture != null:
		player_avatar.texture = Gamemanager.player_avatar_texture
		player_avatar.show()
	else:
		player_avatar.hide()

	
	# 记录堆叠基准；把"向上漂浮"改成 tween 一个偏移变量（不直接动 position，才能和"被顶上去"叠加）
	_base_y = position.y
	_base_y_target = position.y
	_float_offset = 0.0
	_active_anim = true

	if _tween:
		_tween.kill()
	_tween = create_tween()
	# 设置为并行模式：上浮和淡入同时发生
	_tween.set_parallel(true)
	# 🌟 动画 1：向上漂浮 20px（0.5s）——tween 偏移量，由 _process 合成到 position.y
	_tween.tween_property(self, "_float_offset", 20.0, 0.5)
	# 🌟 动画 2：淡入
	_tween.tween_property(self, "modulate:a", 1.0, 1)
	# 🌟 动画 3：停留 1s 后渐隐
	_tween.chain().tween_property(self, "modulate:a", 0.0, 1).set_delay(1)
	# 🌟 结束：自动销毁
	_tween.chain().tween_callback(queue_free)

# 被后来的气泡顶上去：把堆叠基准平滑上移 dy（独立于漂浮/淡出，其它动画完全不受影响）
func shift_up(dy: float) -> void:
	_base_y_target -= dy
	if _stack_tween:
		_stack_tween.kill()
	_stack_tween = create_tween()
	_stack_tween.tween_property(self, "_base_y", _base_y_target, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# 提供一个给外部强行打断并销毁的接口
func kill_bubble() -> void:
	if _tween:
		_tween.kill()
	if _stack_tween:
		_stack_tween.kill()
	queue_free()
