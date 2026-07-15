@tool
extends VBoxContainer

var editor_plugin: EditorPlugin
var _manifest: OfficeTilesetManifest
var _index := 0

var _path_edit: LineEdit
var _status: Label
var _preview: TextureRect
var _candidate_list: ItemList
var _region_spin: Array[SpinBox] = []
var _group_edit: LineEdit
var _orientation_edit: LineEdit
var _name_edit: LineEdit
var _category_spin: SpinBox
var _footprint_x: SpinBox
var _footprint_y: SpinBox
var _interaction_edit: LineEdit


func _ready() -> void:
	custom_minimum_size = Vector2(360, 520)
	_build_ui()


func _build_ui() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	_path_edit = LineEdit.new()
	_path_edit.text = "res://data/office_tileset_import/office_tileset_manifest.tres"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_path_edit)
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_load_manifest)
	row.add_child(load_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_candidate_list = ItemList.new()
	_candidate_list.select_mode = ItemList.SELECT_MULTI
	_candidate_list.custom_minimum_size = Vector2(320, 140)
	_candidate_list.item_selected.connect(func(i): _select_candidate(i))
	add_child(_candidate_list)

	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(256, 180)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_preview)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	for label in ["Region X", "Region Y", "Region W", "Region H"]:
		grid.add_child(Label.new())
		grid.get_child(grid.get_child_count() - 1).text = label
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 4096
		spin.step = 1
		spin.value_changed.connect(func(_v): _apply_region_from_ui())
		_region_spin.append(spin)
		grid.add_child(spin)

	_group_edit = _add_line_field(grid, "Group")
	_orientation_edit = _add_line_field(grid, "Orientation")
	_name_edit = _add_line_field(grid, "中文名")
	_category_spin = _add_spin_field(grid, "Category", -1, 32)
	_footprint_x = _add_spin_field(grid, "Footprint X", 0, 16)
	_footprint_y = _add_spin_field(grid, "Footprint Y", 0, 16)
	_interaction_edit = _add_line_field(grid, "Interaction pts")
	_interaction_edit.placeholder_text = "x,y; x,y"

	var actions := HBoxContainer.new()
	add_child(actions)
	for pair in [
		["Apply", _apply_manual_fields],
		["Approve", _approve_current],
		["Ignore", _ignore_current],
		["Shadow", _mark_shadow_current],
		["Save", _save_manifest],
	]:
		var btn := Button.new()
		btn.text = pair[0]
		btn.pressed.connect(pair[1])
		actions.add_child(btn)

	var structure_actions := HBoxContainer.new()
	add_child(structure_actions)
	for pair in [
		["Merge Selected", _merge_selected],
		["Split V", _split_current_vertical],
		["Split H", _split_current_horizontal],
	]:
		var btn := Button.new()
		btn.text = pair[0]
		btn.pressed.connect(pair[1])
		structure_actions.add_child(btn)


func _add_line_field(parent: GridContainer, label: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit


func _add_spin_field(parent: GridContainer, label: String, min_v: int, max_v: int) -> SpinBox:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	parent.add_child(spin)
	return spin


func _load_manifest() -> void:
	var res := ResourceLoader.load(_path_edit.text)
	if res == null or not res is OfficeTilesetManifest:
		_status.text = "Manifest 加载失败；如果当前 .tres 是自动扫描快照，请先用 Godot 扫描器重新保存为 Resource。"
		return
	_manifest = res
	_candidate_list.clear()
	for c in _manifest.candidates:
		if c == null:
			continue
		_candidate_list.add_item("%s  %s  %.2f" % [c.candidate_id, CandidateAssetData.ReviewState.keys()[c.review_state], c.confidence_score])
	_status.text = "已加载 %d 个 candidates" % _manifest.candidates.size()
	if _manifest.candidates.size() > 0:
		_select_candidate(0)


func _select_candidate(i: int) -> void:
	if _manifest == null or i < 0 or i >= _manifest.candidates.size():
		return
	_index = i
	var c := _manifest.candidates[i]
	var r := c.get_effective_region()
	_region_spin[0].value = r.position.x
	_region_spin[1].value = r.position.y
	_region_spin[2].value = r.size.x
	_region_spin[3].value = r.size.y
	_group_edit.text = String(c.manual_group_id if not String(c.manual_group_id).is_empty() else c.suggested_group_id)
	_orientation_edit.text = String(c.manual_orientation if not String(c.manual_orientation).is_empty() else c.suggested_orientation)
	_name_edit.text = c.manual_display_name
	_category_spin.value = c.manual_category
	var fp := c.manual_ground_footprint if c.manual_ground_footprint != Vector2i.ZERO else c.suggested_ground_footprint
	_footprint_x.value = fp.x
	_footprint_y.value = fp.y
	_interaction_edit.text = _format_points(c.manual_interaction_points)
	_update_preview(c)


func _update_preview(c: CandidateAssetData) -> void:
	var tex := ResourceLoader.load(c.source_texture_path) as Texture2D
	if tex == null:
		_preview.texture = null
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(c.get_effective_region())
	_preview.texture = atlas


func _current() -> CandidateAssetData:
	if _manifest == null or _index < 0 or _index >= _manifest.candidates.size():
		return null
	return _manifest.candidates[_index]


func _apply_region_from_ui() -> void:
	var c := _current()
	if c == null:
		return
	var r := Rect2i(
		int(_region_spin[0].value),
		int(_region_spin[1].value),
		int(_region_spin[2].value),
		int(_region_spin[3].value)
	)
	_set_candidate_property(c, "manual_region", r, "Adjust candidate region")
	_update_preview(c)


func _apply_manual_fields() -> void:
	var c := _current()
	if c == null:
		return
	_set_candidate_property(c, "manual_group_id", StringName(_group_edit.text), "Set candidate group")
	_set_candidate_property(c, "manual_orientation", StringName(_orientation_edit.text), "Set candidate orientation")
	_set_candidate_property(c, "manual_display_name", _name_edit.text, "Set candidate display name")
	_set_candidate_property(c, "manual_category", int(_category_spin.value), "Set candidate category")
	_set_candidate_property(c, "manual_ground_footprint", Vector2i(int(_footprint_x.value), int(_footprint_y.value)), "Set candidate footprint")
	_set_candidate_property(c, "manual_interaction_points", _parse_points(_interaction_edit.text), "Set candidate interaction points")


func _approve_current() -> void:
	var c := _current()
	if c == null:
		return
	_set_candidate_property(c, "review_state", CandidateAssetData.ReviewState.APPROVED, "Approve candidate")
	_refresh_list_label()


func _ignore_current() -> void:
	var c := _current()
	if c == null:
		return
	_set_candidate_property(c, "review_state", CandidateAssetData.ReviewState.IGNORED, "Ignore candidate")
	_refresh_list_label()


func _mark_shadow_current() -> void:
	var c := _current()
	if c == null:
		return
	_set_candidate_property(c, "includes_shadow", true, "Mark candidate as shadow")
	_set_candidate_property(c, "review_state", CandidateAssetData.ReviewState.IGNORED, "Ignore shadow candidate")
	_refresh_list_label()


func _merge_selected() -> void:
	if _manifest == null:
		return
	var selected := _candidate_list.get_selected_items()
	if selected.size() < 2:
		_status.text = "至少选择两个 candidate 才能合并"
		return
	var chosen: Array[CandidateAssetData] = []
	for idx in selected:
		if idx >= 0 and idx < _manifest.candidates.size():
			chosen.append(_manifest.candidates[idx])
	if chosen.size() < 2:
		return
	var merged := CandidateAssetData.new()
	merged.candidate_id = StringName(_next_candidate_id("merged"))
	merged.source_texture_path = chosen[0].source_texture_path
	merged.source_region = _union_regions(chosen.map(func(c): return c.get_effective_region()))
	merged.tight_visual_bounds = _union_regions(chosen.map(func(c): return c.tight_visual_bounds))
	merged.pixel_size = merged.source_region.size
	merged.tile_span = Vector2i(ceili(float(merged.source_region.size.x) / 32.0), ceili(float(merged.source_region.size.y) / 32.0))
	merged.needs_manual_review = true
	merged.confidence_score = 0.5
	merged.suggested_group_id = StringName(_group_edit.text)
	merged.suggested_orientation = StringName(_orientation_edit.text)
	for c in chosen:
		for id in c.connected_component_ids:
			if not merged.connected_component_ids.has(id):
				merged.connected_component_ids.append(id)
		for cell in c.touched_tile_cells:
			if not merged.touched_tile_cells.has(cell):
				merged.touched_tile_cells.append(cell)
	var next := _manifest.candidates.duplicate()
	for c in chosen:
		c.review_state = CandidateAssetData.ReviewState.IGNORED
	next.append(merged)
	_replace_candidates(next, "Merge candidates")
	_reload_list_keep_last()


func _split_current_vertical() -> void:
	_split_current(true)


func _split_current_horizontal() -> void:
	_split_current(false)


func _split_current(vertical: bool) -> void:
	var c := _current()
	if c == null:
		return
	var r := c.get_effective_region()
	if (vertical and r.size.x < 2) or ((not vertical) and r.size.y < 2):
		return
	var a := c.duplicate(true) as CandidateAssetData
	var b := c.duplicate(true) as CandidateAssetData
	a.candidate_id = StringName(_next_candidate_id("split_a"))
	b.candidate_id = StringName(_next_candidate_id("split_b"))
	if vertical:
		var w1 := r.size.x / 2
		a.manual_region = Rect2i(r.position, Vector2i(w1, r.size.y))
		b.manual_region = Rect2i(Vector2i(r.position.x + w1, r.position.y), Vector2i(r.size.x - w1, r.size.y))
	else:
		var h1 := r.size.y / 2
		a.manual_region = Rect2i(r.position, Vector2i(r.size.x, h1))
		b.manual_region = Rect2i(Vector2i(r.position.x, r.position.y + h1), Vector2i(r.size.x, r.size.y - h1))
	for part in [a, b]:
		part.review_state = CandidateAssetData.ReviewState.PENDING
		part.needs_manual_review = true
		part.confidence_score = 0.5
	c.review_state = CandidateAssetData.ReviewState.IGNORED
	var next := _manifest.candidates.duplicate()
	next.append(a)
	next.append(b)
	_replace_candidates(next, "Split candidate")
	_reload_list_keep_last()


func _set_candidate_property(c: CandidateAssetData, property: StringName, value, action_name: String) -> void:
	if editor_plugin == null:
		c.set(property, value)
		return
	var undo := editor_plugin.get_undo_redo()
	undo.create_action(action_name)
	undo.add_do_property(c, property, value)
	undo.add_undo_property(c, property, c.get(property))
	undo.commit_action()


func _replace_candidates(next: Array, action_name: String) -> void:
	if editor_plugin == null:
		_manifest.candidates = next
		return
	var undo := editor_plugin.get_undo_redo()
	undo.create_action(action_name)
	undo.add_do_property(_manifest, "candidates", next)
	undo.add_undo_property(_manifest, "candidates", _manifest.candidates.duplicate())
	undo.commit_action()


func _refresh_list_label() -> void:
	var c := _current()
	if c == null:
		return
	_candidate_list.set_item_text(_index, "%s  %s  %.2f" % [
		c.candidate_id,
		CandidateAssetData.ReviewState.keys()[c.review_state],
		c.confidence_score,
	])


func _reload_list_keep_last() -> void:
	_candidate_list.clear()
	for c in _manifest.candidates:
		_candidate_list.add_item("%s  %s  %.2f" % [
			c.candidate_id,
			CandidateAssetData.ReviewState.keys()[c.review_state],
			c.confidence_score,
		])
	_select_candidate(_manifest.candidates.size() - 1)


func _union_regions(rects: Array) -> Rect2i:
	if rects.is_empty():
		return Rect2i()
	var x0: int = rects[0].position.x
	var y0: int = rects[0].position.y
	var x1: int = rects[0].end.x
	var y1: int = rects[0].end.y
	for r: Rect2i in rects:
		x0 = mini(x0, r.position.x)
		y0 = mini(y0, r.position.y)
		x1 = maxi(x1, r.end.x)
		y1 = maxi(y1, r.end.y)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _next_candidate_id(prefix: String) -> String:
	var n := _manifest.candidates.size() + 1
	var id := "%s_%04d" % [prefix, n]
	while _manifest.find_candidate(StringName(id)) != null:
		n += 1
		id = "%s_%04d" % [prefix, n]
	return id


func _parse_points(text: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for part in text.split(";", false):
		var pair := part.strip_edges().split(",", false)
		if pair.size() == 2:
			out.append(Vector2(float(pair[0]), float(pair[1])))
	return out


func _format_points(points: Array[Vector2]) -> String:
	var parts: PackedStringArray = []
	for p in points:
		parts.append("%s,%s" % [p.x, p.y])
	return "; ".join(parts)


func _save_manifest() -> void:
	if _manifest == null:
		return
	var err := ResourceSaver.save(_manifest, _path_edit.text)
	_status.text = "保存成功" if err == OK else "保存失败: %s" % err
