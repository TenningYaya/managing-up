# sr_visual.gd (建议作为全稀有度通用的视觉脚本)
extends Node2D

# ==========================================
# 1. 节点引用
# ==========================================
@onready var body: Sprite2D = $Body
@onready var clothes_top: Sprite2D = $ClothesTop
@onready var clothes_bottom: Sprite2D = $ClothesBottom 
@onready var hair: Sprite2D = $Hair
# 🌟 新增：饰品节点
@onready var acc_glasses: Sprite2D = $AccGlasses
@onready var acc_hat: Sprite2D = $AccHat
@onready var anim_player = $AnimationPlayer

# ==========================================
# 2. 数据存储 (在编辑器里配置)
# ==========================================
@export_group("Body Settings")
@export var body_skins: Array[Texture2D] = []

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

# 🌟 新增：饰品池配置
@export_group("Accessory Settings")
@export var glasses_pool: Array[Texture2D] = []
@export var glasses_color_counts: Array[int] = []
@export var hat_pool: Array[Texture2D] = []
@export var hat_color_counts: Array[int] = []

const ANIM_CONFIG = {
	"idle": {"y": 256, "w": 32, "f": 5},
	"walk": {"y": 0, "w": 32, "f": 8},
	"walk_down": {"y": 0, "w": 32, "f": 8},
	"walk_up": {"y": 32, "w": 32, "f": 8},
	"walk_right": {"y": 64, "w": 32, "f": 8},
	"walk_left": {"y": 96, "w": 32, "f": 8},
	"slack": {"y": 768, "w": 32, "f": 1}
}

func _process(_delta: float) -> void:
	if body == null: return
	
	var current_frame = body.frame
	
	# 同步所有节点的动画帧
	if hair.hframes > current_frame: hair.frame = current_frame
	if clothes_top.hframes > current_frame: clothes_top.frame = current_frame
	if clothes_bottom.hframes > current_frame: clothes_bottom.frame = current_frame
	
	# 🌟 同步饰品
	if acc_glasses.texture and acc_glasses.hframes > current_frame: 
		acc_glasses.frame = current_frame
	if acc_hat.texture and acc_hat.hframes > current_frame: 
		acc_hat.frame = current_frame

# 🌟 修改：加入 rarity 参数，默认是 "R"
func setup_visual(_seed: int, _style_data: Dictionary, rarity: Employee.Rarity = Employee.Rarity.R) -> void:
	# 防止没准备好
	if body == null: _ready_nodes()
	
	self.position = Vector2(55, 10)
	self.scale = Vector2(3.5, 3.5)

	# --- 随机身体 ---
	if not body_skins.is_empty():
		var body_idx = _style_data.get("body_idx", randi() % body_skins.size())
		_style_data["body_idx"] = body_idx
		body.texture = body_skins[body_idx]
	
	# --- 随机衣服 (原封不动) ---
	var has_sets = not set_pool.is_empty()
	var has_split = not top_pool.is_empty() and not bottom_pool.is_empty()
	var is_set = false
	if has_sets and has_split: is_set = _style_data.get("is_set", randf() > 0.7)
	elif has_sets: is_set = true
	_style_data["is_set"] = is_set

	if is_set and has_sets:
		clothes_bottom.texture = null
		var idx = _style_data.get("set_idx", randi() % set_pool.size())
		_style_data["set_idx"] = idx
		clothes_top.texture = set_pool[idx]
		var c_idx = _style_data.get("set_color", randi() % (set_color_counts[idx] if idx < set_color_counts.size() else 1))
		_style_data["set_color"] = c_idx
		clothes_top.set_meta("color_idx", c_idx)
		clothes_top.set_meta("total_colors", set_color_counts[idx] if idx < set_color_counts.size() else 1)
	elif has_split:
		var t_idx = _style_data.get("top_idx", randi() % top_pool.size())
		var b_idx = _style_data.get("bottom_idx", randi() % bottom_pool.size())
		_style_data["top_idx"] = t_idx
		_style_data["bottom_idx"] = b_idx
		clothes_top.texture = top_pool[t_idx]
		clothes_bottom.texture = bottom_pool[b_idx]
		
		var tc_idx = _style_data.get("top_color", randi() % (top_color_counts[t_idx] if t_idx < top_color_counts.size() else 1))
		_style_data["top_color"] = tc_idx
		clothes_top.set_meta("color_idx", tc_idx)
		clothes_top.set_meta("total_colors", top_color_counts[t_idx] if t_idx < top_color_counts.size() else 1)
		
		var bc_idx = _style_data.get("bottom_color", randi() % (bottom_color_counts[b_idx] if b_idx < bottom_color_counts.size() else 1))
		_style_data["bottom_color"] = bc_idx
		clothes_bottom.set_meta("color_idx", bc_idx)
		clothes_bottom.set_meta("total_colors", bottom_color_counts[b_idx] if b_idx < bottom_color_counts.size() else 1)

	# --- 随机头发 (原封不动) ---
	if not hair_textures.is_empty():
		var hair_idx = _style_data.get("hair_idx", randi() % hair_textures.size())
		_style_data["hair_idx"] = hair_idx
		hair.texture = hair_textures[hair_idx]
		var h_color_idx = _style_data.get("hair_color", randi() % hair_color_count)
		_style_data["hair_color"] = h_color_idx
		hair.set_meta("color_idx", h_color_idx)

# ==========================================
	# 🌟 饰品逻辑：直接用 0, 1, 2 纯数字判断，稳如老狗
	# ==========================================
	acc_glasses.texture = null
	acc_hat.texture = null
	
	# 1 代表 SR，2 代表 SSR。如果是这两者，戴眼镜/墨镜
	if (rarity == Employee.Rarity.SR or rarity == Employee.Rarity.SSR) and not glasses_pool.is_empty():
		var g_idx = _style_data.get("glasses_idx", randi() % glasses_pool.size())
		_style_data["glasses_idx"] = g_idx
		acc_glasses.texture = glasses_pool[g_idx]

		
		var g_total = glasses_color_counts[g_idx] if g_idx < glasses_color_counts.size() else 1
		var gc_idx = _style_data.get("glasses_color", randi() % g_total)
		_style_data["glasses_color"] = gc_idx
		
		acc_glasses.set_meta("color_idx", gc_idx)
		acc_glasses.set_meta("total_colors", g_total)

	# 2 代表 SSR。如果是 SSR，额外戴帽子
	if rarity == Employee.Rarity.SSR and not hat_pool.is_empty():
		var hat_idx = _style_data.get("hat_idx", randi() % hat_pool.size())
		_style_data["hat_idx"] = hat_idx
		acc_hat.texture = hat_pool[hat_idx]
		
		var h_total = hat_color_counts[hat_idx] if hat_idx < hat_color_counts.size() else 1
		var hc_idx = _style_data.get("hat_color", randi() % h_total)
		_style_data["hat_color"] = hc_idx
		
		acc_hat.set_meta("color_idx", hc_idx)
		acc_hat.set_meta("total_colors", h_total)

# 辅助函数：防止没拿到节点报错
func _ready_nodes():
	body = get_node("Body")
	clothes_top = get_node("ClothesTop")
	clothes_bottom = get_node("ClothesBottom")
	hair = get_node("Hair")
	acc_glasses = get_node("AccGlasses")
	acc_hat = get_node("AccHat")
	anim_player = get_node("AnimationPlayer")

# ==========================================
# 3. 动作与裁剪逻辑
# ==========================================
func play_action(action_name: String) -> void:
	# 1. 查字典，拿配置。如果传进来的名字不对，默认退回 idle 防报错
	if not ANIM_CONFIG.has(action_name):
		push_warning("找不到动画配置: " + action_name + "，默认播放 idle")
		action_name = "idle"
		
	var act = ANIM_CONFIG[action_name]
	
	# 2. 应用裁剪
	_apply_region(body, act, 0, 1) 
	
	if hair.texture:
		var h_idx = hair.get_meta("color_idx", 0)
		_apply_region(hair, act, h_idx, hair_color_count) 
		
	if clothes_top.texture:
		var c_idx = clothes_top.get_meta("color_idx", 0)
		var c_total = clothes_top.get_meta("total_colors", 1)
		_apply_region(clothes_top, act, c_idx, c_total) 
		
	if clothes_bottom.texture:
		var c_idx = clothes_bottom.get_meta("color_idx", 0)
		var c_total = clothes_bottom.get_meta("total_colors", 1)
		_apply_region(clothes_bottom, act, c_idx, c_total) 
		
	if acc_glasses.texture:
		var g_idx = acc_glasses.get_meta("color_idx", 0)
		var g_total = acc_glasses.get_meta("total_colors", 1)
		_apply_region(acc_glasses, act, g_idx, g_total)
		
	if acc_hat.texture:
		var hat_idx = acc_hat.get_meta("color_idx", 0)
		var hat_total = acc_hat.get_meta("total_colors", 1)
		_apply_region(acc_hat, act, hat_idx, hat_total)

	# 3. 呼叫 AnimationPlayer 播放真正的动画
	var anim_name := action_name
	if action_name.begins_with("walk_"):
		anim_name = "walk"
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
	else:
		print("【警告】AnimationPlayer 里没找到名为 '", anim_name, "' 的动画轨！")

func play_walk_direction(move_delta: Vector2) -> void:
	if absf(move_delta.x) > absf(move_delta.y):
		if move_delta.x >= 0.0:
			play_action("walk_right")
		else:
			play_action("walk_left")
	else:
		if move_delta.y >= 0.0:
			play_action("walk_down")
		else:
			play_action("walk_up")

func _apply_region(sprite: Sprite2D, act: Dictionary, color_idx: int, total_colors: int):
	sprite.region_enabled = true
	var tex_w = sprite.texture.get_width()
	var group_w = tex_w / total_colors
	# 顶部少切一格：图集每帧最上方有一行白线，下移 1px 并相应减少高度把它裁掉
	sprite.region_rect = Rect2(color_idx * group_w, act.y + 1, act.w * act.f, 31)
	sprite.hframes = act.f

# ==========================================
# 4. 生成立绘数据
# ==========================================
func generate_portrait_texture() -> Texture2D:
	if body == null: _ready_nodes()
	var rect = Rect2(0, 256, 32, 32) 
	return _get_combined_atlas_view(rect)

func _get_combined_atlas_view(rect: Rect2) -> Texture2D:
	var atlas = AtlasTexture.new()
	atlas.atlas = body.texture
	atlas.region = rect
	# 注意：这里的 Rarity 只是 Meta 数据，可以留着或动态传
	atlas.set_meta("rarity", "SR") 
	
	atlas.set_meta("hair_tex", hair.texture)
	atlas.set_meta("hair_rect", _get_item_rect(hair, {"y":256, "w":32, "h":32}, hair_color_count))
	
	atlas.set_meta("clothes_top_tex", clothes_top.texture)
	atlas.set_meta("clothes_top_rect", _get_item_rect(clothes_top, {"y":256, "w":32, "h":32}, clothes_top.get_meta("total_colors", 1)))
	
	atlas.set_meta("clothes_bottom_tex", clothes_bottom.texture)
	atlas.set_meta("clothes_bottom_rect", _get_item_rect(clothes_bottom, {"y":256, "w":32, "h":32}, clothes_bottom.get_meta("total_colors", 1)))
	
	# 🌟 传递饰品数据给 AvatarHelper 绘制
	atlas.set_meta("acc_glasses_tex", acc_glasses.texture)
	atlas.set_meta("acc_glasses_rect", _get_item_rect(acc_glasses, {"y":256, "w":32, "h":32}, acc_glasses.get_meta("total_colors", 1)))
	
	atlas.set_meta("acc_hat_tex", acc_hat.texture)
	atlas.set_meta("acc_hat_rect", _get_item_rect(acc_hat, {"y":256, "w":32, "h":32}, acc_hat.get_meta("total_colors", 1)))
	
	return atlas

# 🌟 通用的获取裁剪区域函数 (合并了原本的衣服和头发计算)
func _get_item_rect(item_node: Sprite2D, act: Dictionary, total_colors: int) -> Rect2:
	if not item_node.texture: return Rect2()
	var c_idx = item_node.get_meta("color_idx", 0)
	# 防止分母为0
	var safe_total = maxi(1, total_colors)
	var group_w = item_node.texture.get_width() / safe_total
	return Rect2(c_idx * group_w, act.y, act.w, act.h)
