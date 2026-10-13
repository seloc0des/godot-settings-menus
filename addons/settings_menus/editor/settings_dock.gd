@tool
extends Control

# Non-coder authoring dock for profile/settings resources. Reflective: it reads
# the resource's exported properties and builds a control per property
# (slider/spinbox/checkbox/color/dropdown/texture), so a designer tunes the look
# without opening the Inspector. Shared, generic body — only the CONFIG block at
# the top differs between packs (this copy targets the menu themes).
#
# Follows the dock template: explicit-save, dirty tracking + discard guard,
# delete confirm, search, working-copy + take_over_path. Gradients, curves,
# arrays, and nested resources are deferred to the Inspector (with a note) but
# preserved through the working copy so saving never drops them.

# ===================== CONFIG (per-pack) =====================
const PROFILE_SCRIPTS := [
	preload("res://addons/settings_menus/resources/menu_theme.gd"),
]
const DEFAULT_DIR := "res://themes"
const DOCK_NAME := "Menu Theme"
const SCENE_TARGETS := {}
# =============================================================

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

var _dir := DEFAULT_DIR
var _paths: PackedStringArray = PackedStringArray()
var _display_paths: PackedStringArray = PackedStringArray()
var _current_index := -1
var _current_path := ""
var _current: Resource
var _dirty := false
var _loading := false
var _pending_index := -1

var _search: LineEdit
var _list: ItemList
var _dir_label: Label
var _dirty_label: Label
var _status: Label
var _new_type: OptionButton
var _field_box: VBoxContainer
var _scroll: ScrollContainer

var _file_dialog: EditorFileDialog
var _confirm_delete: ConfirmationDialog
var _confirm_switch: ConfirmationDialog
var _scene_menu: PopupMenu
var _pending_targets: Array = []
# active texture picker target setter, used across the file dialog callback
var _icon_target := Callable()


func _ready() -> void:
	name = DOCK_NAME
	_build_ui()
	_refresh_list()
	if Engine.is_editor_hint():
		EditorInterface.get_inspector().property_edited.connect(_on_inspector_edit)


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0) if _scroll != null else Vector2.ZERO


# ---------------------------------------------------------------------------
# UI shell
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# One column that scrolls: the list on top, the picked resource's fields under
	# it. Side by side, the fields needed more width than a default dock has.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.minimum_size_changed.connect(update_minimum_size)
	add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_dir_label = Label.new()
	_dir_label.text = _dir
	_dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dir_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a deep folder wraps, it doesn't widen the dock
	_dir_label.tooltip_text = "Folder scanned for profiles"
	header.add_child(_dir_label)
	header.add_child(_mk_button("Folder…", _on_choose_folder))

	_search = LineEdit.new()
	_search.placeholder_text = "Search…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_list())
	root.add_child(_search)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 120)
	_list.item_selected.connect(_on_list_selected)
	root.add_child(_list)
	# type picker only matters when a pack authors more than one profile type
	if PROFILE_SCRIPTS.size() > 1:
		_new_type = OptionButton.new()
		for i in PROFILE_SCRIPTS.size():
			_new_type.add_item(_type_name(PROFILE_SCRIPTS[i]), i)
		root.add_child(_new_type)
	var lb := HBoxContainer.new()
	root.add_child(lb)
	lb.add_child(_mk_button("New", _on_new))
	lb.add_child(_mk_button("Dup", _on_duplicate))
	lb.add_child(_mk_button("Del", _on_delete_pressed))

	root.add_child(HSeparator.new())
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(col)

	_dirty_label = Label.new()
	_dirty_label.modulate = WARN_COLOR
	col.add_child(_dirty_label)

	_field_box = VBoxContainer.new()
	_field_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_field_box)

	col.add_child(HSeparator.new())
	col.add_child(_mk_button("Save", _on_save))
	if not SCENE_TARGETS.is_empty():
		col.add_child(_mk_button("Add to scene…", _on_add_to_scene))
		_scene_menu = PopupMenu.new()
		_scene_menu.id_pressed.connect(_on_scene_menu_id)
		add_child(_scene_menu)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	add_child(_file_dialog)
	_confirm_delete = ConfirmationDialog.new()
	_confirm_delete.ok_button_text = "Delete"
	_confirm_delete.confirmed.connect(_delete_current)
	add_child(_confirm_delete)
	_confirm_switch = ConfirmationDialog.new()
	_confirm_switch.dialog_text = "Discard unsaved changes?"
	_confirm_switch.ok_button_text = "Discard"
	_confirm_switch.confirmed.connect(_on_switch_confirmed)
	_confirm_switch.canceled.connect(_on_switch_canceled)
	add_child(_confirm_switch)


func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _set_status(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text


func _type_name(scr: Script) -> String:
	var gn := scr.get_global_name()
	return str(gn) if gn != &"" else scr.resource_path.get_file().get_basename()


# ---------------------------------------------------------------------------
# List
# ---------------------------------------------------------------------------

func _refresh_list() -> void:
	_dir_label.text = _dir
	_paths = _scan(_dir)
	var query := _search.text.strip_edges().to_lower()
	_display_paths = PackedStringArray()
	_list.clear()
	for p in _paths:
		var display := p.get_file().get_basename()
		if query != "" and not display.to_lower().contains(query):
			continue
		_display_paths.append(p)
		_list.add_item(display)
	if _current_path != "":
		_reselect_current_row()


func _scan(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var full := dir_path.path_join(f)
			var res := load(full)
			if res and _is_profile(res):
				out.append(full)
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _is_profile(res: Resource) -> bool:
	for scr in PROFILE_SCRIPTS:
		if res.get_script() == scr:
			return true
	return false


func _reselect_current_row() -> void:
	for i in _display_paths.size():
		if _display_paths[i] == _current_path:
			_list.select(i)
			_current_index = i
			return
	_current_index = -1


# ---------------------------------------------------------------------------
# Selection + dirty guard
# ---------------------------------------------------------------------------

func _on_list_selected(idx: int) -> void:
	if idx == _current_index:
		return
	if _dirty:
		_pending_index = idx
		_confirm_switch.popup_centered()
		return
	_show_at(idx)


func _on_switch_confirmed() -> void:
	_dirty = false
	_show_at(_pending_index)


func _on_switch_canceled() -> void:
	if _current_index >= 0 and _current_index < _list.item_count:
		_list.select(_current_index)


func _show_at(idx: int) -> void:
	if idx < 0 or idx >= _display_paths.size():
		return
	_current_index = idx
	_current_path = _display_paths[idx]
	_current = load(_current_path).duplicate(false)  # working copy (shares Gradient/Texture refs)
	_build_fields()
	_clear_dirty()
	_set_status("", OK_COLOR)


# ---------------------------------------------------------------------------
# Reflective field builder
# ---------------------------------------------------------------------------

func _build_fields() -> void:
	for c in _field_box.get_children():
		c.queue_free()
	if _current == null:
		return
	_loading = true
	# the script's own list: in the editor a resource whose script isn't a tool script is
	# a placeholder, and its property list has no script-variable flag, so the form was empty
	var scr: Script = _current.get_script()
	for p in (scr.get_script_property_list() if scr != null else []):
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_GROUP:
			if str(p["name"]) != "":
				_field_box.add_child(_header(str(p["name"])))
			continue
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP):
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		_build_field(p)
	_loading = false


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = "[ %s ]" % text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(0.75, 0.8, 0.9)
	return l


func _build_field(p: Dictionary) -> void:
	var prop: String = p["name"]
	var t: int = p["type"]
	var hint: int = p["hint"]
	var hint_string: String = p["hint_string"]
	var value = _current.get(prop)
	var control: Control = null

	match t:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = value
			cb.toggled.connect(func(v): _set_prop(prop, v))
			control = cb
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				control = _enum_control(prop, hint_string, int(value))
			else:
				control = _spin_control(prop, hint, hint_string, value, true)
		TYPE_FLOAT:
			control = _spin_control(prop, hint, hint_string, value, false)
		TYPE_STRING, TYPE_STRING_NAME:
			if hint == PROPERTY_HINT_MULTILINE_TEXT:
				var te := TextEdit.new()
				te.custom_minimum_size = Vector2(0, 48)
				te.text = str(value)
				te.text_changed.connect(func(): _set_prop(prop, te.text))
				control = te
			else:
				var le := LineEdit.new()
				le.text = str(value)
				le.text_changed.connect(func(v): _set_prop(prop, StringName(v) if t == TYPE_STRING_NAME else v))
				control = le
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.color = value
			cp.custom_minimum_size = Vector2(0, 24)
			cp.color_changed.connect(func(v): _set_prop(prop, v))
			control = cp
		TYPE_VECTOR2, TYPE_VECTOR2I:
			control = _vec2_control(prop, value, t == TYPE_VECTOR2I)
		TYPE_OBJECT:
			if hint == PROPERTY_HINT_RESOURCE_TYPE and hint_string.contains("Texture"):
				control = _texture_control(prop, value)
			else:
				# Gradient / Curve / nested resource — Inspector territory
				control = _deferred_label(hint_string)
		_:
			if t == TYPE_ARRAY or t == TYPE_DICTIONARY:
				control = _deferred_label("array/dictionary")
	if control == null:
		return
	_row(_field_box, _pretty(prop), control)


func _spin_control(prop: String, hint: int, hint_string: String, value, is_int: bool) -> SpinBox:
	var s := SpinBox.new()
	if hint == PROPERTY_HINT_RANGE:
		var r := _parse_range(hint_string)
		s.min_value = r[0]
		s.max_value = r[1]
		s.step = r[2] if r[2] > 0.0 else (1.0 if is_int else 0.01)
	else:
		s.min_value = -1000000000.0
		s.max_value = 1000000000.0
		s.step = 1.0 if is_int else 0.01
		s.allow_greater = true
		s.allow_lesser = true
	s.value = value
	if is_int:
		s.value_changed.connect(func(v): _set_prop(prop, int(v)))
	else:
		s.value_changed.connect(func(v): _set_prop(prop, v))
	return s


func _enum_control(prop: String, hint_string: String, value: int) -> OptionButton:
	var opt := OptionButton.new()
	var names := hint_string.split(",", false)
	for i in names.size():
		# @export_enum entries may carry ":N"; strip it and use N if present
		var parts := String(names[i]).split(":")
		var label := parts[0]
		var id := int(parts[1]) if parts.size() > 1 else i
		opt.add_item(label, id)
	opt.select(max(0, opt.get_item_index(value)))
	opt.item_selected.connect(func(_i): _set_prop(prop, opt.get_selected_id()))
	# a long choice ends in "…" in a narrow dock; the open list shows it whole
	opt.fit_to_longest_item = false
	opt.clip_text = true
	opt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return opt


func _vec2_control(prop: String, value, is_int: bool) -> Control:
	var box := HBoxContainer.new()
	var sx := SpinBox.new()
	var sy := SpinBox.new()
	for s in [sx, sy]:
		s.min_value = -1000000000.0
		s.max_value = 1000000000.0
		s.step = 1.0 if is_int else 0.01
		s.allow_greater = true
		s.allow_lesser = true
	sx.value = value.x
	sy.value = value.y
	var read := func():
		if is_int:
			_set_prop(prop, Vector2i(int(sx.value), int(sy.value)))
		else:
			_set_prop(prop, Vector2(sx.value, sy.value))
	sx.value_changed.connect(func(_v): read.call())
	sy.value_changed.connect(func(_v): read.call())
	box.add_child(_tiny("X", sx))
	box.add_child(_tiny("Y", sy))
	return box


func _texture_control(prop: String, value) -> Control:
	var box := HBoxContainer.new()
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(40, 40)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = value
	box.add_child(preview)
	var pick := _mk_button("Pick…", func(): _pick_texture(prop, preview))
	box.add_child(pick)
	var clear := _mk_button("Clear", func():
		preview.texture = null
		_set_prop(prop, null))
	box.add_child(clear)
	return box


func _deferred_label(kind: String) -> Label:
	var l := Label.new()
	l.text = "(%s: edit in Inspector)" % kind
	l.modulate = Color(0.7, 0.7, 0.7)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _set_prop(prop: String, value) -> void:
	if _loading or _current == null:
		return
	_current.set(prop, value)
	_mark_dirty()


func _pick_texture(prop: String, preview: TextureRect) -> void:
	_icon_target = func(path):
		var tex = load(path)
		if tex is Texture2D:
			preview.texture = tex
			_set_prop(prop, tex)
	_open_dialog(EditorFileDialog.FILE_MODE_OPEN_FILE,
		["*.png,*.svg,*.jpg,*.jpeg,*.webp ; Images"])


# ---------------------------------------------------------------------------
# helpers: rows, range parse, name prettify
# ---------------------------------------------------------------------------

func _row(parent: Node, label_text: String, field: Control) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label_text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(field)
	parent.add_child(box)


func _tiny(text: String, field: Control) -> Control:
	var box := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	box.add_child(l)
	box.add_child(field)
	return box


func _parse_range(hint_string: String) -> Array:
	var nums: Array = []
	for tok in hint_string.split(","):
		var t := tok.strip_edges()
		if t.is_valid_float():
			nums.append(t.to_float())
	var lo: float = nums[0] if nums.size() > 0 else 0.0
	var hi: float = nums[1] if nums.size() > 1 else 100.0
	var step: float = nums[2] if nums.size() > 2 else 0.0
	return [lo, hi, step]


func _pretty(prop: String) -> String:
	return prop.replace("_", " ").capitalize()


# ---------------------------------------------------------------------------
# Create / duplicate / delete / save
# ---------------------------------------------------------------------------

func _on_new() -> void:
	if not DirAccess.dir_exists_absolute(_dir):
		DirAccess.make_dir_recursive_absolute(_dir)
	var scr: Script = PROFILE_SCRIPTS[_new_type.get_selected_id()] if _new_type else PROFILE_SCRIPTS[0]
	var base := "new_" + _type_name(scr).to_snake_case()
	var path := _unique_path(_dir, base)
	var err := ResourceSaver.save(scr.new(), path)
	if err != OK:
		_set_status("Could not create (err %d)" % err, ERR_COLOR)
		return
	_after_write_select(path)


func _on_duplicate() -> void:
	if _current == null:
		return
	var base := _current_path.get_file().get_basename() + "_copy"
	var path := _unique_path(_dir, base)
	var err := ResourceSaver.save(_current.duplicate(false), path)
	if err != OK:
		_set_status("Duplicate failed (err %d)" % err, ERR_COLOR)
		return
	_after_write_select(path)


func _on_delete_pressed() -> void:
	if _current_path == "":
		return
	_confirm_delete.dialog_text = "Delete \"%s\"?\nThis removes the .tres file and can't be undone." % _current_path.get_file()
	_confirm_delete.popup_centered()


func _delete_current() -> void:
	if _current_path == "":
		return
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(_current_path))
	if err != OK:
		_set_status("Delete failed (err %d)" % err, ERR_COLOR)
		return
	_current = null
	_current_path = ""
	_current_index = -1
	_build_fields()
	_clear_dirty()
	_refresh_editor_fs()
	_refresh_list()


func _on_save() -> void:
	if _current == null or _current_path == "":
		return
	var err := ResourceSaver.save(_current, _current_path)
	if err != OK:
		_set_status("Save failed (err %d)" % err, ERR_COLOR)
		return
	_sync_cached(_current, _current_path)
	_current = _current.duplicate(false)
	_clear_dirty()
	_set_status("Saved.", OK_COLOR)


func _after_write_select(path: String) -> void:
	_register_uid(path)
	_refresh_editor_fs()
	_search.text = ""
	_current_path = path
	_refresh_list()
	_reselect_current_row()
	if _current_index >= 0:
		_show_at(_current_index)


# ---------------------------------------------------------------------------
# dirty / dialogs
# ---------------------------------------------------------------------------

func _mark_dirty() -> void:
	if _loading:
		return
	if not _dirty:
		_dirty = true
		_dirty_label.text = "● Unsaved changes"


func _clear_dirty() -> void:
	_dirty = false
	_dirty_label.text = ""


func _on_choose_folder() -> void:
	_icon_target = Callable()
	_open_dialog(EditorFileDialog.FILE_MODE_OPEN_DIR, [])


func _open_dialog(mode: int, filters: Array) -> void:
	for c in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(c.callable)
	for c in _file_dialog.dir_selected.get_connections():
		_file_dialog.dir_selected.disconnect(c.callable)
	_file_dialog.file_mode = mode
	_file_dialog.clear_filters()
	for f in filters:
		_file_dialog.add_filter(f)
	if mode == EditorFileDialog.FILE_MODE_OPEN_DIR:
		_file_dialog.dir_selected.connect(_on_dir_selected, CONNECT_ONE_SHOT)
	else:
		_file_dialog.file_selected.connect(_on_file_selected, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered_ratio(0.6)


func _on_dir_selected(path: String) -> void:
	_dir = path
	_current = null
	_current_path = ""
	_current_index = -1
	_search.text = ""
	_build_fields()
	_clear_dirty()
	_refresh_list()


func _on_file_selected(path: String) -> void:
	if _icon_target.is_valid():
		_icon_target.call(path)
		_icon_target = Callable()


func _unique_path(dir_path: String, base: String) -> String:
	var candidate := dir_path.path_join(base + ".tres")
	var n := 1
	while FileAccess.file_exists(candidate):
		candidate = dir_path.path_join("%s_%d.tres" % [base, n])
		n += 1
	return candidate


# ---------------------------------------------------------------------------
# W-WIRE — spawn the consuming node in the open scene and assign this resource
# ---------------------------------------------------------------------------

func _on_add_to_scene() -> void:
	if _current == null or _current_path == "":
		_set_status("Select and save a resource first.", ERR_COLOR)
		return
	if _dirty:
		_set_status("Save your changes first, then add to scene.", WARN_COLOR)
		return
	var key: String = _current.get_script().resource_path
	_pending_targets = SCENE_TARGETS.get(key, [])
	if _pending_targets.is_empty():
		_set_status("No scene node consumes this resource type.", ERR_COLOR)
		return
	if _pending_targets.size() == 1:
		_spawn(_pending_targets[0])
		return
	_scene_menu.clear()
	for i in _pending_targets.size():
		_scene_menu.add_item(_pending_targets[i]["label"], i)
	_scene_menu.reset_size()
	# Window.position is Vector2i — cast explicitly (Vector2 assignment throws).
	_scene_menu.position = Vector2i(get_screen_position()) + Vector2i(0, 36)
	_scene_menu.popup()


func _on_scene_menu_id(id: int) -> void:
	if id >= 0 and id < _pending_targets.size():
		_spawn(_pending_targets[id])


func _spawn(target: Dictionary) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_set_status("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var scr = load(target["script"])
	if scr == null:
		_set_status("Node script missing: %s" % target["script"], ERR_COLOR)
		return
	var node: Node = scr.new()
	# parent under the current selection if it's a node, else the scene root
	var parent: Node = root
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.size() > 0 and sel[0] is Node:
		parent = sel[0]
	parent.add_child(node, true)
	node.owner = root  # required so the node is saved into the scene
	# assign the on-disk resource (an ext_resource ref, not the working copy)
	node.set(target["prop"], load(_current_path))
	node.name = _current_path.get_file().get_basename()
	# optional: auto-wire the node to a light/environment already in the scene
	var extra := ""
	if target.get("auto_light", false):
		var light := _find_in_tree(root, "DirectionalLight3D")
		if light:
			node.set("sun_path", node.get_path_to(light))
			extra = " (sun wired to %s)" % light.name
		else:
			extra = " (point its Sun Path at a DirectionalLight3D)"
		var env := _find_in_tree(root, "WorldEnvironment")
		if env:
			node.set("environment_path", node.get_path_to(env))
	# flag the scene, or Play runs the saved file without the node we just added
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)
	_set_status("Added %s to the scene.%s" % [node.name, extra], OK_COLOR)


func _find_in_tree(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var found := _find_in_tree(c, cls)
		if found:
			return found
	return null


func _refresh_editor_fs() -> void:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()


# The Inspector edits the file's own copy. Keep the working copy in step, or the
# next Save here would put back whatever the Inspector just changed.
func _on_inspector_edit(prop: String) -> void:
	if _current == null or _current_path == "":
		return
	var obj := EditorInterface.get_inspector().get_edited_object()
	if not (obj is Resource) or (obj as Resource).resource_path != _current_path:
		return
	_current.set(prop, obj.get(prop))
	_build_fields()


# The file is saved; now make the copy everyone else already holds (scene nodes, the
# Inspector) match it. take_over_path handed the path to the working copy instead,
# which left those holders with an orphaned old copy their scene then saved embedded.
func _sync_cached(saved: Resource, path: String) -> void:
	if not ResourceLoader.has_cached(path):
		saved.take_over_path(path)  # nobody holds it yet, so taking over is safe
		return
	var cached: Resource = ResourceLoader.load(path)
	if cached == saved:
		return
	for p in saved.get_property_list():
		var n: String = p.name
		if (int(p.usage) & PROPERTY_USAGE_STORAGE) and n != "script" and n != "resource_path":
			cached.set(n, saved.get(n))
	cached.emit_changed()


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
