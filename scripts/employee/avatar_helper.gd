# avatar_helper.gd
class_name AvatarHelper
extends RefCounted

# 万能装配接口，传进来的可以是一个 TextureRect，也可以是 TextureButton
static func apply_portrait(target_node: Control, portrait_tex: Texture2D) -> void:
	if target_node == null: return
	
	# 1. 赋予身体底图 (兼容 Rect 和 Button 两种类型)
	if target_node is TextureRect:
		target_node.texture = portrait_tex
	elif target_node is TextureButton:
		target_node.texture_normal = portrait_tex
		
	# 如果连底图都没有，直接清空所有图层并退出
	if portrait_tex == null:
		_clear_layer(target_node, "HairLayer")
		_clear_layer(target_node, "ClothesLayer")
		return

	# 2. 自动化层叠处理
	_set_or_clear_layer(target_node, portrait_tex, "hair_tex", "hair_rect", "HairLayer")
	_set_or_clear_layer(target_node, portrait_tex, "clothes_tex", "clothes_rect", "ClothesLayer")

# 内部函数：处理单层
static func _set_or_clear_layer(parent: Control, main_tex: Texture2D, tex_key: String, rect_key: String, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	
	if main_tex.has_meta(tex_key):
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

# 内部函数：清空图层
static func _clear_layer(parent: Control, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	if layer:
		layer.texture = null
