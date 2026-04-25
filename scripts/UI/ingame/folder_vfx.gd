#folder_vfx.gd
extends TextureRect
class_name FileVFX

var gray_tex = preload("res://assets/UI/ingame/folder_grey.png")
var green_tex = preload("res://assets/UI/ingame/folder_green.png")
var blue_tex = preload("res://assets/UI/ingame/folder_blue.png")
var gold_tex = preload("res://assets/UI/ingame/folder_golden.png")

func play_vfx(grade: String) -> void:
	self.custom_minimum_size = Vector2(32, 32)
	self.size = Vector2(32, 32) # 确保实时生效
	# 1. 根据传入的等级，改变自身外观
	match grade:
		"Gold":
			texture = gold_tex
		"Blue":
			texture = blue_tex
		"Green":
			texture = green_tex
		"Gray":
			texture = gray_tex
	
	# 2. 开始 Tween 动画表演
	var tween = create_tween()
	
	# 设置动画同时进行 (位置上移的同时变透明)
	tween.set_parallel(true) 
	
	# 目标位置：在当前 position 的基础上，再往上飘 60 个像素
	var target_pos = position + Vector2(0, -60)
	
	# 动画 1：向上飘动，耗时 1.0 秒，使用“减速”曲线让它看起来有阻力
	tween.tween_property(self, "position", target_pos, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# 动画 2：渐隐 (Alpha 变成 0)，耗时 1.0 秒
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	
	# 3. 动画结束后的清理工作
	# 当整套 Tween 跑完后，自动销毁这个节点
	tween.chain().tween_callback(queue_free)
