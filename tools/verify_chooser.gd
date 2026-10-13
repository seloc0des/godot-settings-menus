extends Node

# Headless test for the Menus chooser's wiring logic (the part behind the Apply
# button). Editor-only calls (get_edited_scene_root/selection) are split out; this
# drives the pure wire()/_ensure_* helpers against a real scene tree and asserts
# the result is baked-in, re-entrant, and doesn't hijack buried sub-scene nodes.
# Run: godot --headless --path . res://tools/verify_chooser.tscn

const CHOOSER := preload("res://addons/settings_menus/editor/09-settings-menus_chooser_dock.gd")
const DEFAULT_THEME := "res://addons/settings_menus/resources/default_menu_theme.tres"

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- menus chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers

	# MAIN — a MainMenuUI under an owned UILayer, with the play path threaded in.
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)
	var made1: Array = dock.wire(root, root, 0, "res://game.tscn")  # Outcome.MAIN
	_assert(made1.size() == 1, "MAIN made exactly one menu node")
	var main = made1[0]
	_assert(main != null and main.get_script() != null and main.get_script().get_global_name() == "MainMenuUI", "MAIN created a MainMenuUI")
	_assert(main.owner == root, "MainMenuUI owned by scene root, bakes into the .tscn")
	_assert(String(main.get("play_scene_path")) == "res://game.tscn", "MAIN threaded the Play scene path through")
	_assert(main.get("theme_data") != null, "MAIN bound the default menu theme")
	# The MainMenuUI is a plain Control, so it must live under an owned UILayer.
	_assert(main.get_parent() is CanvasLayer and main.get_parent().owner == root, "MainMenuUI parented under an owned UILayer")

	# RE-ENTRANT — applying MAIN again reuses the same node, never a second one.
	var made1b: Array = dock.wire(root, root, 0, "res://game2.tscn")  # Outcome.MAIN again
	_assert(made1b[0] == main, "second Apply reused the same MainMenuUI (no duplicate)")
	_assert(String(main.get("play_scene_path")) == "res://game2.tscn", "re-apply updated the Play path in place")
	var main_count := _count_class(root, "MainMenuUI")
	_assert(main_count == 1, "exactly one MainMenuUI after two Applies (got %d)" % main_count)

	# EMPTY play path must NOT clobber an already-set path (only fill, never wipe).
	var made1c: Array = dock.wire(root, root, 0, "")  # Outcome.MAIN, blank path
	_assert(String(made1c[0].get("play_scene_path")) == "res://game2.tscn", "blank Play path leaves an existing one alone")

	# PAUSE — PauseMenuUI extends CanvasLayer, so it parents directly (no wrapper).
	var made2: Array = dock.wire(root, root, 1, "")  # Outcome.PAUSE
	var pause = made2[0]
	_assert(pause != null and pause.get_script().get_global_name() == "PauseMenuUI", "PAUSE created a PauseMenuUI")
	_assert(pause is CanvasLayer, "PauseMenuUI is itself a CanvasLayer (no extra layer stacked)")
	_assert(pause.owner == root, "PauseMenuUI owned by scene root")
	_assert(String(pause.get("pause_action")) == "pause", "PAUSE set the pause_action the menu listens for")

	# ALL — the three menus, re-entrant against what's already there.
	var made3: Array = dock.wire(root, root, 3, "")  # Outcome.ALL
	_assert(made3.size() == 3, "ALL touched three menu nodes")
	_assert(_count_class(root, "MainMenuUI") == 1, "ALL reused the existing MainMenuUI (still one)")
	_assert(_count_class(root, "PauseMenuUI") == 1, "ALL reused the existing PauseMenuUI (still one)")
	_assert(_count_class(root, "OptionsMenuUI") == 1, "ALL added exactly one OptionsMenuUI")
	# All Controls share the single owned UILayer — no layer sprawl.
	_assert(_count_class(root, "UILayer") == 1, "all Controls share one owned UILayer (no layer sprawl)")
	root.free()

	# SCOPE: "under the selected node" — the chooser passes a different parent, but
	# ownership still resolves to root so it serializes. Menu lands under the pick.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var holder := Node.new()
	holder.name = "MenuHolder"
	root2.add_child(holder); holder.owner = root2
	var madeS: Array = dock.wire(root2, holder, 2, "")  # Outcome.OPTIONS under holder
	var opts = madeS[0]
	_assert(opts.owner == root2, "SELECTED scope: OptionsMenuUI still owned by root (serializes)")
	_assert(_is_descendant(holder, opts), "SELECTED scope: menu landed under the selected node")
	root2.free()

	# OWNERSHIP — a menu buried in an instanced sub-scene (owner != root) must NOT be
	# hijacked; Apply should make a fresh menu the scene actually owns. Fresh root so
	# the ONLY MainMenuUI present is the non-owned, buried one.
	var root3 := Node.new()
	get_tree().root.add_child(root3)
	var sub := Node.new()
	root3.add_child(sub); sub.owner = root3
	var buried = load("res://addons/settings_menus/ui/main_menu_ui.gd").new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root3
	var madeF: Array = dock.wire(root3, root3, 0, "res://fresh.tscn")  # Outcome.MAIN
	var fresh = madeF[0]
	_assert(fresh != buried, "did not hijack a MainMenuUI owned by a sub-scene")
	_assert(fresh.owner == root3, "made a fresh MainMenuUI the scene root owns")
	root3.free()

	# PAUSE ACTION — no-code input action, ships in project.godot on a real Apply.
	# Test in memory only (save=false) so we never pollute the pack's project.godot.
	var had := ProjectSettings.has_setting("input/pause")
	if not had:
		dock.ensure_pause_action(false)  # in-memory only, no save
		_assert(ProjectSettings.has_setting("input/pause"), "pause input action registered in memory")
		var cfg: Dictionary = ProjectSettings.get_setting("input/pause")
		var has_esc := false
		for e in cfg["events"]:
			if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
				has_esc = true
		_assert(has_esc, "pause action ships an Escape default")
		ProjectSettings.set_setting("input/pause", null)  # clean up, unsaved
	else:
		_assert(true, "pause action already defined in this project (skipped in-memory add)")

	# Only the editor writes project.godot. A headless save stamps a newer engine
	# floor into it, so save=true out here must still leave the file alone.
	var before_txt := FileAccess.get_file_as_string("res://project.godot")
	var had_cfg: Variant = ProjectSettings.get_setting("input/pause", null)
	var keep: Variant = had_cfg.duplicate(true) if had_cfg is Dictionary else null
	dock.ensure_pause_action(true)
	_assert(FileAccess.get_file_as_string("res://project.godot") == before_txt,
		"ensure_pause_action(true) outside the editor leaves project.godot alone")
	ProjectSettings.set_setting("input/pause", keep)  # put the in-memory copy back

	# SIZED: chooser-made menus have to fill the screen. MainMenuUI never anchors
	# itself and used to land 0x0 in the corner. Built in a 1280x720 viewport so
	# the sizes mean something headless (the root one is tiny).
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	get_tree().root.add_child(vp)
	var root4 := Node2D.new()
	vp.add_child(root4)
	var madeA: Array = dock.wire(root4, root4, 3, "")  # Outcome.ALL
	await get_tree().process_frame
	var m4: Control = madeA[0]
	var o4: Control = madeA[2]
	_assert(m4.anchor_right == 1.0 and m4.anchor_bottom == 1.0 and m4.offset_right == 0.0,
		"MainMenuUI anchored full rect")
	_assert(m4.size == Vector2(1280, 720), "MainMenuUI fills a 1280x720 screen (got %s)" % m4.size)
	_assert(o4.size == Vector2(1280, 720), "OptionsMenuUI fills it too (got %s)" % o4.size)
	_assert(not o4.visible, "ALL: the Options screen starts hidden instead of covering the main menu")
	_assert(madeA[1] is CanvasLayer, "PauseMenuUI stays its own CanvasLayer (it fills the screen itself)")
	vp.free()

	# free(), not queue_free(): we quit on the next line, so a deferred free never
	# runs and the engine reports leaked objects after an all-green result.
	dock.free()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _count_class(root: Node, cls: String) -> int:
	var n := 0
	if _matches(root, cls):
		n += 1
	for c in root.get_children():
		n += _count_class(c, cls)
	return n


func _matches(node: Node, cls: String) -> bool:
	if cls == "UILayer":
		return node.name == "UILayer" and node is CanvasLayer
	var scr: Script = node.get_script()
	if scr != null and scr.get_global_name() == cls:
		return true
	return node.is_class(cls)


func _is_descendant(ancestor: Node, node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
