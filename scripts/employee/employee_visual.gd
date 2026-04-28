# employee_visual.gd
extends Resource
class_name EmployeeVisual

# 在编辑器里暴露出动画插槽
@export var sprite_frames: SpriteFrames

# 核心接口：别人调用这个，就能自动拿到 idle 的第一帧做头像
func get_portrait() -> Texture2D:
	if sprite_frames != null and sprite_frames.has_animation("idle"):
		# 提取 idle 动画的第 0 帧
		return sprite_frames.get_frame_texture("idle", 0)
	
	# 如果没找到，返回一个兜底的报错图或者 null
	printerr("这套动画里没有 idle！")
	return null
