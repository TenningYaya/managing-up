# avatar_helper.gd
class_name AvatarHelper
extends RefCounted

const RARITY_BGS = {
	"R": preload("res://assets/UI/employee/raritybcg/r_bcg.png"),
	"SR": preload("res://assets/UI/employee/raritybcg/sr_bcg.png"),
	"SSR": preload("res://assets/UI/employee/raritybcg/ssr_bcg.png")
}

static func apply_portrait(target_node: Control, portrait_tex: Texture2D) -> void:
	if target_node == null: return
	
# 🌟 改动 A：父节点自己不再拿图，清空它，防止它挡住子节点或被挡住
	if target_node is TextureRect: target_node.texture = null
	elif target_node is TextureButton: target_node.texture_normal = null
		
	if portrait_tex == null:
		_clear_layer(target_node, "BgLayer")
		_clear_layer(target_node, "BodyLayer")
		_clear_layer(target_node, "HairLayer")
		_clear_layer(target_node, "ClothesTopLayer")
		_clear_layer(target_node, "ClothesBottomLayer")
		return
		
	# 🌟 2. 按照“从底到顶”的顺序严格创建/刷新图层
	
	# 第一层：背景
	if portrait_tex.has_meta("rarity"):
		var r_key = portrait_tex.get_meta("rarity")
		var bg_tex = RARITY_BGS.get(r_key)
		_set_direct_layer(target_node, bg_tex, "BgLayer")
	
	# 第二层：人体 (Body)
	# 这里的 portrait_tex 本身就是 AtlasTexture(Body)，我们直接传进去
	_set_body_layer(target_node, portrait_tex, "BodyLayer")
		
	# 第三层：下装
	_set_or_clear_layer(target_node, portrait_tex, "clothes_bottom_tex", "clothes_bottom_rect", "ClothesBottomLayer")
	# 第四层：上装
	_set_or_clear_layer(target_node, portrait_tex, "clothes_top_tex", "clothes_top_rect", "ClothesTopLayer")
	# 第五层：头发
	_set_or_clear_layer(target_node, portrait_tex, "hair_tex", "hair_rect", "HairLayer")

	# 🌟 3. 强制刷新一次所有层级的顺序，确保万无一失
	_reorder_layers(target_node)

	# ==========================================
	# 🌟 4. 终极视觉修正：把人物整体往上拽！
	# ==========================================
	var y_offset = -12 # 负数代表往上移动。你可以自己调这个数值，直到看着舒服为止（比如 -8, -15）
	
	var character_layers = ["BodyLayer", "ClothesBottomLayer", "ClothesTopLayer", "HairLayer"]
	for l_name in character_layers:
		var l = target_node.get_node_or_null(l_name)
		if l:
			# 强行改变 Y 轴坐标，把人往上提
			l.position.y = y_offset

static func _set_or_clear_layer(parent: Control, main_tex: Texture2D, tex_key: String, rect_key: String, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	
	if main_tex.has_meta(tex_key) and main_tex.get_meta(tex_key) != null:
		if not layer:
			layer = TextureRect.new()
			layer.name = layer_name
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(layer)
		
		var atlas = AtlasTexture.new()
		atlas.atlas = main_tex.get_meta(tex_key)
		atlas.region = main_tex.get_meta(rect_key)
		layer.texture = atlas
	elif layer:
		layer.texture = null

static func _clear_layer(parent: Control, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	if layer:
		layer.texture = null

static func _set_direct_layer(parent: Control, tex: Texture2D, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	if tex:
		if not layer:
			# 🌟 调用工厂函数创建节点
			layer = _create_layer_node(parent, layer_name)
		layer.texture = tex
	elif layer:
		layer.texture = null

static func _set_body_layer(parent: Control, tex: Texture2D, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	if tex:
		if not layer:
			layer = TextureRect.new()
			layer.name = layer_name
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(layer)
		layer.texture = tex
	elif layer:
		layer.texture = null

# 终极保底：强制排序函数
static func _reorder_layers(parent: Control):
	# 定义你想要的从底到顶的顺序
	var order = ["BgLayer", "BodyLayer", "ClothesBottomLayer", "ClothesTopLayer", "HairLayer"]
	for i in range(order.size()):
		var layer = parent.get_node_or_null(order[i])
		if layer:
			parent.move_child(layer, i) # 强制调整它在节点树里的位置

static func _create_layer_node(parent: Control, layer_name: String) -> TextureRect:
	var layer = TextureRect.new()
	layer.name = layer_name
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	return layer
