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

func pop_up(content: String) -> void:
	label.text = content
	
	if _tween:
		_tween.kill()
		
	_tween = create_tween()
	# 设置为并行模式：上浮和淡入同时发生
	_tween.set_parallel(true)
	
	# 🌟 动画 1：向上飘移
	# 这里的 -40 可以根据你想要飘的高度调整
	var target_pos = position + Vector2(0, -20) 
	_tween.tween_property(self, "position", target_pos, 0.5)
	
	# 🌟 动画 2：淡入
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	
	# 🌟 动画 3：在上方停留一会后渐隐消失 (连写逻辑)
	# 使用 chain() 确保在上面的“上浮”动作完成后执行
	_tween.chain().tween_property(self, "modulate:a", 0.0, 0.5).set_delay(1)
	
	# 🌟 结束：自动销毁
	_tween.chain().tween_callback(queue_free)
	
# 提供一个给外部强行打断并销毁的接口
func kill_bubble() -> void:
	if _tween:
		_tween.kill()
	queue_free()
