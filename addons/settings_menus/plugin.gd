@tool
extends EditorPlugin

const SETTINGS_NAME := "Settings"
const SETTINGS_PATH := "res://addons/settings_menus/settings_manager.gd"


func _enter_tree() -> void:
	add_autoload_singleton(SETTINGS_NAME, SETTINGS_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(SETTINGS_NAME)
