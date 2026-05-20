extends Control
class_name SlackingBubble

signal slacking_resolved(by_click: bool)

@onready var icon_rect = $bubble/icon # 对应你放图标的TextureRect节点名
@onready var timer = $Timer
# 🌟 新增：引用气泡的主体节点（如果是 bubble 整体缩放效果更好）
@onready var bubble_main = $bubble
@onready var bubble_clicked: AudioStreamPlayer = $BubbleClicked

var icons = [
	preload("res://assets/UI/摸鱼气泡/异常行为-打瞌睡.png"),
	preload("res://assets/UI/摸鱼气泡/手柄.png"),
	preload("res://assets/UI/摸鱼气泡/爱心.png")
]

func _ready():
	icon_rect.texture = icons.pick_random()
	timer.wait_time = 30.0
	timer.one_shot = true
	timer.timeout.connect(_on_timeout)
	timer.start()
	# 🌟 开启“呼吸”动画
	_start_breathing_animation()

func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		bubble_clicked.play()
		# 🌟 点击反馈：被点中的瞬间弹一下
		var t = create_tween()
		t.tween_property(bubble_main, "scale", Vector2(0.8, 0.8), 0.05)
		t.tween_callback(func(): resolve(true)) # 弹小后消失
		accept_event()

func resolve(by_click: bool):
	slacking_resolved.emit(by_click)
	queue_free()

func _on_timeout():
	resolve(false)

func _start_breathing_animation():
	# 确保缩放中心在气泡正中央（非常重要，否则会往右下角放大）
	bubble_main.pivot_offset = bubble_main.size / 2
	
	# 创建一个无限循环的 Tween
	var tween = create_tween().set_loops()
	
	# 第一步：1.2秒内放大到 1.1 倍，使用平滑的过渡
	tween.tween_property(bubble_main, "scale", Vector2(1.1, 1.1), 1.2)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
		
	# 第二步：1.2秒内缩回到 1.0 倍
	tween.tween_property(bubble_main, "scale", Vector2(1.0, 1.0), 1.2)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
