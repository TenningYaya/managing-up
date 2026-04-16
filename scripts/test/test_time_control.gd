#test_time_control.gd
extends Control

# 获取所有的倍速按钮
@onready var btn_1x: Button = $VBoxContainer/"1x"
@onready var btn_3x: Button = $VBoxContainer/"3x"
@onready var btn_5x: Button = $VBoxContainer/"5x"
@onready var btn_10x: Button = $VBoxContainer/"10x"
@onready var btn_100x: Button = $VBoxContainer/BetterNotDoIt # 假设这个是你的 100x

func _ready() -> void:
	# 批量连接按钮信号
	btn_1x.pressed.connect(func(): _change_speed(1.0))
	btn_3x.pressed.connect(func(): _change_speed(3.0))
	btn_5x.pressed.connect(func(): _change_speed(5.0))
	btn_10x.pressed.connect(func(): _change_speed(10.0))
	
	# 设置 100x 的文本并连接
	btn_100x.text = "100x (狂暴测试)"
	btn_100x.pressed.connect(func(): _change_speed(100.0))
	
	print("测试倍速控制组件就绪，默认速度: 1.0x")

func _change_speed(multiplier: float) -> void:
	# 核心逻辑：修改引擎时间缩放
	Engine.time_scale = multiplier
	
	# UI 反馈，方便在控制台确认
	print(">>> 游戏速度调整为: ", multiplier, "x")
	
	# 小贴士：如果倍速太高，建议把一些不重要的 print 关掉，
	# 否则控制台 IO 会导致游戏本体卡顿。
	if multiplier > 20.0:
		print("警告：超高倍速下，进度条显示可能会出现跳帧现象。")
