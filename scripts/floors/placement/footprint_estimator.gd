class_name FootprintEstimator
extends RefCounted
# 占地自动估算:把一个 Scene/节点的"有效占地像素边界"换算成网格占地。
# 换算全部经由传入的 TileMapLayer(map_to_local/local_to_map/to_global/to_local),
# 不读 tile_size、不出现任何格径魔法数字。
#
# 估算优先级(高 → 低):
#   1. footprint_override(由调用方/PlaceableItemData 处理,不进本类)
#   2. PlacementBounds 专用占地标记节点(Control/ReferenceRect,所见即占地)
#   3. CollisionShape2D / CollisionPolygon2D 有效边界
#   4. 导航阻挡边界(NavigationObstacle2D)
#   5. Sprite2D / AnimatedSprite2D 可见内容边界(可读像素时裁掉透明留白)
#   6. 所有可见 CanvasItem 组合边界(TextureRect 等 UI 素材)
#   7. 纹理完整尺寸(5/6 的兜底,单图素材)
# 自动结果只是"建议",正式数据须人工确认(footprint_override)。
#
# 返回字典:
#   pixel_bounds: Rect2       世界坐标的有效边界
#   footprint: Vector2i       建议占地(格)
#   source: String            采用的检测来源(上面 2~7 之一)
#   placement_offset: Vector2 场景原点 → 边界左上角(放置对齐用)
#   transparent_risk: bool    素材含明显透明留白(可读像素时判定)
#   cells_covered: Rect2i     边界覆盖的格范围(以 tilemap map 坐标)


# 测量一个已在场景树内、布局稳定的节点
static func estimate_node(node: Node, tilemap: TileMapLayer) -> Dictionary:
	var source := ""
	var bounds := Rect2()
	var transparent_risk := false

	# 2) 专用占地标记
	var pb := node.find_child("PlacementBounds", true, false)
	if pb is Control and pb.size != Vector2.ZERO:
		bounds = pb.get_global_transform() * Rect2(Vector2.ZERO, pb.size)
		source = "PlacementBounds 标记节点"

	# 3) 碰撞体边界
	if source.is_empty():
		bounds = _collision_bounds(node)
		if bounds.size != Vector2.ZERO:
			source = "CollisionShape 边界"

	# 4) 导航阻挡
	if source.is_empty():
		bounds = _nav_obstacle_bounds(node)
		if bounds.size != Vector2.ZERO:
			source = "导航阻挡边界"

	# 5) 精灵可见内容
	if source.is_empty():
		var r := _sprite_bounds(node)
		if r.size != Vector2.ZERO:
			bounds = r.grow(0)
			source = "Sprite 可见内容"
			transparent_risk = _had_transparent_trim

	# 6) 全部可见 CanvasItem
	if source.is_empty():
		bounds = _canvas_item_bounds(node)
		if bounds.size != Vector2.ZERO:
			source = "可见 CanvasItem 组合边界"

	if bounds.size == Vector2.ZERO:
		return {"pixel_bounds": Rect2(), "footprint": Vector2i.ZERO, "source": "无法检测",
				"placement_offset": Vector2.ZERO, "transparent_risk": false, "cells_covered": Rect2i()}

	# 建议占地 = ceil(有效像素 / 世界格径),与测量位置无关;
	# 世界格径从 TileMapLayer 推导(相邻格中心的世界距离),不读 tile_size 常量
	var cell_world := (tilemap.to_global(tilemap.map_to_local(Vector2i.ONE))
			- tilemap.to_global(tilemap.map_to_local(Vector2i.ZERO))).abs()
	var fp := Vector2i(
			ceili(bounds.size.x / cell_world.x),
			ceili(bounds.size.y / cell_world.y))
	# 实际覆盖到的格范围(与位置有关,供已放置物件的调试标注用)
	var c0 := tilemap.local_to_map(tilemap.to_local(bounds.position + Vector2.ONE))
	var c1 := tilemap.local_to_map(tilemap.to_local(bounds.end - Vector2.ONE))

	var origin := Vector2.ZERO
	if node is Node2D or node is Control:
		origin = node.global_position
	return {
		"pixel_bounds": bounds,
		"footprint": fp,
		"source": source,
		"placement_offset": bounds.position - origin,
		"transparent_risk": transparent_risk,
		"cells_covered": Rect2i(c0, c1 - c0 + Vector2i.ONE),
	}


# 测量一个 PackedScene:临时实例化到 host 下(远离可视区),等两帧布局稳定后测量再销毁。
# 实例会被"假人化":移出所有 group、禁鼠标,避免污染存档/交互。必须 await 调用
static func estimate_scene(scene: PackedScene, tilemap: TileMapLayer, host: Node) -> Dictionary:
	if scene == null or host == null or not host.is_inside_tree():
		return {"pixel_bounds": Rect2(), "footprint": Vector2i.ZERO, "source": "参数无效",
				"placement_offset": Vector2.ZERO, "transparent_risk": false, "cells_covered": Rect2i()}
	# ⚠️ 隐藏节点下容器不排版(比如当前楼层不是 2F 时它整棵树 visible=false),
	# 所以假人挂在场景树根下的临时节点上(永远可见),摆到视野外测量
	var temp_host := Node2D.new()
	temp_host.name = "FootprintProbe"
	host.get_tree().root.add_child(temp_host)
	var inst := scene.instantiate()
	temp_host.add_child(inst)
	_neutralize(inst)  # 入树后再假人化:group 是各脚本 _ready 里加的,入树前移除是空操作
	if inst is Node2D or inst is Control:
		inst.global_position = host.get_viewport().get_visible_rect().size + Vector2(0, 5000)
	# 嵌套容器(CenterContainer→GridContainer)排版逐层级联:至少等 4 帧,
	# 之后连续两帧边界不变即收工(上限 12 帧)
	var result := {}
	var prev := Rect2(0, 0, -1, -1)
	for i in 12:
		await host.get_tree().process_frame
		result = estimate_node(inst, tilemap)
		if i >= 3 and result.pixel_bounds == prev:
			break
		prev = result.pixel_bounds
	temp_host.queue_free()
	return result


# 测量假人不参与任何游戏逻辑:移出所有 group(存档/座位查找都靠 group)、禁鼠标。
# 注意不要动 process 状态:容器布局依赖正常的帧循环
static func _neutralize(node: Node) -> void:
	for g in node.get_groups():
		if not String(g).begins_with("_"):  # 引擎内部 group 不动
			node.remove_from_group(g)
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_neutralize(c)


# ---- 各优先级的边界收集 ----
static func _collision_bounds(node: Node) -> Rect2:
	var acc := Rect2()
	var has := false
	for shape_node in _find_all(node, ["CollisionShape2D", "CollisionPolygon2D"]):
		if shape_node is CanvasItem and not shape_node.visible:
			continue
		var r := Rect2()
		if shape_node is CollisionShape2D and shape_node.shape != null:
			var local: Rect2 = shape_node.shape.get_rect()
			r = shape_node.get_global_transform() * local
		elif shape_node is CollisionPolygon2D and shape_node.polygon.size() > 0:
			var pts: PackedVector2Array = shape_node.polygon
			var local := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				local = local.expand(p)
			r = shape_node.get_global_transform() * local
		if r.size != Vector2.ZERO:
			acc = r if not has else acc.merge(r)
			has = true
	return acc if has else Rect2()


static func _nav_obstacle_bounds(node: Node) -> Rect2:
	var acc := Rect2()
	var has := false
	for ob in _find_all(node, ["NavigationObstacle2D"]):
		var pts: PackedVector2Array = ob.vertices
		if pts.is_empty():
			continue
		var local := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			local = local.expand(p)
		var r: Rect2 = ob.get_global_transform() * local
		acc = r if not has else acc.merge(r)
		has = true
	return acc if has else Rect2()


# 记录最近一次 _sprite_bounds 是否发生过透明裁边(供 estimate_node 读取)
static var _had_transparent_trim := false

static func _sprite_bounds(node: Node) -> Rect2:
	_had_transparent_trim = false
	var acc := Rect2()
	var has := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not n.visible:
			continue
		for c in n.get_children():
			stack.push_back(c)
		var tex: Texture2D = null
		var local := Rect2()
		var region := Rect2()  # region_enabled 的精灵:尺寸/透明裁剪都按区域算
		if n is Sprite2D and n.texture != null:
			tex = n.texture
			var sz: Vector2
			if n.region_enabled and n.region_rect.size != Vector2.ZERO:
				region = n.region_rect
				sz = region.size
			else:
				sz = tex.get_size()
			local = Rect2(-sz / 2.0 if n.centered else Vector2.ZERO, sz)
			local.position += n.offset
		elif n is AnimatedSprite2D and n.sprite_frames != null:
			var anim: StringName = n.animation
			if n.sprite_frames.has_animation(anim) and n.sprite_frames.get_frame_count(anim) > 0:
				tex = n.sprite_frames.get_frame_texture(anim, 0)
				if tex:
					var sz: Vector2 = tex.get_size()
					local = Rect2(-sz / 2.0 if n.centered else Vector2.ZERO, sz)
					local.position += n.offset
		if tex == null:
			continue
		# 可读像素时裁掉透明留白(不能只按整张 PNG 算)
		local = _trim_transparent(tex, local, region)
		var r: Rect2 = n.get_global_transform() * local
		if r.size != Vector2.ZERO:
			acc = r if not has else acc.merge(r)
			has = true
	return acc if has else Rect2()


# 用 Image.get_used_rect 裁掉纹理四周的透明像素;不可读(压缩后)则原样返回。
# region 非空 = 只看图集里这一块(区域精灵)
static func _trim_transparent(tex: Texture2D, local: Rect2, region := Rect2()) -> Rect2:
	var img := tex.get_image()
	if img == null:
		return local
	if img.is_compressed():
		if img.decompress() != OK:
			return local
	if region.size != Vector2.ZERO:
		img = img.get_region(Rect2i(region))
		if img == null:
			return local
	var used := img.get_used_rect()
	if used.size == Vector2i.ZERO or used.size == img.get_size():
		return local
	_had_transparent_trim = true
	var scale := local.size / Vector2(img.get_size())
	return Rect2(local.position + Vector2(used.position) * scale, Vector2(used.size) * scale)


static func _canvas_item_bounds(node: Node) -> Rect2:
	var acc := Rect2()
	var has := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not n.visible:
			continue
		for c in n.get_children():
			stack.push_back(c)
		var r := Rect2()
		if n is TextureRect and n.texture != null:
			r = n.get_global_transform() * Rect2(Vector2.ZERO, n.size)
		elif n is NinePatchRect and n.texture != null:
			r = n.get_global_transform() * Rect2(Vector2.ZERO, n.size)
		elif n is Sprite2D and n.texture != null:
			var sz: Vector2 = n.region_rect.size \
					if (n.region_enabled and n.region_rect.size != Vector2.ZERO) \
					else n.texture.get_size()
			var local := Rect2(-sz / 2.0 if n.centered else Vector2.ZERO, sz)
			local.position += n.offset
			r = n.get_global_transform() * local
		if r.size != Vector2.ZERO:
			acc = r if not has else acc.merge(r)
			has = true
	return acc if has else Rect2()


static func _find_all(node: Node, type_names: Array) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for t in type_names:
			if n.is_class(t):
				out.append(n)
				break
		for c in n.get_children():
			stack.push_back(c)
	return out
