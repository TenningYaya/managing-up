# avatar_helper.gd
class_name AvatarHelper
extends RefCounted

static func apply_portrait(target_node: Control, portrait_tex: Texture2D) -> void:
	if target_node == null: return
	
	if target_node is TextureRect:
		target_node.texture = portrait_tex
	elif target_node is TextureButton:
		target_node.texture_normal = portrait_tex
		
	if portrait_tex == null:
		_clear_layer(target_node, "HairLayer")
		_clear_layer(target_node, "ClothesTopLayer")
		_clear_layer(target_node, "ClothesBottomLayer")
		return

	# 🌟 注意层叠顺序：先画下装，再画上装，再画头发
	_set_or_clear_layer(target_node, portrait_tex, "clothes_bottom_tex", "clothes_bottom_rect", "ClothesBottomLayer")
	_set_or_clear_layer(target_node, portrait_tex, "clothes_top_tex", "clothes_top_rect", "ClothesTopLayer")
	_set_or_clear_layer(target_node, portrait_tex, "hair_tex", "hair_rect", "HairLayer")

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
