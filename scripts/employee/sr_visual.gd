# sr_visual.gd
extends Node2D

# ==========================================
# 1. 节点引用
# ==========================================
@onready var body: Sprite2D = $Body
# 🌟 修改：分为上下两件
@onready var clothes_top: Sprite2D = $ClothesTop
@onready var clothes_bottom: Sprite2D = $ClothesBottom 
@onready var hair: Sprite2D = $Hair
@onready var anim_player = $AnimationPlayer

# ==========================================
# 2. 数据存储
# ==========================================
@export_group("Body Settings")
@export var body_skins: Array[Texture2D] = []

# 🌟 修改：将衣服池拆分为三个，方便你在属性面板里管理
@export_group("Clothes Settings")
@export var set_pool: Array[Texture2D] = []
@export var set_color_counts: Array[int] = []

@export var top_pool: Array[Texture2D] = []
@export var top_color_counts: Array[int] = []

@export var bottom_pool: Array[Texture2D] = []
@export var bottom_color_counts: Array[int] = []

@export_group("Hair Settings")
@export var hair_textures: Array[Texture2D] = []
@export var hair_color_count: int = 14

func _process(_delta: float) -> void:
	# 1. 原有的安全检查
	if body == null or clothes_top == null or clothes_bottom == null or hair == null:
		return
	
	# 2. 🌟 新增：关键防抖检查
	# 只有当衣服的 hframes 大于 1（说明已经成功执行了 _apply_region）时，才允许同步帧数
	# 这样在节点被销毁或初始化的瞬间，就不会因为“强行同步”而报错了
	var current_frame = body.frame
	
	if hair.hframes > current_frame:
		hair.frame = current_frame
		
	if clothes_top.hframes > current_frame:
		clothes_top.frame = current_frame
		
	if clothes_bottom.hframes > current_frame:
		clothes_bottom.frame = current_frame

func setup_visual(_seed: int, _style_data: Dictionary) -> void:
	if body == null: body = get_node("Body")
	if clothes_top == null: clothes_top = get_node("ClothesTop")
	if clothes_bottom == null: clothes_bottom = get_node("ClothesBottom")
	if hair == null: hair = get_node("Hair")
	if anim_player == null: anim_player = get_node("AnimationPlayer")
	
	self.position = Vector2(55, 10)
	self.scale = Vector2(3.5, 3.5)

	# --- 随机身体 ---
	if not body_skins.is_empty():
		var body_idx = _style_data.get("body_idx", randi() % body_skins.size())
		_style_data["body_idx"] = body_idx
		body.texture = body_skins[body_idx]
	
	# ==========================================
	# 🌟 核心修改：复杂的衣服随机逻辑
	# ==========================================
	# 抛硬币：决定穿套装(true)还是上下搭(false)
	var has_sets = not set_pool.is_empty()
	var has_split = not top_pool.is_empty() and not bottom_pool.is_empty()
	
	var is_set = false
	if has_sets and has_split:
		is_set = _style_data.get("is_set", randf() > 0.7)
	elif has_sets:
		is_set = true
	else:
		is_set = false
		
	_style_data["is_set"] = is_set

	if is_set and has_sets:
		# 方案 A: 穿套装
		clothes_bottom.texture = null # 清空下装
		var idx = _style_data.get("set_idx", randi() % set_pool.size())
		_style_data["set_idx"] = idx
		clothes_top.texture = set_pool[idx]
		
		var total_colors = set_color_counts[idx] if idx < set_color_counts.size() else 1
		var c_idx = _style_data.get("set_color", randi() % total_colors)
		_style_data["set_color"] = c_idx
		
		clothes_top.set_meta("color_idx", c_idx)
		clothes_top.set_meta("total_colors", total_colors)
		
	elif has_split:
		# 方案 B: 上装 + 下装
		var t_idx = _style_data.get("top_idx", randi() % top_pool.size())
		var b_idx = _style_data.get("bottom_idx", randi() % bottom_pool.size())
		_style_data["top_idx"] = t_idx
		_style_data["bottom_idx"] = b_idx
		
		clothes_top.texture = top_pool[t_idx]
		clothes_bottom.texture = bottom_pool[b_idx]
		
		# 上装颜色
		var t_total = top_color_counts[t_idx] if t_idx < top_color_counts.size() else 1
		var tc_idx = _style_data.get("top_color", randi() % t_total)
		_style_data["top_color"] = tc_idx
		clothes_top.set_meta("color_idx", tc_idx)
		clothes_top.set_meta("total_colors", t_total)
		
		# 下装颜色
		var b_total = bottom_color_counts[b_idx] if b_idx < bottom_color_counts.size() else 1
		var bc_idx = _style_data.get("bottom_color", randi() % b_total)
		_style_data["bottom_color"] = bc_idx
		clothes_bottom.set_meta("color_idx", bc_idx)
		clothes_bottom.set_meta("total_colors", b_total)

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
	var act = {"y": 256, "w": 32, "f": 5} 
	
	_apply_region(body, act, 0, 1) 
	
	if hair.texture:
		var h_idx = hair.get_meta("color_idx", 0)
		_apply_region(hair, act, h_idx, hair_color_count) 
		
	# 🌟 应用上装/套装裁剪
	if clothes_top.texture:
		var c_idx = clothes_top.get_meta("color_idx", 0)
		var c_total = clothes_top.get_meta("total_colors", 1)
		_apply_region(clothes_top, act, c_idx, c_total) 
		
	# 🌟 应用下装裁剪
	if clothes_bottom.texture:
		var c_idx = clothes_bottom.get_meta("color_idx", 0)
		var c_total = clothes_bottom.get_meta("total_colors", 1)
		_apply_region(clothes_bottom, act, c_idx, c_total) 

	if anim_player.has_animation("idle"):
		anim_player.play("idle")

func _apply_region(sprite: Sprite2D, act: Dictionary, color_idx: int, total_colors: int):
	sprite.region_enabled = true
	var tex_w = sprite.texture.get_width()
	var group_w = tex_w / total_colors
	
	sprite.region_rect = Rect2(color_idx * group_w, act.y, act.w * act.f, 32)
	sprite.hframes = act.f

# ==========================================
# 4. 生成立绘数据
# ==========================================
func generate_portrait_texture() -> Texture2D:
	if body == null: body = get_node("Body")
	if clothes_top == null: clothes_top = get_node("ClothesTop")
	if clothes_bottom == null: clothes_bottom = get_node("ClothesBottom")
	if hair == null: hair = get_node("Hair")

	var rect = Rect2(0, 256, 32, 32) 
	return _get_combined_atlas_view(rect)

func _get_combined_atlas_view(rect: Rect2) -> Texture2D:
	var atlas = AtlasTexture.new()
	atlas.atlas = body.texture
	atlas.region = rect
	atlas.set_meta("rarity", "SR")
	
	atlas.set_meta("hair_tex", hair.texture)
	atlas.set_meta("hair_rect", _get_hair_rect({"y":256, "w":32, "h":32}))
	
	# 🌟 保存上下装信息
	atlas.set_meta("clothes_top_tex", clothes_top.texture)
	atlas.set_meta("clothes_top_rect", _get_clothes_rect(clothes_top, {"y":256, "w":32, "h":32}))
	
	atlas.set_meta("clothes_bottom_tex", clothes_bottom.texture)
	atlas.set_meta("clothes_bottom_rect", _get_clothes_rect(clothes_bottom, {"y":256, "w":32, "h":32}))
	
	return atlas

func _get_hair_rect(act: Dictionary) -> Rect2:
	if not hair.texture: return Rect2()
	var h_idx = hair.get_meta("color_idx", 0)
	var group_w = hair.texture.get_width() / hair_color_count
	return Rect2(h_idx * group_w, act.y, act.w, act.h)
	
# 🌟 改造：传入特定的衣服节点来计算裁剪
func _get_clothes_rect(cloth_node: Sprite2D, act: Dictionary) -> Rect2:
	if not cloth_node.texture: return Rect2()
	var c_idx = cloth_node.get_meta("color_idx", 0)
	var c_total = cloth_node.get_meta("total_colors", 1)
	var group_w = cloth_node.texture.get_width() / c_total
	return Rect2(c_idx * group_w, act.y, act.w, act.h)
