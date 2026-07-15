class_name OfficeTilesetManifest
extends Resource
# Persistent audit manifest for atlas detection and human review.

@export var source_texture_path: String = ""
@export var source_texture_hash: String = ""
@export var source_image_size: Vector2i = Vector2i.ZERO
@export var base_tile_size: Vector2i = Vector2i(32, 32)
@export_range(0, 255) var alpha_threshold: int = 8
@export var minimum_visible_pixels_per_tile: int = 2
@export var component_merge_distance_px: int = 4
@export var shadow_merge_distance_px: int = 8
@export var maximum_component_gap_tiles: int = 1
@export var include_detached_shadows: bool = true
@export var maximum_auto_region_size_tiles: Vector2i = Vector2i(8, 8)
@export var crop_padding_px: int = 1
@export var ground_contact_scan_height_px: int = 8
@export var ignore_low_alpha_for_ground: bool = true
@export_range(0, 255) var ground_alpha_threshold: int = 64

@export var candidates: Array[CandidateAssetData] = []
@export var ignored_candidate_ids: Array[StringName] = []
@export var manual_merges: Array[PackedStringArray] = []
@export var manual_splits: Array[StringName] = []
@export var furniture_groups: Dictionary = {}
@export var direction_assignments: Dictionary = {}
@export var generated_item_ids: Array[StringName] = []


func find_candidate(candidate_id: StringName) -> CandidateAssetData:
	for c in candidates:
		if c != null and c.candidate_id == candidate_id:
			return c
	return null


func approved_candidates() -> Array[CandidateAssetData]:
	var out: Array[CandidateAssetData] = []
	for c in candidates:
		if c != null and c.is_approved():
			out.append(c)
	return out
