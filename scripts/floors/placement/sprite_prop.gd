class_name SpriteProp
extends Node2D
# 单图装修物件的通用载体:从图集(如 Office Tileset All)取一个区域显示。
# regions 配多个区域 = 同一物件的不同朝向/花色,装修菜单里只占一个选项,
# 放置/移动时用鼠标滚轮切换(见 DecorationController._cycle_variant)。
# 任何场景只要实现 get_variant_count()/set_variant()/get_variant() 三个方法,
# 就能接入滚轮切换,不限于本类。

@export var texture: Texture2D
@export var regions: Array[Rect2] = []

@onready var sprite: Sprite2D = $Sprite

var _variant := 0
var _item_data: PlaceableItemData = null
var _orientation_id: StringName = &""


func _ready() -> void:
	_apply()


func get_variant_count() -> int:
	if _item_data != null and _item_data.has_orientations():
		return _item_data.get_orientation_count()
	return maxi(1, regions.size())


func get_variant() -> int:
	return _variant


func set_variant(i: int) -> void:
	_variant = posmod(i, get_variant_count())
	if _item_data != null and _item_data.has_orientations():
		var orientation := _item_data.get_orientation_by_index(_variant)
		_orientation_id = orientation.orientation_id if orientation != null else &""
	_apply()


func configure_from_item_data(data: PlaceableItemData, orientation_id: StringName = &"") -> void:
	_item_data = data
	_orientation_id = data.normalize_orientation_id(orientation_id) if data != null else &""
	_variant = maxi(0, data.get_orientation_index(_orientation_id)) if data != null else 0
	_apply()


func get_orientation_id() -> StringName:
	return _orientation_id


func set_orientation_id(orientation_id: StringName) -> void:
	if _item_data == null:
		return
	_orientation_id = _item_data.normalize_orientation_id(orientation_id)
	_variant = maxi(0, _item_data.get_orientation_index(_orientation_id))
	_apply()


func _apply() -> void:
	if sprite == null:
		return
	if _item_data != null and _item_data.has_orientations():
		var orientation := _item_data.get_orientation(_orientation_id)
		if orientation == null:
			orientation = _item_data.get_default_orientation()
		if orientation != null:
			sprite.texture = orientation.texture
			sprite.region_enabled = true
			sprite.region_rect = Rect2(orientation.get_region())
			sprite.position = orientation.visual_offset
			sprite.z_index = orientation.z_index_offset
			return
	if texture != null:
		sprite.texture = texture
	if not regions.is_empty():
		sprite.region_enabled = true
		sprite.region_rect = regions[_variant]
