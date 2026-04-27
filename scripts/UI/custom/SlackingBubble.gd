extends Control
class_name SlackingBubble

signal slacking_resolved(by_click: bool)

@onready var icon_rect = $bubble/icon # 对应你放图标的TextureRect节点名
@onready var timer = $Timer

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

func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		resolve(true)
		accept_event()
		print("喵喵喵")

func resolve(by_click: bool):
	slacking_resolved.emit(by_click)
	queue_free()

func _on_timeout():
	resolve(false)
