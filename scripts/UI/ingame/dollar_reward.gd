#dollar_reward.gd
extends Control

func play() -> void:
	z_index = 200
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 20.0, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.5) \
		.set_delay(0.3)
	tween.tween_callback(queue_free)
