#speech_bubble.gd
extends Node2D
class_name SpeechBubble

@onready var label: Label = $BubblePanel/TextLabel
@onready var panel: PanelContainer = $BubblePanel

# 动画相关变量
var _tween: Tween = null

func _ready() -> void:
	# 初始状态设为不可见和极小
	scale = Vector2.ZERO

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

	if _tween:
		_tween.kill()
		
	_tween = create_tween()
	# 设置为并行模式：上浮和淡入同时发生
	_tween.set_parallel(true)
	
# 🌟 动画 1：向上浮动
	# Vector2(0, -20): 目标偏移量，X为0表示横向不动，Y为-20表示向上移动20个像素
	# 0.5: 完成这次上浮动作需要的时长，单位是秒
	var target_pos = position + Vector2(0, -20) 
	_tween.tween_property(self, "position", target_pos, 1.5)
	
	# 🌟 动画 2：淡入
	# 1.0: 目标透明度，1.0代表完全不透明（显示）
	# 0.3: 完成淡入显示的时间，单位是秒
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	
	# 🌟 动画 3：在上方停留一会后渐隐消失
	# .set_delay(1): 延迟执行时间，单位是秒（即：保持显示状态停留 1 秒）
	# 0.0: 目标透明度，0.0代表完全透明（消失）
	# 0.5: 完成这次渐隐过程的时间，单位是秒
	_tween.chain().tween_property(self, "modulate:a", 0.0, 0.5).set_delay(3)
	
	# 🌟 结束：自动销毁
	_tween.chain().tween_callback(queue_free)
	
# 提供一个给外部强行打断并销毁的接口
func kill_bubble() -> void:
	if _tween:
		_tween.kill()
	queue_free()
