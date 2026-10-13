class_name OptionsMenuUI
extends Control

# Tabbed options menu — Audio / Display / Controls / Accessibility.
# Listens to /root/Settings for the live values; pushing UI changes flows
# through Settings.set_value and re-applies immediately.

signal close_requested

@export var theme_data: MenuTheme

var _tabs: TabContainer
var _back_btn: Button


func _ready() -> void:
	if theme_data == null:
		theme_data = MenuTheme.new()
	anchor_right = 1
	anchor_bottom = 1
	_build()
	focus_default()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = theme_data.bg_color
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	add_child(dim)

	var margin := MarginContainer.new()
	margin.anchor_right = 1
	margin.anchor_bottom = 1
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", theme_data.heading_font_size)
	title.add_theme_color_override("font_color", theme_data.text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.pressed.connect(_reset_all)
	theme_data.apply_to_button(reset_btn)
	header.add_child(reset_btn)
	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.pressed.connect(_close)
	theme_data.apply_to_button(_back_btn)
	header.add_child(_back_btn)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)

	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_display_tab())
	# Only when something is listening. A Graphics tab whose dropdowns move
	# nothing is worse than no tab at all.
	var settings_for_tabs := _settings()
	if settings_for_tabs != null and settings_for_tabs.quality_provider() != null:
		_tabs.add_child(_build_graphics_tab())
	_tabs.add_child(_build_controls_tab())
	_tabs.add_child(_build_a11y_tab())
	_frame_checkboxes(_tabs)


# ---- tab: audio ----------------------------------------------------------

func _build_audio_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Audio"
	tab.add_theme_constant_override("separation", 10)
	_add_padding(tab)
	_add_slider_row(tab, "Master", "audio.master", 0.0, 1.0, 0.01)
	_add_slider_row(tab, "Music", "audio.music", 0.0, 1.0, 0.01)
	_add_slider_row(tab, "SFX", "audio.sfx", 0.0, 1.0, 0.01)
	# Only the buses this project actually has. Showing a Dialogue slider in a
	# game with no Dialogue bus is a control that does nothing, which is worse
	# than not offering it.
	for pair in [["Dialogue", "dialogue"], ["UI", "ui"], ["Ambience", "ambience"]]:
		if SETTINGS_MANAGER.bus_exists(pair[1]):
			_add_slider_row(tab, pair[0], "audio.%s" % pair[1], 0.0, 1.0, 0.01)
	return tab


func _add_slider_row(parent: Container, label_text: String, setting_key: String,
		min_v: float, max_v: float, step: float) -> void:
	var settings := _settings()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", theme_data.body_font_size)
	label.add_theme_color_override("font_color", theme_data.text)
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = float(settings.get_value(setting_key, min_v)) if settings != null else min_v
	slider.custom_minimum_size = Vector2(280, 0)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = "%d%%" % int(slider.value * 100.0)
	value_label.add_theme_font_size_override("font_size", theme_data.body_font_size)
	value_label.add_theme_color_override("font_color", theme_data.text_dim)
	value_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float):
		var s := _settings()
		if s != null:
			s.set_value(setting_key, v)
		value_label.text = "%d%%" % int(v * 100.0))


# ---- tab: display --------------------------------------------------------

func _build_display_tab() -> Control:
	var settings := _settings()
	var tab := VBoxContainer.new()
	tab.name = "Display"
	tab.add_theme_constant_override("separation", 10)
	_add_padding(tab)
	if settings == null:
		return tab  # nothing to bind to; leave the tab empty rather than crash

	# Window mode.
	var mode_row := _row(tab, "Window Mode")
	var mode_opt := OptionButton.new()
	for label in ["Windowed", "Fullscreen", "Borderless"]:
		mode_opt.add_item(label)
	mode_opt.selected = int(settings.get_value("display.window_mode", 0))
	mode_opt.item_selected.connect(func(idx):
		var s := _settings()
		if s != null:
			s.set_value("display.window_mode", idx))
	mode_row.add_child(mode_opt)

	# Resolution.
	var res_row := _row(tab, "Resolution")
	var res_opt := OptionButton.new()
	for r in settings.RESOLUTIONS:
		res_opt.add_item("%d × %d" % [r.x, r.y])
	res_opt.selected = int(settings.get_value("display.resolution_index", 0))
	res_opt.item_selected.connect(func(idx):
		var s := _settings()
		if s != null:
			s.set_value("display.resolution_index", idx))
	res_row.add_child(res_opt)

	# VSync.
	var vsync_row := _row(tab, "VSync")
	var vsync_cb := CheckBox.new()
	vsync_cb.button_pressed = bool(settings.get_value("display.vsync", true))
	vsync_cb.toggled.connect(func(p):
		var s := _settings()
		if s != null:
			s.set_value("display.vsync", p))
	vsync_row.add_child(vsync_cb)

	# FPS counter.
	var fps_row := _row(tab, "Show FPS")
	var fps_cb := CheckBox.new()
	fps_cb.button_pressed = bool(settings.get_value("display.fps_visible", false))
	fps_cb.toggled.connect(func(p):
		var s := _settings()
		if s != null:
			s.set_value("display.fps_visible", p))
	fps_row.add_child(fps_cb)

	return tab


# ---- tab: controls -------------------------------------------------------

func _build_controls_tab() -> Control:
	var settings := _settings()
	var tab := VBoxContainer.new()
	tab.name = "Controls"
	tab.add_theme_constant_override("separation", 6)
	_add_padding(tab)
	if settings == null:
		return tab

	var hint := Label.new()
	hint.text = "Click a binding and press the new one: a key or mouse button on the left, a gamepad button, trigger or stick on the right. Esc or Start cancels."
	hint.add_theme_font_size_override("font_size", theme_data.body_font_size)
	hint.add_theme_color_override("font_color", theme_data.text_dim)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 0)
	tab.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for action in settings.rebindable_actions:
		if not InputMap.has_action(String(action)):
			continue
		var row := KeyRebindRow.new()
		row.action = String(action)
		row.theme_data = theme_data
		list.add_child(row)

	var reset_btn := Button.new()
	reset_btn.text = "Reset All Bindings"
	reset_btn.pressed.connect(func():
		var s := _settings()
		if s != null:
			s.reset_all_keybinds()
		_refresh_controls_tab())
	theme_data.apply_to_button(reset_btn)
	tab.add_child(reset_btn)
	return tab


func _refresh_controls_tab() -> void:
	# Rebuild the controls tab by swapping it. The old one goes first: added while the
	# old one still held the name, the new tab was renamed "@VBoxContainer@NNN", which
	# became its title, so the next refresh couldn't find "Controls".
	var tabs := _tabs
	var idx := -1
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == "Controls":
			idx = i; break
	if idx < 0:
		return
	var old := tabs.get_child(idx)
	var current := tabs.current_tab
	# The focused button leaves with the old tab, and a pad was left with nowhere to
	# go. Its twin in the new tab takes the focus instead.
	var focused := get_viewport().gui_get_focus_owner()
	var focus_text := (focused as Button).text if focused is Button and old.is_ancestor_of(focused) else ""
	tabs.remove_child(old)
	old.queue_free()
	var fresh := _build_controls_tab()
	tabs.add_child(fresh)
	tabs.move_child(fresh, idx)
	tabs.current_tab = current
	_frame_checkboxes(fresh)
	if focus_text == "":
		return
	for b in fresh.find_children("*", "Button", true, false):
		if (b as Button).text == focus_text:
			(b as Button).grab_focus.call_deferred()
			return


# ---- tab: graphics -------------------------------------------------------

func _build_graphics_tab() -> Control:
	var settings := _settings()
	var tab := VBoxContainer.new()
	tab.name = "Graphics"
	tab.add_theme_constant_override("separation", 10)
	_add_padding(tab)
	if settings == null:
		return tab

	for row in settings.QUALITY_AXES:
		var key := String(row[0])
		var axis_row := _row(tab, String(row[1]))
		var opt := OptionButton.new()
		for level_name in settings.QUALITY_LEVELS:
			opt.add_item(String(level_name))
		# Stored as -1 for "follow", which is item 0 here.
		opt.selected = int(settings.get_value("quality." + key, -1)) + 1
		opt.item_selected.connect(func(idx: int):
			var s := _settings()
			if s != null:
				s.set_value("quality." + key, idx - 1))
		axis_row.add_child(opt)

	var note := Label.new()
	note.text = "Each of these follows the graphics preset until you change it, and then stays where you put it even if the preset moves."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", theme_data.text_dim)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)
	return tab


# ---- tab: accessibility --------------------------------------------------

func _build_a11y_tab() -> Control:
	var settings := _settings()
	var tab := VBoxContainer.new()
	tab.name = "Accessibility"
	tab.add_theme_constant_override("separation", 10)
	_add_padding(tab)
	if settings == null:
		return tab

	# Font scale.
	var scale_row := _row(tab, "Font Scale")
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.75
	scale_slider.max_value = 1.5
	scale_slider.step = 0.05
	scale_slider.value = float(settings.get_value("a11y.font_scale", 1.0))
	scale_slider.custom_minimum_size = Vector2(280, 0)
	scale_row.add_child(scale_slider)
	var scale_value := Label.new()
	scale_value.text = "%.2f×" % scale_slider.value
	scale_value.add_theme_color_override("font_color", theme_data.text_dim)
	scale_value.custom_minimum_size = Vector2(60, 0)
	scale_row.add_child(scale_value)
	scale_slider.value_changed.connect(func(v: float):
		var s := _settings()
		if s != null:
			s.set_value("a11y.font_scale", v)
		scale_value.text = "%.2f×" % v)

	# Colorblind filter.
	var cb_row := _row(tab, "Colorblind Filter")
	var cb_opt := OptionButton.new()
	for f in settings.COLORBLIND_FILTERS:
		cb_opt.add_item(String(f).capitalize())
	var current := String(settings.get_value("a11y.colorblind_filter", "none"))
	var current_idx := 0
	for i in range(settings.COLORBLIND_FILTERS.size()):
		if String(settings.COLORBLIND_FILTERS[i]) == current:
			current_idx = i; break
	cb_opt.selected = current_idx
	cb_opt.item_selected.connect(func(idx):
		var s := _settings()
		if s != null:
			s.set_value("a11y.colorblind_filter", String(s.COLORBLIND_FILTERS[idx])))
	cb_row.add_child(cb_opt)

	# Reduce motion.
	var motion_row := _row(tab, "Reduce Motion")
	var motion_cb := CheckBox.new()
	motion_cb.button_pressed = bool(settings.get_value("a11y.reduce_motion", false))
	motion_cb.toggled.connect(func(p):
		var s := _settings()
		if s != null:
			s.set_value("a11y.reduce_motion", p))
	motion_row.add_child(motion_cb)

	# Effects. One toggle each, not a single post-processing switch: someone who
	# wants shake gone usually still wants the grain.
	var fx_head := Label.new()
	fx_head.text = "Effects"
	fx_head.add_theme_font_size_override("font_size", theme_data.body_font_size)
	fx_head.add_theme_color_override("font_color", theme_data.text_dim)
	tab.add_child(fx_head)

	var fx_rows: Dictionary = {}
	for row in settings.EFFECTS:
		var key := String(row[0])
		var fx_row := _row(tab, String(row[1]))
		var fx_cb := CheckBox.new()
		fx_cb.button_pressed = bool(settings.get_value("fx." + key, true))
		fx_cb.toggled.connect(func(p):
			var s := _settings()
			if s != null:
				s.set_value("fx." + key, p))
		fx_row.add_child(fx_cb)
		fx_rows[key] = fx_row

	# Reduce motion switches the motion effects off, so show them off rather than
	# leaving a ticked box beside an effect that is not running. Set without the
	# signal, or the displayed value writes itself back over the preference it is
	# standing in for.
	var sync_motion := func() -> void:
		var s := _settings()
		if s == null:
			return
		var reduced := bool(s.get_value("a11y.reduce_motion", false))
		for row in s.EFFECTS:
			if not bool(row[2]):
				continue
			var r := fx_rows[String(row[0])] as HBoxContainer
			var box := r.get_child(1) as CheckBox
			box.disabled = reduced
			box.set_pressed_no_signal(s.is_effect_enabled(String(row[0])))
			var lbl := r.get_child(0) as Label
			lbl.add_theme_color_override("font_color", theme_data.text_dim if reduced else theme_data.text)
	sync_motion.call()
	motion_cb.toggled.connect(func(_p): sync_motion.call())

	var note := Label.new()
	note.text = "Font scale takes effect after re-opening menus. Game UI should query Settings.get_font_scale() at startup. Effect toggles are published on Settings.effects_changed for your game to act on. Reduce Motion switches the motion effects off without forgetting how you had them."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", theme_data.text_dim)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)

	return tab


# ---- shared helpers ------------------------------------------------------

func _row(parent: Container, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", theme_data.body_font_size)
	label.add_theme_color_override("font_color", theme_data.text)
	label.custom_minimum_size = Vector2(180, 0)
	row.add_child(label)
	return row


func _add_padding(box: VBoxContainer) -> void:
	var p := Control.new()
	p.custom_minimum_size = Vector2(0, 8)
	box.add_child(p)


# Every box gets the theme's unticked frame, the ones a subclass adds in its own tab
# builders included. Godot's stock one barely showed on this background. A box
# already drawn from your own Godot Theme is left alone.
func _frame_checkboxes(root: Node) -> void:
	var stock := ThemeDB.get_default_theme().get_icon(&"unchecked", &"CheckBox")
	for node in root.find_children("*", "CheckBox", true, false):
		var cb := node as CheckBox
		if cb.get_theme_icon(&"unchecked") == stock:
			theme_data.apply_to_checkbox(cb)


# ---- actions --------------------------------------------------------------

func _reset_all() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.reset_to_defaults()
	# Cheap rebuild: re-instantiate the whole control.
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	_build()
	focus_default()


func _close() -> void:
	close_requested.emit()


func focus_default() -> void:
	# Land on Back so Tab walks into the tabs naturally and Esc has an obvious
	# escape hatch already highlighted.
	if _back_btn != null:
		call_deferred("_grab_if_shown", _back_btn)


# All three adds one that starts hidden. It used to grab focus anyway and keep it,
# so the main menu under it ignored Enter and the arrows. Focus comes when it opens.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _back_btn != null and is_visible_in_tree():
		focus_default()


func _grab_if_shown(c: Control) -> void:
	if is_instance_valid(c) and c.is_visible_in_tree():
		c.grab_focus()


# Centralized accessor so every consumer null-checks consistently. Returns
# null if the Settings autoload isn't installed (legitimate for headless use
# or projects that haven't wired the addon yet).
func _settings() -> Node:
	return get_node_or_null("/root/Settings")


# Settings is reached through its script instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const SETTINGS_MANAGER := preload("res://addons/settings_menus/settings_manager.gd")
