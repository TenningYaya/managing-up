class_name PlaceableItemDB
extends RefCounted
# 装修物品运行时数据库:启动时自动扫描 res://data/placeable_items/ 及其子目录里的
# 所有 PlaceableItemData(.tres/.res),构建 item_id -> data 映射。
# 没有硬编码物品数组;新增 .tres 即自动入库、自动出现在装修菜单。
# 由 BuildingManager 持有(非 autoload),UI 通过 BuildingManager.get_item_db() 取用。

const ROOT_DIR := "res://data/placeable_items"

var _items := {}          # StringName -> PlaceableItemData
var _source_paths := {}   # StringName -> String(来源文件,用于重复 id 报错定位)


# 全量扫描(可重复调用 = 重新扫描)
func scan() -> int:
	_items.clear()
	_source_paths.clear()
	_scan_dir(ROOT_DIR)
	return _items.size()


func _scan_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		# 根目录不存在只警告(项目可能还没建目录);子目录打不开是异常
		push_warning("PlaceableItemDB:目录不存在或无法打开:%s" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full)
		else:
			# 导出后资源文件名可能带 .remap 后缀,裁掉再判断
			var clean := full.trim_suffix(".remap")
			if clean.get_extension() in ["tres", "res"]:
				_register_file(clean)
		entry = dir.get_next()
	dir.list_dir_end()


func _register_file(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("PlaceableItemDB:资源加载失败:%s" % path)
		return
	if not res is PlaceableItemData:
		# 目录里允许放别的资源(比如共用图标),不是物品数据就跳过
		return
	var item: PlaceableItemData = res

	var errors := item.validate()
	if not errors.is_empty():
		push_error("PlaceableItemDB:%s 数据无效,已跳过注册:\n  - %s" % [path, "\n  - ".join(errors)])
		return
	if _items.has(item.item_id):
		push_error("PlaceableItemDB:item_id 重复 \"%s\":\n  已注册: %s\n  冲突项: %s(后者被跳过)"
				% [item.item_id, _source_paths[item.item_id], path])
		return
	_items[item.item_id] = item
	_source_paths[item.item_id] = path


# ---- 查询接口(装修菜单按这些自动组织,不需要每个物品改代码) ----
func has_item(item_id: StringName) -> bool:
	return _items.has(item_id)


func get_item(item_id: StringName) -> PlaceableItemData:
	return _items.get(item_id, null)


func get_source_path(item_id: StringName) -> String:
	return _source_paths.get(item_id, "")


func get_all_ids() -> Array:
	var ids := _items.keys()
	ids.sort()
	return ids


func get_all_items() -> Array[PlaceableItemData]:
	var out: Array[PlaceableItemData] = []
	for id in get_all_ids():
		out.append(_items[id])
	return out


# 按分类取物品,按 unlock_level → item_id 排序(菜单分页直接用)
func get_by_category(category: PlaceableItemData.Category) -> Array[PlaceableItemData]:
	var out: Array[PlaceableItemData] = []
	for item in get_all_items():
		if item.category == category:
			out.append(item)
	out.sort_custom(func(a, b):
		if a.unlock_level != b.unlock_level:
			return a.unlock_level < b.unlock_level
		return String(a.item_id) < String(b.item_id))
	return out


# 按解锁等级筛选(unlock_level <= level)
func get_unlocked(level: int, category = null) -> Array[PlaceableItemData]:
	var pool: Array[PlaceableItemData] = get_all_items() if category == null else get_by_category(category)
	var out: Array[PlaceableItemData] = []
	for item in pool:
		if item.unlock_level <= level:
			out.append(item)
	return out


# 按标签筛选(物品需含 tags 中任意一个)
func filter_by_tags(tags: Array[StringName]) -> Array[PlaceableItemData]:
	var out: Array[PlaceableItemData] = []
	for item in get_all_items():
		for t in tags:
			if item.tags.has(t):
				out.append(item)
				break
	return out
