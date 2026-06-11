extends Node

const FLOOR_LAYER = 0 

func change_all_floors(new_source_id: int, new_atlas_coords: Vector2i):
	# 🌟 统一使用组查找
	var layers = get_tree().get_nodes_in_group("floor_tilemap")
	if layers.is_empty():
		push_error("FloorManager 找不到地板层！")
		return
		
	for layer in layers:
		if layer is TileMapLayer:
			# 🌟 关键点：TileMapLayer 获取格子的方法是 get_used_cells()
			var used_cells = layer.get_used_cells()
			
			for cell_pos in used_cells:
				layer.set_cell(cell_pos, new_source_id, new_atlas_coords)

func get_current_floor_data() -> Dictionary:
	var layers = get_tree().get_nodes_in_group("floor_tilemap")
	if layers.is_empty() or not layers[0] is TileMapLayer: return {}
	
	var layer = layers[0]
	var used_cells = layer.get_used_cells()
	
	if used_cells.is_empty(): return {}
	
	# 取第一个格子的数据作为“当前地板”
	var first_cell = used_cells[0]
	var source_id = layer.get_cell_source_id(first_cell)
	var atlas_coords = layer.get_cell_atlas_coords(first_cell)
	
	return {"source_id": source_id, "atlas_coords": atlas_coords}

func get_current_floor_texture(source_id: int, atlas_coords: Vector2i) -> Texture2D:
	var layers = get_tree().get_nodes_in_group("floor_tilemap")
	if layers.is_empty(): return null
	
	var tile_set = layers[0].tile_set
	var source = tile_set.get_source(source_id)
	if source is TileSetAtlasSource:
		var icon_tex = AtlasTexture.new()
		icon_tex.atlas = source.texture
		icon_tex.region = source.get_tile_texture_region(atlas_coords)
		return icon_tex
	return null
	
