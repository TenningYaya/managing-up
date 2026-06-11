#tile_changer.gd
extends Control

@onready var toggle_btn = $ToggleButton
@onready var grid_container = $GridContainer

# 根据你的配置，图集 Source ID 为 0
const TARGET_SOURCE_ID = 0 

func _ready():
	grid_container.hide()
	toggle_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	toggle_btn.pressed.connect(_on_toggle_pressed)
	
	# 🌟 关键：推迟同步，等待场景加载稳定
	call_deferred("sync_current_floor_icon")
	
	# 自动生成按钮逻辑不变
	call_deferred("_generate_tile_buttons_automatically")

func sync_current_floor_icon():
	var data = FloorManager.get_current_floor_data()
	if not data.is_empty():
		var tex = FloorManager.get_current_floor_texture(data.source_id, data.atlas_coords)
		if tex:
			toggle_btn.icon = tex
			# 🌟 同步设为 50x50
			toggle_btn.custom_minimum_size = Vector2(70, 70)
			toggle_btn.expand_icon = true

func _on_tile_button_pressed(source_id: int, atlas_coord: Vector2i, new_icon: Texture2D):
	FloorManager.change_all_floors(source_id, atlas_coord)
	
	toggle_btn.icon = new_icon 
	# 🌟 点击换图后，也要确保它是 50x50
	toggle_btn.custom_minimum_size = Vector2(70, 70)
	toggle_btn.expand_icon = true
	
	grid_container.hide()
			
func _generate_tile_buttons_automatically():
	var nodes = get_tree().get_nodes_in_group("floor_tilemap")
	
	var target_tilemap = null
	for node in nodes:
		# 🌟 关键修改：检查是否是 TileMapLayer
		if node is TileMapLayer:
			target_tilemap = node
			break 
	
	if target_tilemap == null:
		push_error("错误：没找到 TileMapLayer！(注意：Godot 4.x 请使用 TileMapLayer 而非 TileMap)")
		return
		
	# 🌟 关键修改：TileMapLayer 访问 tile_set 的方式略有不同
	# 某些版本中 tile_set 属性是直接挂在 TileMapLayer 上的，
	# 如果报错找不到 tile_set，请确保你的 TileMapLayer 确实关联了 TileSet 资源
	var tile_set = target_tilemap.tile_set
		
	if not tile_set.has_source(TARGET_SOURCE_ID): return
		
	var source = tile_set.get_source(TARGET_SOURCE_ID)
	if source is TileSetAtlasSource:
		var base_texture = source.texture 
		
		# 🌟 1. 构建你指定的 17 种地板白名单
		var valid_floor_coords: Array[Vector2i] = []
		
		# 第 9 行 (y = 8)，第 1 到 8 列 (x 从 0 到 7)
		for x in range(0, 8):
			valid_floor_coords.append(Vector2i(x, 8))
			
		# 第 10 行 (y = 9)，第 1 到 8 列 (x 从 0 到 7)
		for x in range(0, 8):
			valid_floor_coords.append(Vector2i(x, 9))
			
		# 第 11 行 (y = 10)，第 1 列 (x = 0)
		valid_floor_coords.append(Vector2i(0, 10))
		
		# 🌟 2. 开始遍历图集，只放行白名单内的坐标
		for i in range(source.get_tiles_count()):
			var atlas_coord = source.get_tile_id(i) 
			
			# 【坐标拦截器】如果当前格子不在 17 种地板的白名单里，直接跳过
			if not atlas_coord in valid_floor_coords:
				continue
			
			# ✂️ 抠图：使用 AtlasTexture 动态剪切 32*32 的地砖
			var icon_tex = AtlasTexture.new()
			icon_tex.atlas = base_texture
			icon_tex.region = source.get_tile_texture_region(atlas_coord) 
			
			# 🔲 创建网格中的选择按钮
			var btn = Button.new()
			btn.icon = icon_tex
			
			# 🌟 极简 50x50 设定法
			btn.custom_minimum_size = Vector2(52, 52) # 1. 强制按钮为 50x50
			btn.expand_icon = true                    # 2. 强制图片拉伸填满这 50x50
			btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			
			# 🔗 绑定点击事件，把对应的坐标和切好的图传过去
			btn.pressed.connect(_on_tile_button_pressed.bind(TARGET_SOURCE_ID, atlas_coord, icon_tex))
			
			# 📦 塞入布局流
			grid_container.add_child(btn)

# ==========================================
# 交互与换地砖逻辑
# ==========================================
func _on_toggle_pressed():
	grid_container.visible = not grid_container.visible
