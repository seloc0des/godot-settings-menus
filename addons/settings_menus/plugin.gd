@tool
extends EditorPlugin

const SETTINGS_NAME := "Settings"
const SETTINGS_PATH := "res://addons/settings_menus/settings_manager.gd"
const META_SECTION := "settings_menus"
const META_ADDED := "added_autoload"
const CHOOSER_SCRIPT := preload("res://addons/settings_menus/editor/09-settings-menus_chooser_dock.gd")
const DOCK_SCRIPT := preload("res://addons/settings_menus/editor/settings_dock.gd")

var _chooser: Control
var _dock: Control


func _enable_plugin() -> void:
	_ensure_autoload()


# Only take away a Settings autoload this plugin put there. A project that declares
# it itself (the Complete bundle does) keeps it, and closing the editor never touches it.
func _disable_plugin() -> void:
	var es := EditorInterface.get_editor_settings()
	if es.get_project_metadata(META_SECTION, META_ADDED, false) and ProjectSettings.has_setting("autoload/" + SETTINGS_NAME):
		remove_autoload_singleton(SETTINGS_NAME)
	es.set_project_metadata(META_SECTION, META_ADDED, false)


func _enter_tree() -> void:
	_ensure_autoload()

	# The chooser: pick the menus your game needs → where → Apply. Registered first
	# so it's the tab a non-coder lands on. The "Menu Theme" tab below is the author.
	_chooser = CHOOSER_SCRIPT.new()
	# Named here, not only in the dock's _ready: Godot 4.5 reads the tab title
	# the moment the dock is added, before _ready has run.
	_chooser.name = "Menus · Setup"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chooser)
	# No-code theme editor for designers — tweak menu colors/sizes via UI.
	_dock = DOCK_SCRIPT.new()
	_dock.name = "Menu Theme"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _chooser:
		remove_control_from_docks(_chooser)
		_chooser.free()
		_chooser = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null


func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + SETTINGS_NAME):
		add_autoload_singleton(SETTINGS_NAME, SETTINGS_PATH)
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_ADDED, true)
