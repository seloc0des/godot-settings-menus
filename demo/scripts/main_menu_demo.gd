extends Node

# Wires a MainMenuUI to the demo's "game" scene. The MainMenuUI is built in
# code so the demo can ship without a packed scene file referencing every
# class — runs after one project import pass.

const MainMenuUIScript := preload("res://addons/settings_menus/ui/main_menu_ui.gd")
const MenuThemeScript := preload("res://addons/settings_menus/resources/menu_theme.gd")


func _ready() -> void:
	var menu: MainMenuUI = MainMenuUIScript.new()
	var theme: MenuTheme = MenuThemeScript.new()
	theme.game_title = "Settings + Menus"
	theme.game_subtitle = "Free funnel for the CindieForge RPG Toolkit.\nPress Play to drop into a tiny pausable demo room."
	menu.theme_data = theme
	menu.play_scene_path = "res://demo/game_scene.tscn"
	menu.anchor_right = 1
	menu.anchor_bottom = 1
	add_child(menu)
