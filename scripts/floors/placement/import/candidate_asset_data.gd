class_name CandidateAssetData
extends Resource
# Detected atlas candidate. This is review data, not a final furniture item.

enum ReviewState { PENDING, APPROVED, IGNORED, NEEDS_RESCAN }

@export var candidate_id: StringName = &""
@export var source_texture_path: String = ""
@export var source_region: Rect2i = Rect2i()
@export var tight_visual_bounds: Rect2i = Rect2i()
@export var pixel_size: Vector2i = Vector2i.ZERO
@export var tile_span: Vector2i = Vector2i.ZERO
@export var touched_tile_cells: Array[Vector2i] = []
@export var connected_component_ids: Array[int] = []
@export var detected_shadow_components: Array[int] = []
@export_range(0.0, 1.0, 0.01) var confidence_score: float = 0.0
@export var needs_manual_review: bool = true
@export var review_state: ReviewState = ReviewState.PENDING

@export_group("Suggestions")
@export var suggested_category: StringName = &""
@export var suggested_group_id: StringName = &""
@export var suggested_orientation: StringName = &""
@export var suggested_item_id: StringName = &""
@export var suggested_ground_footprint: Vector2i = Vector2i.ZERO
@export var suggested_placement_anchor: Vector2 = Vector2.ZERO
@export var includes_shadow: bool = false

@export_group("Manual Corrections")
@export var manual_region: Rect2i = Rect2i()
@export var manual_group_id: StringName = &""
@export var manual_orientation: StringName = &""
@export var manual_display_name: String = ""
@export var manual_category: int = -1
@export var manual_ground_footprint: Vector2i = Vector2i.ZERO
@export var manual_placement_anchor: Vector2 = Vector2.ZERO
@export var manual_interaction_points: Array[Vector2] = []


func get_effective_region() -> Rect2i:
	if manual_region.size.x > 0 and manual_region.size.y > 0:
		return manual_region
	return source_region


func is_approved() -> bool:
	return review_state == ReviewState.APPROVED
