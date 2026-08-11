@tool
extends Control

# The "chooser" panel: a non-coder picks the menus their game needs, picks WHERE
# they land, and hits Apply — the panel spawns them into their own scene. Nothing
# here is a one-way street: re-pick and Apply again (it updates in place, never
# duplicates), tweak the dropped node in the Inspector, or open the "Menu Theme"
# tab (sibling) to restyle every menu at once. The menus themselves are the full,
# shipping Control scripts — this just wires them in for you.

const MAIN_SCRIPT := "res://addons/settings_menus/ui/main_menu_ui.gd"
const PAUSE_SCRIPT := "res://addons/settings_menus/ui/pause_menu_ui.gd"
const OPTIONS_SCRIPT := "res://addons/settings_menus/ui/options_menu_ui.gd"
const DEFAULT_THEME := "res://addons/settings_menus/resources/default_menu_theme.tres"
const PAUSE_ACTION := "pause"  # PauseMenuUI listens for this by default

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Outcome { MAIN, PAUSE, OPTIONS, ALL }
enum Scope { THIS_SCENE, SELECTED }

var _chosen: int = -1
var _buttons := {}
var _scope: OptionButton
var _play_path: LineEdit
var _status: Label


func _ready() -> void:
	name = "Menus · Setup"
	custom_minimum_size = Vector2(320, 440)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  Pick the menus your game needs"))
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	_add_pick(grid, Outcome.MAIN, "Main menu")
	_add_pick(grid, Outcome.PAUSE, "Pause menu")
	_add_pick(grid, Outcome.OPTIONS, "Options screen")
	_add_pick(grid, Outcome.ALL, "All three")

	root.add_child(_h("2.  Where should they go?"))
	_scope = OptionButton.new()
	_scope.add_item("This scene", Scope.THIS_SCENE)
	_scope.add_item("Under the selected node", Scope.SELECTED)
	root.add_child(_scope)

	# Per-outcome option: the Play scene the Main menu loads. Blank is fine —
	# the buyer can point play_scene_path at their gameplay scene in the Inspector.
	root.add_child(_h("Main menu → Play loads this scene (optional)"))
	_play_path = LineEdit.new()
	_play_path.placeholder_text = "res://your_game.tscn"
	root.add_child(_play_path)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("Customize theme…", _on_customize))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply, tweak the node in the Inspector, or restyle every menu at once in the Menu Theme tab. The Pause menu listens for the \"%s\" input action (added for you if missing)." % PAUSE_ACTION
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)


# ---- pick ----------------------------------------------------------------

func _add_pick(parent: Container, id: int, label: String) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.pressed.connect(_on_pick.bind(id))
	parent.add_child(b)
	_buttons[id] = b


func _on_pick(id: int) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_say("Picked %s. Choose where, then Apply." % _label(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen < 0:
		_say("Pick what you want first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var parent: Node = root
	if _scope.get_selected_id() == Scope.SELECTED:
		var sel := EditorInterface.get_selection().get_selected_nodes()
		if sel.size() > 0 and sel[0] is Node:
			parent = sel[0]
	# Pause menu needs a "pause" input action to toggle on. Register + save it now
	# (real Apply, so it lands in project.godot) if the buyer's picking the pause.
	if _chosen == Outcome.PAUSE or _chosen == Outcome.ALL:
		ensure_pause_action(true)
	var made := wire(root, parent, _chosen, _play_path.text.strip_edges())
	if not made.is_empty():
		_select(made[0])
	_say("Added %s. Tweak it in the Inspector, restyle in the Menu Theme tab, or re-pick here." % _label(_chosen), OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses the menu nodes already in the scene rather than duplicating.
# Returns the nodes it touched (first = the one to select/focus).

func wire(root: Node, parent: Node, outcome: int, play_path: String) -> Array:
	var made: Array = []
	match outcome:
		Outcome.MAIN:
			made.append(_ensure_main(root, parent, play_path))
		Outcome.PAUSE:
			made.append(_ensure_pause(root, parent))
		Outcome.OPTIONS:
			made.append(_ensure_options(root, parent))
		Outcome.ALL:
			made.append(_ensure_main(root, parent, play_path))
			made.append(_ensure_pause(root, parent))
			made.append(_ensure_options(root, parent))
	return made


# MainMenuUI + OptionsMenuUI are plain Controls, so they live under an owned
# CanvasLayer. PauseMenuUI already IS a CanvasLayer — parent it directly so we
# don't stack two layers.

func _ensure_main(root: Node, parent: Node, play_path: String) -> Node:
	var layer := _find_ui_layer(root, parent)
	var ui := _ensure(root, layer, "MainMenuUI", MAIN_SCRIPT)
	if play_path != "":
		ui.set("play_scene_path", play_path)
	_bind_theme(ui)
	return ui


func _ensure_options(root: Node, parent: Node) -> Node:
	var layer := _find_ui_layer(root, parent)
	var ui := _ensure(root, layer, "OptionsMenuUI", OPTIONS_SCRIPT)
	_bind_theme(ui)
	return ui


func _ensure_pause(root: Node, parent: Node) -> Node:
	# PauseMenuUI extends CanvasLayer — no wrapper layer.
	var ui := _ensure(root, parent, "PauseMenuUI", PAUSE_SCRIPT)
	ui.set("pause_action", PAUSE_ACTION)
	_bind_theme(ui)
	return ui


# Ensure a "pause" input action exists so the pause menu works out of the box.
# Pure + safe to call from a test: pass save=false to only touch the in-memory
# ProjectSettings. On a real Apply the caller saves.
func ensure_pause_action(save := true) -> void:
	var key := "input/" + PAUSE_ACTION
	if ProjectSettings.has_setting(key):
		return
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	ProjectSettings.set_setting(key, {"deadzone": 0.5, "events": [esc]})
	if save:
		ProjectSettings.save()


# ---- customize -----------------------------------------------------------

func _on_customize() -> void:
	# Hand off to the pack's authoring dock — the "Menu Theme" sibling tab owns
	# the full styling (colors, fonts, background). We don't duplicate its CRUD.
	_say("Open the \"Menu Theme\" tab to restyle every menu at once (colors, fonts, title). Assign your theme to each menu's Theme Data in the Inspector.", OK_COLOR)


# ---- helpers -------------------------------------------------------------

func _ensure(root: Node, parent: Node, cls: String, script_path: String) -> Node:
	var found := _find(root, cls)
	if found != null:
		return found  # re-entrant: reuse the existing one, never duplicate
	var n: Node = load(script_path).new()
	parent.add_child(n)
	n.owner = root
	n.name = cls
	return n


# Find (or create) a CanvasLayer this scene owns, to hold the Control menus.
# Copied from save-load's _find_ui_layer: only reuse a layer the ROOT owns —
# one inside an instanced sub-scene won't serialize our children.
func _find_ui_layer(root: Node, fallback_parent: Node) -> Node:
	var existing := _find(root, "UILayer")
	if existing != null and existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	fallback_parent.add_child(layer)
	layer.owner = root
	return layer


# Re-entrancy search, scoped to nodes THIS scene owns. A menu inside an instanced
# child scene (owner != root) is skipped — updating it wouldn't serialize into the
# buyer's scene, so we'd silently no-op. (Same trap the save dock's CanvasLayer
# search had.)
func _find(root: Node, cls: String) -> Node:
	return _find_owned(root, root, cls)


func _find_owned(node: Node, root: Node, cls: String) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, cls):
		return node
	for c in node.get_children():
		var f := _find_owned(c, root, cls)
		if f != null:
			return f
	return null


func _is_cls(node: Node, cls: String) -> bool:
	if node.name == cls and cls == "UILayer":
		return node is CanvasLayer  # our helper layer is identified by name
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


func _bind_theme(ui: Node) -> void:
	# Only fill an empty slot — never clobber a theme the buyer already assigned.
	if ui.get("theme_data") == null:
		var t := load(DEFAULT_THEME)
		if t != null:
			ui.set("theme_data", t)


func _select(n: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _label(id: int) -> String:
	match id:
		Outcome.MAIN: return "a Main menu"
		Outcome.PAUSE: return "a Pause menu"
		Outcome.OPTIONS: return "an Options screen"
		Outcome.ALL: return "all three menus"
	return "menus"


func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _say(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text
