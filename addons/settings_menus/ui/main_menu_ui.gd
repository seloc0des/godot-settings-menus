class_name MainMenuUI
extends Control

# Main menu Control. Drops in as your project's main scene root, or anywhere
# you want to surface the start screen. Wires Play / Options / Credits / Quit
# to scene transitions you configure via exports.
#
# Customize via the MenuTheme Resource (set `theme_data`).

signal play_pressed
signal quit_pressed

@export var theme_data: MenuTheme

## Scene to transition to on Play. If empty, just emits `play_pressed`.
@export_file("*.tscn") var play_scene_path: String = ""

@export var show_credits: bool = true
@export var show_options: bool = true
@export var show_quit: bool = true

var _options_layer: CanvasLayer
var _credits_layer: CanvasLayer
var _options_ui: OptionsMenuUI
var _credits_ui: CreditsUI
var _first_button: Button
var _focus_return: Control


func _ready() -> void:
	if theme_data == null:
		theme_data = MenuTheme.new()
	_build()
	_apply_font_scale()
	# Defer so the button is fully in the tree and sized before we focus it —
	# otherwise the focus rect can render at (0,0) for a frame.
	if _first_button != null:
		_first_button.call_deferred("grab_focus")


func _build() -> void:
	# Background.
	var bg := ColorRect.new()
	bg.color = theme_data.bg_color
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	add_child(bg)
	if theme_data.background_texture != null:
		var bg_tex := TextureRect.new()
		bg_tex.texture = theme_data.background_texture
		bg_tex.anchor_right = 1
		bg_tex.anchor_bottom = 1
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.modulate = Color(1, 1, 1, 0.6)
		add_child(bg_tex)

	# Centered panel.
	var center := CenterContainer.new()
	center.anchor_right = 1
	center.anchor_bottom = 1
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", theme_data.panel_stylebox())
	panel.custom_minimum_size = Vector2(theme_data.menu_max_width, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	# Title.
	var title := Label.new()
	title.text = theme_data.game_title
	title.add_theme_font_size_override("font_size", theme_data.title_font_size)
	title.add_theme_color_override("font_color", theme_data.text)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	if theme_data.game_subtitle != "":
		var sub := Label.new()
		sub.text = theme_data.game_subtitle
		sub.add_theme_font_size_override("font_size", theme_data.body_font_size)
		sub.add_theme_color_override("font_color", theme_data.text_dim)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size = Vector2(theme_data.menu_max_width - 32, 0)
		col.add_child(sub)

	col.add_child(_spacer(8))

	_first_button = _add_button(col, "Play", _on_play)
	if show_options:
		_add_button(col, "Options", _open_options)
	if show_credits:
		_add_button(col, "Credits", _open_credits)
	if show_quit:
		_add_button(col, "Quit", _on_quit)


func _add_button(parent: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	theme_data.apply_to_button(b)
	parent.add_child(b)
	return b


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _apply_font_scale() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	var scale: float = settings.get_font_scale()
	if not is_equal_approx(scale, 1.0):
		_scale_fonts(self, scale)


func _scale_fonts(node: Node, scale: float) -> void:
	if node is Label or node is Button:
		var fs: int = int(node.get_theme_font_size("font_size"))
		if fs > 0:
			node.add_theme_font_size_override("font_size", maxi(8, int(round(fs * scale))))
	for c in node.get_children():
		_scale_fonts(c, scale)


# ---- actions --------------------------------------------------------------

func _on_play() -> void:
	play_pressed.emit()
	if play_scene_path != "":
		get_tree().change_scene_to_file(play_scene_path)


func _on_quit() -> void:
	quit_pressed.emit()
	get_tree().quit()


func _open_options() -> void:
	_focus_return = get_viewport().gui_get_focus_owner()
	if _options_layer == null:
		_options_layer = CanvasLayer.new()
		add_child(_options_layer)
		_options_ui = OptionsMenuUI.new()
		_options_ui.theme_data = theme_data
		_options_ui.close_requested.connect(_close_options)
		_options_layer.add_child(_options_ui)
	_options_layer.visible = true
	# Also flip the inner Control so its own _unhandled_input guard
	# (`if not visible`) blocks stray Esc presses when closed.
	if _options_ui != null:
		_options_ui.visible = true
		_options_ui.focus_default()


func _close_options() -> void:
	if _options_layer != null:
		_options_layer.visible = false
	if _options_ui != null:
		_options_ui.visible = false
	_restore_focus()


func _open_credits() -> void:
	_focus_return = get_viewport().gui_get_focus_owner()
	if _credits_layer == null:
		_credits_layer = CanvasLayer.new()
		add_child(_credits_layer)
		_credits_ui = CreditsUI.new()
		_credits_ui.theme_data = theme_data
		_credits_ui.close_requested.connect(_close_credits)
		_credits_layer.add_child(_credits_ui)
	_credits_layer.visible = true
	if _credits_ui != null:
		_credits_ui.visible = true
		_credits_ui.focus_default()


func _close_credits() -> void:
	if _credits_layer != null:
		_credits_layer.visible = false
	if _credits_ui != null:
		_credits_ui.visible = false
	_restore_focus()


func _restore_focus() -> void:
	if is_instance_valid(_focus_return):
		_focus_return.grab_focus()
	elif _first_button != null:
		_first_button.grab_focus()
	_focus_return = null
