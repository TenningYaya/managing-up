#dollar_bust_vfx.gd
extends Node2D
class_name DollarBurstVFX

@onready var texture_rect: TextureRect = $TextureRect

func play_burst_vfx() -> void:
	# 1. 🌟 固定大小，该多大就多大 (设为 0.5 左右比较精致)
	var base_scale = Vector2(0.2, 0.2)
	scale = base_scale
	modulate.a = 0.0
	
	# ======= 第一步：极速淡入 =======
	var spawn_tween = create_tween()
	spawn_tween.tween_property(self, "modulate:a", 1.0, 0.1) # 0.1s 闪现
	
	# ======= 第二步：利落的抛物线 =======
	var main_tween = create_tween().set_parallel(true)
	
	## X轴：0.5s 内平滑向右横移 (缩短总时间)
	var move_dist_x = 50
	main_tween.tween_property(self, "position:x", position.x + move_dist_x, 0.5).set_trans(Tween.TRANS_LINEAR)
	
	# Y轴：快起快落 (重点：总时长也是 0.5s)
	var jump_h = 40
	var land_h = 20
	
	# 向上冲 (0.2s) - EASE_OUT 模拟冲力减弱
	main_tween.tween_property(self, "position:y", position.y - jump_h, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 🌟 关键：衔接要快！向下掉 (0.3s) - EASE_IN 模拟重力加速
	# 用 0.3s 掉落，总共 0.2 + 0.3 = 0.5s，刚好和 X 轴同步
	main_tween.chain().tween_property(self, "position:y", position.y + land_h, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# ======= 第三步：落地后迅速离场 =======
	# 落地停留缩短到 0.5s，然后快速消失
	main_tween.chain().tween_interval(0.5)
	main_tween.chain().tween_property(self, "modulate:a", 0.0, 0.2)
	main_tween.chain().tween_callback(queue_free)
