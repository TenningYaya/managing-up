# avatar_helper.gd
class_name AvatarHelper
extends RefCounted

const RARITY_BGS = {
	Employee.Rarity.R: preload("res://assets/UI/employee/raritybcg/r_bcg.png"),
	Employee.Rarity.SR: preload("res://assets/UI/employee/raritybcg/sr_bcg.png"),
	Employee.Rarity.SSR: preload("res://assets/UI/employee/raritybcg/ssr_bcg.png")
}

static func apply_portrait(target_node: Control, portrait_tex: Texture2D, emp_rarity: Employee.Rarity = Employee.Rarity.R) -> void:
	if target_node == null: return
	
	# 1. 父节点自己不再拿图，清空它，防止它挡住子节点或被挡住
	if target_node is TextureRect: target_node.texture = null
	elif target_node is TextureButton: target_node.texture_normal = null
		
	if portrait_tex == null:
		_clear_layer(target_node, "BgLayer")
		_clear_layer(target_node, "BodyLayer")
		_clear_layer(target_node, "ClothesBottomLayer")
		_clear_layer(target_node, "ClothesTopLayer")
		_clear_layer(target_node, "AccGlassesLayer") # 🌟 清空眼镜
		_clear_layer(target_node, "HairLayer")
		_clear_layer(target_node, "AccHatLayer")     # 🌟 清空帽子
		return
		
	# 2. 按照“从底到顶”的顺序严格创建/刷新图层
	
	# 第一层：背景
	var bg_tex = RARITY_BGS.get(emp_rarity)
	_set_direct_layer(target_node, bg_tex, "BgLayer")
	
	# 第二层：人体 (Body)
	_set_body_layer(target_node, portrait_tex, "BodyLayer")
		
	# 第三层：下装
	_set_or_clear_layer(target_node, portrait_tex, "clothes_bottom_tex", "clothes_bottom_rect", "ClothesBottomLayer")
	
	# 第四层：上装
	_set_or_clear_layer(target_node, portrait_tex, "clothes_top_tex", "clothes_top_rect", "ClothesTopLayer")
	
	# 🌟 第五层：眼镜 (加在衣服和头发之间，防止刘海被眼镜反向遮挡)
	_set_or_clear_layer(target_node, portrait_tex, "acc_glasses_tex", "acc_glasses_rect", "AccGlassesLayer")
	
	# 第六层：头发
	_set_or_clear_layer(target_node, portrait_tex, "hair_tex", "hair_rect", "HairLayer")
	
	# 🌟 第七层：帽子 (绝对的顶点，必须盖在头发外面)
	_set_or_clear_layer(target_node, portrait_tex, "acc_hat_tex", "acc_hat_rect", "AccHatLayer")

	# 3. 强制刷新一次所有层级的顺序，确保万无一失
	_reorder_layers(target_node)

	# ==========================================
	# 4. 终极视觉修正：把人物整体（包括新配饰）往上拽！
	# ==========================================
	var y_offset = -12 # 负数代表往上移动。
	
	# 🌟 修正：把 AccGlassesLayer 和 AccHatLayer 也塞进移动大名单里
	var character_layers = [
		"BodyLayer", 
		"ClothesBottomLayer", 
		"ClothesTopLayer", 
		"AccGlassesLayer", 
		"HairLayer", 
		"AccHatLayer"
	]
	for l_name in character_layers:
		var l = target_node.get_node_or_null(l_name)
		if l:
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
	var order = [
		"BgLayer", 
		"BodyLayer", 
		"ClothesBottomLayer", 
		"ClothesTopLayer", 
		"HairLayer", 
		"AccGlassesLayer", 
		"AccHatLayer"
	]
	
	# 🌟 核心修正：不要用固定的 index，因为有些角色没有帽子/眼镜！
	for layer_name in order:
		var layer = parent.get_node_or_null(layer_name)
		if layer:
			# -1 表示“把这个节点移动到当前所有兄弟节点的最下面（也就是视觉的最顶层）”
			# 只要我们按 order 数组的顺序把存在的节点一个个往最后塞，排出来的顺序就绝对正确！
			parent.move_child(layer, -1)

static func _create_layer_node(parent: Control, layer_name: String) -> TextureRect:
	var layer = TextureRect.new()
	layer.name = layer_name
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	return layer
