class_name PlaceableOrientationData
extends Resource
# A single real sprite orientation for one logical placeable item.
# Pixel furniture should switch between these entries instead of rotating nodes.

enum Direction { NONE, NORTH, EAST, SOUTH, WEST, HORIZONTAL, VERTICAL, LEFT, RIGHT }

@export var orientation_id: StringName = &""
@export var direction: Direction = Direction.NONE
@export var texture: Texture2D
@export var atlas_region: Rect2i = Rect2i()
@export var atlas_coordinates: Vector2i = Vector2i.ZERO
@export var atlas_size_in_tiles: Vector2i = Vector2i.ONE
@export var visual_size: Vector2 = Vector2.ZERO
@export var visual_offset: Vector2 = Vector2.ZERO
@export var placement_anchor: Vector2 = Vector2.ZERO
@export var footprint: Vector2i = Vector2i.ONE
@export var occupied_cells: Array[Vector2i] = []
@export var blocked_cells: Array[Vector2i] = []
@export var interaction_points: Array[Vector2] = []
@export var entrance_cells: Array[Vector2i] = []
@export var z_index_offset: int = 0
@export var preview_offset: Vector2 = Vector2.ZERO
@export var is_default: bool = false


func get_region() -> Rect2i:
	if atlas_region.size.x > 0 and atlas_region.size.y > 0:
		return atlas_region
	return Rect2i(atlas_coordinates * 32, atlas_size_in_tiles * 32)


func get_visual_size() -> Vector2:
	if visual_size != Vector2.ZERO:
		return visual_size
	return Vector2(get_region().size)


func get_footprint() -> Vector2i:
	if footprint.x > 0 and footprint.y > 0:
		return footprint
	return Vector2i.ONE


func get_occupied_cells() -> Array[Vector2i]:
	if not occupied_cells.is_empty():
		return occupied_cells
	var out: Array[Vector2i] = []
	var fp := get_footprint()
	for y in fp.y:
		for x in fp.x:
			out.append(Vector2i(x, y))
	return out


func validate() -> Array[String]:
	var errors: Array[String] = []
	if String(orientation_id).is_empty():
		errors.append("orientation_id 为空")
	if texture == null:
		errors.append("%s texture 丢失" % orientation_id)
	var region := get_region()
	if region.size.x <= 0 or region.size.y <= 0:
		errors.append("%s atlas_region 无效:%s" % [orientation_id, region])
	var fp := get_footprint()
	if fp.x <= 0 or fp.y <= 0:
		errors.append("%s footprint 无效:%s" % [orientation_id, fp])
	return errors
