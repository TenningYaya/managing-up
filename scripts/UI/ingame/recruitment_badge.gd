# recruitment_badge.gd
extends TextureRect

func _ready():
	# 1. 隐藏，等待信号
	hide()
	
	# 2. 监听招聘系统的更新信号
	RecruitmentManager.new_resumes_arrived.connect(_on_resumes_updated)
	
	# 3. 开启浮动动画
	_play_float_animation()
	
	# 初始检查
	_on_resumes_updated()

func _on_resumes_updated():
	# 强制打印调试信息，看看它到底为什么觉得还有简历
	var count = RecruitmentManager.get_unread_count()
	
	if count > 0:
		show()
	else:
		hide()
		
func _play_float_animation():
	var tween = create_tween().set_loops()
	# 相对位置上下移动 5 像素，持续 0.8 秒，平滑曲线
	tween.tween_property(self, "position:y", position.y - 5, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", position.y, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
