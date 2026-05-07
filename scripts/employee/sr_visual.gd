# sr_visual.gd

extends Node2D

# ==========================================
# 1. 节点引用
# ==========================================
@onready var body: Sprite2D = $Body
@onready var clothes: Sprite2D = $Clothes
@onready var hair: Sprite2D = $Hair
@onready var anim_player = $AnimationPlayer

# ==========================================
# 2. 数据存储
# ==========================================
@export_group("Body Settings")
@export var body_skins: Array[Texture2D] = []

@export_group("Clothes Settings")
@export var clothes_pool: Array[Texture2D] = [] 
@export var clothes_color_counts: Array[int] = []

@export_group("Hair Settings")
@export var hair_textures: Array[Texture2D] = []
@export var hair_color_count: int = 14

func _process(_delta: float) -> void:
	# 安全检查：如果节点还没加载好，就不执行，防止报错
	if body == null or clothes == null or hair == null:
		return
		
	# 这一行代码值千金：它让衣服和头发永远贴死身体的动作 
	var current_frame = body.frame
	hair.frame = current_frame
	clothes.frame = current_frame

func setup_visual(_seed: int, _style_data: Dictionary) -> void:
	if body == null: body = get_node("Body")
	if clothes == null: clothes = get_node("Clothes")
	if hair == null: hair = get_node("Hair")
	if anim_player == null: anim_player = get_node("AnimationPlayer")
	
	self.position = Vector2(55, 10)
	self.scale = Vector2(3.5, 3.5)

	# --- 随机身体 ---
	if not body_skins.is_empty():
		var body_idx = _style_data.get("body_idx", randi() % body_skins.size())
		_style_data["body_idx"] = body_idx
		body.texture = body_skins[body_idx]
	
	# --- 随机衣服 ---
	if not clothes_pool.is_empty():
		var cloth_idx = _style_data.get("cloth_idx", randi() % clothes_pool.size())
		_style_data["cloth_idx"] = cloth_idx
		clothes.texture = clothes_pool[cloth_idx]
		
		var total_colors = clothes_color_counts[cloth_idx] if cloth_idx < clothes_color_counts.size() else 1
		var selected_color_idx = _style_data.get("cloth_color", randi() % total_colors)
		_style_data["cloth_color"] = selected_color_idx
		
		clothes.set_meta("color_idx", selected_color_idx)
		clothes.set_meta("total_colors", total_colors)

	# --- 随机头发 ---
	if not hair_textures.is_empty():
		var hair_idx = _style_data.get("hair_idx", randi() % hair_textures.size())
		_style_data["hair_idx"] = hair_idx
		hair.texture = hair_textures[hair_idx]
		
		var h_color_idx = _style_data.get("hair_color", randi() % hair_color_count)
		_style_data["hair_color"] = h_color_idx
		hair.set_meta("color_idx", h_color_idx)

	play_action("idle")


# ==========================================
# 3. 动作与裁剪逻辑
# ==========================================
func play_action(_action_name: String) -> void:
	# 强制只看第 9 行，格子宽 32，共 5 帧
	var act = {"y": 256, "w": 32, "f": 5} 
	
	# 裁剪身体
	_apply_region(body, act, 0, 1) 
	
	# 裁剪头发 (应用 14 色偏移)
	if hair.texture:
		var h_idx = hair.get_meta("color_idx", 0)
		_apply_region(hair, act, h_idx, hair_color_count) 
		
	# 裁剪衣服 (根据你拖入大图时填写的颜色组数)
	if clothes.texture:
		var c_idx = clothes.get_meta("color_idx", 0)
		var c_total = clothes.get_meta("total_colors", 1)
		_apply_region(clothes, act, c_idx, c_total) 

	# 开启节拍器
	if anim_player.has_animation("idle"):
		anim_player.play("idle")

# 万能裁剪函数
func _apply_region(sprite: Sprite2D, act: Dictionary, color_idx: int, total_colors: int):
	sprite.region_enabled = true
	var tex_w = sprite.texture.get_width()
	var group_w = tex_w / total_colors
	
	sprite.region_rect = Rect2(color_idx * group_w, act.y, act.w * act.f, 32)
	sprite.hframes = act.f

# 这个函数专门给 RecruitmentManager 调用
func generate_portrait_texture() -> Texture2D:
	# 确保节点已初始化 (处理 @onready 还没触发的情况)
	if body == null: body = get_node("Body")
	if clothes == null: clothes = get_node("Clothes")
	if hair == null: hair = get_node("Hair")

	# 定义 idle 第一帧
	var rect = Rect2(0, 256, 32, 32) 
	
	# 如果你想要最简单且美术通用的方案：
	# 我们可以返回一个 AtlasTexture，但 AtlasTexture 只能存一张图。
	# 为了“封装成一张图”，最轻量的办法是返回 Body 的 Texture，
	# 然后让 UI 的统一接口去处理层叠。
	# 或者，如果你一定要它是“一张真正的图”，就用下面的渲染逻辑：
	return _get_combined_atlas_view(rect)

func _get_combined_atlas_view(rect: Rect2) -> Texture2D:
	# 这里我们依然返回 Body 的 Atlas 作为代表，
	# 但我们将颜色索引和 Texture 信息存入 meta，方便 UI 自动读取
	var atlas = AtlasTexture.new()
	atlas.atlas = body.texture
	atlas.region = rect
	
	# 把层叠信息“藏”在 texture 里的 meta 中，这样它就像一张带数据的图
	atlas.set_meta("hair_tex", hair.texture)
	atlas.set_meta("hair_rect", _get_hair_rect({"y":256, "w":32, "h":32}))
	atlas.set_meta("clothes_tex", clothes.texture)
	atlas.set_meta("clothes_rect", _get_clothes_rect({"y":256, "w":32, "h":32}))
	
	return atlas

# 内部工具：计算头发的裁剪区域（带颜色偏移）
func _get_hair_rect(act: Dictionary) -> Rect2:
	if not hair.texture: return Rect2()
	var h_idx = hair.get_meta("color_idx", 0)
	var group_w = hair.texture.get_width() / hair_color_count
	return Rect2(h_idx * group_w, act.y, act.w, act.h)
	
# 内部工具：计算衣服的裁剪区域
func _get_clothes_rect(act: Dictionary) -> Rect2:
	if not clothes.texture: return Rect2()
	var c_idx = clothes.get_meta("color_idx", 0)
	var c_total = clothes.get_meta("total_colors", 1)
	var group_w = clothes.texture.get_width() / c_total
	return Rect2(c_idx * group_w, act.y, act.w, act.h)
