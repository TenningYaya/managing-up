# ssr_visual.gd
extends Node2D

# ==========================================
# 1. 节点引用
# ==========================================
@onready var sprite: Sprite2D = $Sprite
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# ==========================================
# 2. 数据存储
# ==========================================
@export_group("SSR Settings")
# 在编辑器中将准备好的 12 张 SSR 完整精灵图拖入此数组
@export var ssr_skins: Array[Texture2D] = [] 

func setup_visual(_seed: int, _style_data: Dictionary) -> void:
	# 确保节点在初始化前已被正确引用（参考 sr_visual 的唤醒逻辑）
	if sprite == null: sprite = get_node("Sprite")
	if anim_player == null: anim_player = get_node("AnimationPlayer")
	
	# 保持与 sr_visual 一致的缩放和偏移，确保在工位上的位置统一
	self.position = Vector2(55, 10)
	self.scale = Vector2(3.5, 3.5)

	# 随机选择一种 SSR 形象
	if not ssr_skins.is_empty():
		sprite.texture = ssr_skins.pick_random()
	
	# 默认播放待机动画
	play_action("idle")

# ==========================================
# 3. 动作与裁剪逻辑
# ==========================================
func play_action(_action_name: String) -> void:
	# 根据你提供的图片 (Office_Boss_Idle.png)，该图为单行 6 帧。
	# 假设每帧宽高为 32x32
	var act = {"y": 0, "w": 32, "h": 32, "f": 6} 
	
	# 应用裁剪区域
	sprite.region_enabled = true
	# 这里的 y 坐标设为 0，因为 SSR 图是独立的完整形象，不需要像 SR 那样在合集图中偏移
	sprite.region_rect = Rect2(0, act.y, act.w * act.f, act.h)
	sprite.hframes = act.f

	# 播放动画轨道
	if anim_player.has_animation("idle"):
		anim_player.play("idle")

# 这个函数专门给 RecruitmentManager 调用，用于生成简历上的头像
func generate_portrait_texture() -> Texture2D:
	if sprite == null: sprite = get_node("Sprite")
	
	# 获取第一帧作为静态头像
	var atlas = AtlasTexture.new()
	atlas.atlas = sprite.texture
	# 截取第一帧 (0, 0, 32, 32)
	atlas.region = Rect2(0, 0, 32, 32) 
	
	return atlas
