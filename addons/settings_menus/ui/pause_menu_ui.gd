class_name PauseMenuUI
extends CanvasLayer

# Drop-in pause overlay. Listens for the "pause" action by default and toggles
# itself on. Pauses the tree via SceneTree.paused — your game code should set
# process modes accordingly. Resume / Options / Main Menu / Quit.

signal resumed
signal main_menu_pressed
signal quit_pressed

@export var theme_data: MenuTheme
@export var pause_action: String = "pause"
@export_file("*.tscn") var main_menu_scene_path: String = ""
@export var listen_for_pause_action: bool = true

var _panel: PanelContainer
var _options: OptionsMenuUI
var _first_button: Button
var _focus_return: Control


func _ready() -> void:
	if theme_data == null:
		theme_data = MenuTheme.new()
	process_mode = Node.PROCESS_MODE_ALWAYS  # menu still ticks when paused
	layer = 100
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not listen_for_pause_action:
		return
	if event.is_action_pressed(pause_action):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		resume()
	else:
		pause()


func pause() -> void:
	get_tree().paused = true
	visible = true
	# If Options was left open from a prior session (external resume() without
	# closing the sub-panel first), route focus into Options instead of the
	# hidden Resume button.
	if _options != null and _options.visible:
		_options.focus_default()
	elif _first_button != null:
		_first_button.call_deferred("grab_focus")


func resume() -> void:
	get_tree().paused = false
	visible = false
	# Drop focus so the game scene doesn't see lingering UI focus once we hide.
	var owner_ctl := get_viewport().gui_get_focus_owner()
	if owner_ctl != null and is_ancestor_of(owner_ctl):
		owner_ctl.release_focus()
	resumed.emit()


# ---- skeleton -------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1
	center.anchor_bottom = 1
	add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", theme_data.panel_stylebox())
	_panel.custom_minimum_size = Vector2(theme_data.menu_max_width, 0)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", theme_data.heading_font_size)
	title.add_theme_color_override("font_color", theme_data.text)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_first_button = _add_button(col, "Resume", resume)
	_add_button(col, "Options", _open_options)
	_add_button(col, "Main Menu", _main_menu)
	_add_button(col, "Quit to Desktop", _quit)


func _add_button(parent: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	theme_data.apply_to_button(b)
	parent.add_child(b)
	return b


# ---- actions --------------------------------------------------------------

func _open_options() -> void:
	_focus_return = get_viewport().gui_get_focus_owner()
	if _options == null:
		_options = OptionsMenuUI.new()
		_options.theme_data = theme_data
		_options.close_requested.connect(_close_options)
		add_child(_options)
	_options.visible = true
	_options.focus_default()
	_panel.visible = false


func _close_options() -> void:
	if _options != null:
		_options.visible = false
	_panel.visible = true
	_restore_focus()


func _restore_focus() -> void:
	if is_instance_valid(_focus_return):
		_focus_return.grab_focus()
	elif _first_button != null:
		_first_button.grab_focus()
	_focus_return = null


func _main_menu() -> void:
	main_menu_pressed.emit()
	get_tree().paused = false
	if main_menu_scene_path != "":
		get_tree().change_scene_to_file(main_menu_scene_path)


func _quit() -> void:
	quit_pressed.emit()
	get_tree().quit()
