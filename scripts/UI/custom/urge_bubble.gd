#urge_bubble.gd
extends Node2D
class_name UrgeBubble

@onready var label: Label = $HBoxContainer/BubblePanel/TextLabel
@onready var panel: PanelContainer = $HBoxContainer/BubblePanel
@onready var player_avatar: TextureRect = $HBoxContainer/MarginContainer/PlayerAvatar

# 动画相关变量
var _tween: Tween = null

func _ready() -> void:
	
	player_avatar.custom_minimum_size = Vector2(167,167)
	player_avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	player_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	if Gamemanager.player_avatar_texture:
		player_avatar.texture = Gamemanager.player_avatar_texture
	else:
		player_avatar.hide()  # 没选头像就藏起来，不留空白
	
func pop_up(content: String) -> void:
	label.text = content
	if Gamemanager.player_avatar_texture != null:
		player_avatar.texture = Gamemanager.player_avatar_texture
		player_avatar.show()
	else:
		player_avatar.hide()

	
	if _tween:
		_tween.kill()
		
	_tween = create_tween()
	# 设置为并行模式：上浮和淡入同时发生
	_tween.set_parallel(true)
	
# 🌟 动画 1：向上浮动
	# Vector2(0, -20): 目标偏移量，X为0表示横向不动，Y为-20表示向上移动20个像素
	# 0.5: 完成这次上浮动作需要的时长，单位是秒
	var target_pos = position + Vector2(0, -20) 
	_tween.tween_property(self, "position", target_pos, 0.5)
	
	# 🌟 动画 2：淡入
	# 1.0: 目标透明度，1.0代表完全不透明（显示）
	# 0.3: 完成淡入显示的时间，单位是秒
	_tween.tween_property(self, "modulate:a", 1.0, 1)
	
	# 🌟 动画 3：在上方停留一会后渐隐消失
	# .set_delay(1): 延迟执行时间，单位是秒（即：保持显示状态停留 1 秒）
	# 0.0: 目标透明度，0.0代表完全透明（消失）
	# 0.5: 完成这次渐隐过程的时间，单位是秒
	_tween.chain().tween_property(self, "modulate:a", 0.0, 1).set_delay(1)
	
	# 🌟 结束：自动销毁
	_tween.chain().tween_callback(queue_free)
	
# 提供一个给外部强行打断并销毁的接口
func kill_bubble() -> void:
	if _tween:
		_tween.kill()
	queue_free()
