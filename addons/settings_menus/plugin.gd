@tool
extends EditorPlugin

const SETTINGS_NAME := "Settings"
const SETTINGS_PATH := "res://addons/settings_menus/settings_manager.gd"
const CHOOSER_SCRIPT := preload("res://addons/settings_menus/editor/09-settings-menus_chooser_dock.gd")
const DOCK_SCRIPT := preload("res://addons/settings_menus/editor/settings_dock.gd")

var _chooser: Control
var _dock: Control


func _enter_tree() -> void:
	add_autoload_singleton(SETTINGS_NAME, SETTINGS_PATH)

	# The chooser: pick the menus your game needs → where → Apply. Registered first
	# so it's the tab a non-coder lands on. The "Menu Theme" tab below is the author.
	_chooser = CHOOSER_SCRIPT.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chooser)
	# No-code theme editor for designers — tweak menu colors/sizes via UI.
	_dock = DOCK_SCRIPT.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	remove_autoload_singleton(SETTINGS_NAME)
	if _chooser:
		remove_control_from_docks(_chooser)
		_chooser.free()
		_chooser = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null
