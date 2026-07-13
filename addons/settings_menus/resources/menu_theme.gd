class_name MenuTheme
extends Resource

# Visual theme for the Settings + Menus template. Drop one into a
# MainMenuUI / PauseMenuUI / OptionsMenuUI / CreditsUI to recolor every menu
# in one swap. Separate from Godot's stock Theme — this is the high-level
# palette + a few layout knobs.

@export_group("Palette")
@export var bg_color: Color = Color(0.06, 0.07, 0.10, 1.0)
@export var panel_bg: Color = Color(0.10, 0.12, 0.16, 0.95)
@export var panel_border: Color = Color(0.20, 0.22, 0.28, 1.0)
@export var accent: Color = Color(0.45, 0.70, 0.95, 1.0)
@export var accent_hover: Color = Color(0.60, 0.80, 1.0, 1.0)
@export var text: Color = Color(0.92, 0.94, 0.97, 1.0)
@export var text_dim: Color = Color(0.65, 0.68, 0.74, 1.0)
@export var button_bg: Color = Color(0.14, 0.16, 0.20, 1.0)
@export var button_bg_hover: Color = Color(0.20, 0.24, 0.32, 1.0)
@export var button_bg_pressed: Color = Color(0.10, 0.12, 0.15, 1.0)
@export var slider_track: Color = Color(0.18, 0.20, 0.24, 1.0)
@export var slider_fill: Color = Color(0.45, 0.70, 0.95, 1.0)

@export_group("Typography")
@export var title_font_size: int = 48
@export var heading_font_size: int = 22
@export var body_font_size: int = 14
@export var button_font_size: int = 16

@export_group("Layout")
@export var panel_corner_radius: int = 6
@export var panel_padding: int = 16
@export var menu_max_width: int = 480

@export_group("Branding")
@export var game_title: String = "Your Game Here"
@export var game_subtitle: String = "A demo built on the CindieForge Settings + Menus template."
@export var background_texture: Texture2D
@export var logo_texture: Texture2D


func panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = panel_bg
	sb.border_color = panel_border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(panel_corner_radius)
	sb.set_content_margin_all(panel_padding)
	return sb


func button_normal_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = button_bg
	sb.set_corner_radius_all(panel_corner_radius - 2)
	sb.set_content_margin_all(8)
	return sb


func button_hover_stylebox() -> StyleBoxFlat:
	var sb := button_normal_stylebox()
	sb.bg_color = button_bg_hover
	sb.border_color = accent
	sb.set_border_width_all(1)
	return sb


func button_pressed_stylebox() -> StyleBoxFlat:
	var sb := button_normal_stylebox()
	sb.bg_color = button_bg_pressed
	return sb


func apply_to_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", button_normal_stylebox())
	b.add_theme_stylebox_override("hover", button_hover_stylebox())
	b.add_theme_stylebox_override("pressed", button_pressed_stylebox())
	b.add_theme_stylebox_override("focus", button_hover_stylebox())
	b.add_theme_color_override("font_color", text)
	b.add_theme_color_override("font_hover_color", accent_hover)
	b.add_theme_color_override("font_pressed_color", text_dim)
	b.add_theme_font_size_override("font_size", button_font_size)
