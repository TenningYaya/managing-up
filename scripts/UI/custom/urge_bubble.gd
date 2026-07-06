#urge_bubble.gd
extends Node2D
class_name UrgeBubble

# =====================================================================
# 催工气泡 · 位置与间距调参地图
# （气泡从员工头顶冒出、旧的被顶上去堆叠；下面列出所有相关参数在哪、调它会怎样）
# ---------------------------------------------------------------------
# 【整列位置】employee.gd → _spawn_speech_bubble：bubble.position = Vector2(20 + jitter, -47)
#   · 60   基准 x（相对员工偏右）：调大→整列右移；负→左移
#   · -17  基准 y（离员工原点的高度）：越负→越高；往 0 调→越贴头顶
#
# 【左右晃动】employee.gd → const URGE_X_JITTER（现 30）
#   · 每条刷出时 x 随机偏移 ±该值：调大→晃得更狂；0→完全对齐成一竖列
#
# 【上下间距 · 最常调】employee.gd 顶部常量
#   · URGE_STACK_ROW （现 54）：单行气泡的间距（基础值），调小更紧凑
#   · URGE_LINE_EXTRA（现 24）：每多一行再加的间距（多行被压→调大）
#   · 公式：间距 = URGE_STACK_ROW + (行数-1) × URGE_LINE_EXTRA
#
# 【气泡大小】employee.gd → bubble.scale（现 0.3）；字号在本场景 TextLabel.font_size（现 64）
#   · ⚠️ 间距是固定像素、不随 scale/字号自动变——改了大小要回头重调上面两个间距常量！
#
# 【上浮动画 / 停留时长】本文件 pop_up()
#   · "_float_offset"→20.0, 0.5s：向上漂浮 20px、耗时 0.5s
#   · 淡入 1s；停留 set_delay(1)；淡出 1s（总寿命约 3s）
#   · 想让柱子堆更高（更易"上青天"）：把停留 delay 调大，气泡活久点不易先消失
#
# 【换行宽度】本文件 const MAX_TEXT_WIDTH（现 900，×0.3≈270px 视觉）
#   · 文字超此宽才换行：调大→更晚换行、行数少、气泡更扁；调小→更早换行、行数多、更高
#
# 【透明窗口可见余量】本文件 const TOP_VIEWPORT_MARGIN（现 130）
#   · 窗口"可见上限"在锚点上方多留的余量：最上面那条顶部被透明区裁掉了就调大
#
# 最常用只碰三处（都在 employee.gd 顶部）：URGE_STACK_ROW / URGE_LINE_EXTRA / URGE_X_JITTER
# =====================================================================

@onready var label: Label = $HBoxContainer/BubblePanel/TextLabel
@onready var panel: PanelContainer = $HBoxContainer/BubblePanel
@onready var player_avatar: TextureRect = $HBoxContainer/MarginContainer/PlayerAvatar
@onready var urge_sfx: AudioStreamPlayer = $Urge
@onready var hbox: Control = $HBoxContainer   # 视觉主体：底边贴锚点、向上生长（多行只往上占，不压下面）

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
	# 让视觉主体"底边"贴着锚点、向上生长：多行气泡多出来的高度只往上占，不会往下压到下面那条
	if is_instance_valid(hbox):
		hbox.position.y = -hbox.size.y

const TOP_VIEWPORT_MARGIN := 130.0   # 视觉顶端在锚点上方的估计余量（气泡向上生长，多行更高），宁可多留别裁到

# 供 main.gd 计算"窗口可见上限"用：本气泡视觉顶端在视口坐标里的 y（越小越高）
func get_top_viewport_y() -> float:
	return get_global_transform_with_canvas().origin.y - TOP_VIEWPORT_MARGIN

# 这条台词换行后有几行，供堆叠按行数定间距。用字体度量同步算，不依赖布局帧 → 生成当帧就准。
func get_line_count() -> int:
	if not is_instance_valid(label):
		return 1
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	var line_h := font.get_height(fs)
	if line_h <= 0.0:
		return 1
	var wrap_w: float = label.custom_minimum_size.x   # _fit_label_width 已把换行宽度写进这里
	if wrap_w <= 0.0:
		wrap_w = MAX_TEXT_WIDTH
	var total_h := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs).y
	return maxi(1, int(round(total_h / line_h)))

func _ready() -> void:
	add_to_group("urge_bubbles")   # main.gd 据此把窗口可见上限抬到最高气泡处
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
