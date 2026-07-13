extends Node

# Tiny "game" scene the demo's main menu transitions into. A movable colored
# square, a wallpaper background, and a PauseMenuUI listening for the "pause"
# action (Esc by default). Demonstrates the menus working in context.

const PauseMenuUIScript := preload("res://addons/settings_menus/ui/pause_menu_ui.gd")
const MenuThemeScript := preload("res://addons/settings_menus/resources/menu_theme.gd")

var _player: ColorRect
var _hint: Label
var _fps_label: Label


func _ready() -> void:
	# Background.
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.16)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	add_child(bg)

	# Player square.
	_player = ColorRect.new()
	_player.color = Color(0.45, 0.70, 0.95)
	_player.size = Vector2(48, 48)
	_player.position = Vector2(580, 340)
	add_child(_player)

	# Hint label.
	_hint = Label.new()
	_hint.text = "Move: A / D (rebindable). Jump: Space (rebindable). Pause: Esc.\nOpen Options inside Pause and try Audio, Display, Controls, Accessibility."
	_hint.position = Vector2(16, 16)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	add_child(_hint)

	# FPS label (toggled via Settings).
	_fps_label = Label.new()
	_fps_label.position = Vector2(16, 80)
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	add_child(_fps_label)

	# Pause overlay.
	var pause_ui: PauseMenuUI = PauseMenuUIScript.new()
	var theme: MenuTheme = MenuThemeScript.new()
	pause_ui.theme_data = theme
	pause_ui.main_menu_scene_path = "res://demo/main_menu_scene.tscn"
	add_child(pause_ui)


func _process(delta: float) -> void:
	if _player == null:
		return
	var dx := 0.0
	if Input.is_action_pressed("move_left"):
		dx -= 1.0
	if Input.is_action_pressed("move_right"):
		dx += 1.0
	_player.position.x = clampf(_player.position.x + dx * 220.0 * delta, 0.0, 1180.0 - _player.size.x)
	if Input.is_action_just_pressed("jump"):
		_player.color = Color(randf_range(0.3, 1.0), randf_range(0.3, 1.0), randf_range(0.3, 1.0))

	# FPS visibility from settings.
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		var visible: bool = bool(settings.get_value("display.fps_visible", false))
		_fps_label.visible = visible
		if visible:
			_fps_label.text = "FPS: %d" % int(Engine.get_frames_per_second())
