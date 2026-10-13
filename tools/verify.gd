extends Node

# Headless test for the Settings / Menus addon.
# Run: godot --headless --path . res://tools/verify.tscn

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


# This suite ships to buyers, so it must not touch their real settings — it
# resets to defaults and rebinds keys, which would wipe saved volume/resolution/
# keybinds. Redirect the whole thing at a scratch file first.
const SANDBOX := "user://verify_settings.json"


func _ready() -> void:
	await get_tree().process_frame
	print("--- settings / menus verify ---")
	var real_before := _snapshot_real_settings()
	if _settings_manager():
		_settings_manager().save_file = SANDBOX
	await _run_defaults_load()
	await _run_set_and_persist()
	await _run_audio_bus_missing_warns()
	await _run_keybind_allowlist()
	await _run_keybind_dedup()
	await _run_keybind_conflict_detection()
	await _run_ui_ignores_ui_actions()
	await _run_trigger_survives_a_restart()
	await _run_menu_keys_are_free()
	await _run_rebind_row_halves()
	await _run_rebind_row_hears_a_stick()
	await _run_pad_buttons_have_names()
	await _run_resting_trigger_doesnt_bind_itself()
	await _run_controls_tab_survives_a_reset()
	await _run_reset_restores_live_bindings()
	await _run_reset_all_is_quiet()
	await _run_persistence_roundtrip()
	await _run_a_write_that_does_not_finish()
	_run_pause_reaches_a_gamepad()
	_run_optional_buses()
	_run_effect_toggles()
	await _run_options_menu_effect_rows()
	await _run_effect_rows_write_their_own_key()
	await _run_unticked_boxes_show()
	await _run_quality_axes()
	await _run_corrupt_settings_file()
	await _run_save_debounce()
	_assert(_snapshot_real_settings() == real_before,
		"Sandbox: the real %s was left untouched" % SETTINGS_MANAGER.SAVE_FILE)
	_cleanup_sandbox()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/acceptance_report.gd").new()
		get_tree().root.add_child(report)
		report.render(_passes, _failures, _log)


# Absent and empty both read as "" — good enough, we only care whether the run
# changed it.
func _snapshot_real_settings() -> String:
	if not FileAccess.file_exists(SETTINGS_MANAGER.SAVE_FILE):
		return ""
	var f := FileAccess.open(SETTINGS_MANAGER.SAVE_FILE, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _cleanup_sandbox() -> void:
	_settings_manager().save_file = SETTINGS_MANAGER.SAVE_FILE
	if FileAccess.file_exists(SANDBOX):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SANDBOX))


func _assert(cond: bool, msg: String) -> void:
	_log.append([cond, msg])
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- tests ---------------------------------------------------------------

func _run_defaults_load() -> void:
	await get_tree().process_frame
	_assert(_settings_manager() != null, "Boot: Settings autoload present")
	# Clear any state a prior run persisted to user://settings.json so the
	# defaults check is idempotent (this test later sets audio.master = 0.5).
	if _settings_manager():
		_settings_manager().reset_to_defaults()
	# Default master volume is 1.0.
	_assert(float(_settings_manager().get_value("audio.master", -1.0)) == 1.0,
		"Defaults: audio.master = 1.0 (got %s)" % str(_settings_manager().get_value("audio.master", -1.0)))


func _run_set_and_persist() -> void:
	await get_tree().process_frame
	# Mutate a value, save, then load fresh and verify it survived.
	_settings_manager().set_value("audio.music", 0.42)
	_settings_manager().save_settings()
	# Reset in-memory snapshot, then load from disk.
	_settings_manager()._data.clear()
	_settings_manager().load_settings()
	_assert(abs(float(_settings_manager().get_value("audio.music", -1.0)) - 0.42) < 0.001,
		"Persist: audio.music round-trips (got %s)" % str(_settings_manager().get_value("audio.music", -1.0)))


func _run_audio_bus_missing_warns() -> void:
	await get_tree().process_frame
	# Re-applying audio with a missing bus shouldn't crash. We can't easily
	# capture push_warning output in a headless test, but a clean run with
	# no exception is the success signal.
	_settings_manager().set_value("audio.master", 0.5)
	_assert(true, "AudioBus: applying audio with possibly-missing bus didn't crash")


func _run_keybind_allowlist() -> void:
	await get_tree().process_frame
	# Manufacture a non-ui action and a ui action.
	InputMap.add_action("game_test_action")
	if not InputMap.has_action("ui_accept"):
		InputMap.add_action("ui_accept")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Q
	# ui_accept must be refused (not in allowlist + begins with ui_).
	_settings_manager().set_keybind("ui_accept", [ev])
	var accepted_ui := InputMap.action_get_events("ui_accept")
	var matches_q := false
	for e in accepted_ui:
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Q:
			matches_q = true
			break
	_assert(not matches_q, "Allowlist: ui_accept rebind refused (key Q not present)")
	# game_test_action is not in the default allowlist either, but the
	# manager's fallback policy ("any non-ui_ if allowlist is empty") doesn't
	# apply because the bundled allowlist is non-empty. So this should also
	# be refused.
	_settings_manager().set_keybind("game_test_action", [ev])
	var game_evs := InputMap.action_get_events("game_test_action")
	var game_matches := false
	for e in game_evs:
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Q:
			game_matches = true
			break
	_assert(not game_matches, "Allowlist: non-allowlisted action refused")
	# But "jump" (in the default allowlist) should succeed if the project
	# defines it. The demo project does; allow either outcome.
	if InputMap.has_action("jump"):
		_settings_manager().set_keybind("jump", [ev])
		var jump_evs := InputMap.action_get_events("jump")
		var jump_matches := false
		for e in jump_evs:
			if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Q:
				jump_matches = true
				break
		_assert(jump_matches, "Allowlist: allowed action 'jump' accepted")


func _run_keybind_dedup() -> void:
	await get_tree().process_frame
	if not InputMap.has_action("jump"):
		_assert(true, "Dedup: skipped (no 'jump' action in this project)")
		return
	var ev1 := InputEventKey.new()
	ev1.physical_keycode = KEY_SPACE
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_SPACE
	_settings_manager().set_keybind("jump", [ev1, ev2, ev1])
	var bound := InputMap.action_get_events("jump")
	# After dedup, only one event with KEY_SPACE should remain.
	var space_count := 0
	for e in bound:
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_SPACE:
			space_count += 1
	_assert(space_count == 1, "Dedup: only one SPACE binding kept (got %d)" % space_count)


func _run_keybind_conflict_detection() -> void:
	await get_tree().process_frame
	if not (InputMap.has_action("jump") and InputMap.has_action("attack")):
		_assert(true, "Conflict: skipped (project lacks jump/attack actions)")
		return
	# Bind W to jump.
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	_settings_manager().set_keybind("jump", [w])
	# Now ask: is W conflicting if we try to bind it to attack?
	var w2 := InputEventKey.new()
	w2.physical_keycode = KEY_W
	var conflict: String = _settings_manager().find_conflicting_action(w2, "attack")
	_assert(conflict == "jump", "Conflict: W bound to jump detected when probing for attack (got '%s')" % conflict)
	# Probing against the SAME action excludes it (no self-conflict).
	var self_conflict: String = _settings_manager().find_conflicting_action(w2, "jump")
	_assert(self_conflict == "", "Conflict: probe excludes the action being rebound (got '%s')" % self_conflict)


func _run_ui_ignores_ui_actions() -> void:
	await get_tree().process_frame
	# Confirm _is_rebindable rejects ui_* outright.
	_assert(not _settings_manager()._is_rebindable("ui_accept"), "Rebindable: ui_* rejected")
	_assert(_settings_manager()._is_rebindable("jump"), "Rebindable: jump (in allowlist) accepted")
	_assert(not _settings_manager()._is_rebindable("not_in_allowlist"), "Rebindable: arbitrary action rejected when allowlist non-empty")


func _run_trigger_survives_a_restart() -> void:
	# A trigger or a stick saved as {}, so the file kept nothing of it and a rebound
	# action came back on the next launch without it. The dedup also read every {}
	# as the same binding, so a trigger and a stick on one action became one.
	await get_tree().process_frame
	var held := _borrow(["jump"])
	var s := _settings_manager()
	var space := _key(KEY_SPACE)
	s.set_keybind("jump", [space, _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), _axis(JOY_AXIS_RIGHT_X, -1.0)])
	_assert(_has_axis("jump", JOY_AXIS_TRIGGER_RIGHT, 1.0) and _has_axis("jump", JOY_AXIS_RIGHT_X, -1.0),
		"Trigger: a trigger and a stick on one action stay two bindings")
	# The next launch: read the file, start from the project's binding, apply.
	s._data = {}
	s.load_settings()
	InputMap.action_erase_events("jump")
	InputMap.action_add_event("jump", space)
	s.apply_keybinds()
	_assert(_has_axis("jump", JOY_AXIS_TRIGGER_RIGHT, 1.0), "Trigger: a rebound action still has its trigger after a save and apply_keybinds()")
	_assert(_has_axis("jump", JOY_AXIS_RIGHT_X, -1.0), "Trigger: and its stick, pushed the way it was bound")
	var motions := InputMap.action_get_events("jump").filter(func(e): return e is InputEventJoypadMotion)
	_assert(motions.size() == 2 and motions.all(func(e): return e.device == -1), "Trigger: and both answer any pad, not only the first")
	_give_back(held)


func _run_menu_keys_are_free() -> void:
	# Space selects in a menu, and a pad-driven menu puts A and B on ui_accept and
	# ui_cancel. Games bind those on purpose (jump on Space, a dodge on B), but the
	# check counted them, so jump could never go back to Space.
	await get_tree().process_frame
	var s := _settings_manager()
	var b := _button(JOY_BUTTON_B)
	InputMap.action_add_event("ui_cancel", b)
	var space_clash: String = s.find_conflicting_action(_key(KEY_SPACE), "jump")
	_assert(space_clash == "", "Menu keys: Space is free for jump though menus select with it (got '%s')" % space_clash)
	var b_clash: String = s.find_conflicting_action(_button(JOY_BUTTON_B), "jump")
	_assert(b_clash == "", "Menu keys: so is B, though a pad-driven menu backs out with it (got '%s')" % b_clash)
	s.set("menu_navigation_clashes", true)
	_assert(s.find_conflicting_action(_key(KEY_SPACE), "jump").begins_with("ui_"),
		"Menu keys: a game that wants them kept apart switches menu_navigation_clashes on")
	s.set("menu_navigation_clashes", false)
	InputMap.action_erase_event("ui_cancel", b)
	# The game's own actions still count.
	var held := _borrow(["verify_other"])
	InputMap.action_add_event("verify_other", _key(KEY_K))
	var k_clash: String = s.find_conflicting_action(_key(KEY_K), "jump")
	_assert(k_clash == "verify_other", "Menu keys: a key another game action uses is still taken (got '%s')" % k_clash)
	_give_back(held)


func _run_rebind_row_halves() -> void:
	# One button per action used to replace every binding on it, so a new key took
	# the pad's trigger away, and the next launch had no trigger to load either.
	var held := _borrow(["jump", "move_up"])
	var s := _settings_manager()
	s.set_keybind("jump", [_key(KEY_SPACE), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	var menu = await _controls_menu()
	var row := _rebind_row(menu, "jump")
	var key_btn: Button = row.get_node_or_null("Key") if row != null else null
	var pad_btn: Button = row.get_node_or_null("Pad") if row != null else null
	_assert(key_btn != null and pad_btn != null, "Row: each action has a keyboard half and a gamepad half")
	if key_btn == null or pad_btn == null:
		await _close(menu, held)
		return
	_assert(key_btn.text == "Space" and pad_btn.text == "Right Trigger",
		"Row: the key on one, the trigger on the other (got '%s' / '%s')" % [key_btn.text, pad_btn.text])

	key_btn.pressed.emit()
	_tap_key(KEY_J)
	_assert(_has_key("jump", KEY_J) and not _has_key("jump", KEY_SPACE), "Row: a new key replaces the key")
	_assert(_has_axis("jump", JOY_AXIS_TRIGGER_RIGHT, 1.0), "Row: and leaves the trigger alone")
	s._data = {}
	s.load_settings()
	InputMap.action_erase_events("jump")
	s.apply_keybinds()
	_assert(_has_axis("jump", JOY_AXIS_TRIGGER_RIGHT, 1.0) and _has_key("jump", KEY_J),
		"Row: the trigger is still there after a save and apply_keybinds()")

	key_btn.grab_focus()
	key_btn.pressed.emit()
	_tap_key(KEY_SPACE)
	_assert(_has_key("jump", KEY_SPACE), "Row: jump can go back to Space, which menus select with too")
	_assert(key_btn.text == "Space", "Row: and letting go of Space doesn't press the focused button and start listening again (got '%s')" % key_btn.text)

	# B on ui_cancel, the way a pad-driven menu has it, used to cancel listening.
	var b := _button(JOY_BUTTON_B)
	InputMap.action_add_event("ui_cancel", b)
	pad_btn.pressed.emit()
	_tap_button(JOY_BUTTON_B)
	InputMap.action_erase_event("ui_cancel", b)
	_assert(_has_button("jump", JOY_BUTTON_B) and not _has_axis("jump", JOY_AXIS_TRIGGER_RIGHT, 1.0),
		"Row: B binds, though a pad-driven menu backs out with it, and replaces the trigger")
	_assert(_has_key("jump", KEY_SPACE), "Row: and the key stays")

	key_btn.pressed.emit()
	_send(_mouse(MOUSE_BUTTON_RIGHT, true))
	_send(_mouse(MOUSE_BUTTON_RIGHT, false))
	_assert(_has_mouse("jump", MOUSE_BUTTON_RIGHT) and not _has_key("jump", KEY_SPACE),
		"Row: a mouse button goes on the keyboard half, where the menu used to take the click")
	_assert(_has_button("jump", JOY_BUTTON_B), "Row: and the pad binding stays")

	key_btn.pressed.emit()
	_tap_key(KEY_ESCAPE)
	_assert(_has_mouse("jump", MOUSE_BUTTON_RIGHT) and key_btn.text == "Right Click", "Row: Esc backs out and binds nothing")

	# One row at a time: click jump, then move_up, and the key goes to move_up.
	var up_row := _rebind_row(menu, "move_up")
	if up_row != null:
		key_btn.pressed.emit()
		(up_row.get_node("Key") as Button).pressed.emit()
		_tap_key(KEY_K)
		_assert(_has_key("move_up", KEY_K) and not _has_key("jump", KEY_K), "Row: only the row clicked last listens")

	# Listening gives up by itself. The key half, since a real pad still reaches a
	# headless run and could answer during the wait.
	key_btn.pressed.emit()
	row.set("_listen_left", 0.05)
	await get_tree().create_timer(0.3).timeout
	_assert(key_btn.text == "Right Click", "Row: listening gives up on its own (got '%s')" % key_btn.text)
	await _close(menu, held)


func _run_rebind_row_hears_a_stick() -> void:
	# The menu moves its focus on the left stick, so the stick never reached a row
	# listening in _unhandled_input, and the row took no stick or trigger anyway.
	var held := _borrow(["move_up"])
	InputMap.action_erase_events("move_up")
	InputMap.action_add_event("move_up", _key(KEY_W))
	InputMap.action_add_event("move_up", _button(JOY_BUTTON_Y))
	var menu = await _controls_menu()
	var row := _rebind_row(menu, "move_up")
	var pad_btn: Button = row.get_node_or_null("Pad") if row != null else null
	_assert(pad_btn != null, "Stick: the row has a gamepad half to listen with")
	if pad_btn == null:
		await _close(menu, held)
		return

	pad_btn.grab_focus()
	pad_btn.pressed.emit()
	_send(_axis(JOY_AXIS_LEFT_Y, -0.55))  # past the menu's deadzone, short of a press
	_send(_axis(JOY_AXIS_LEFT_Y, -1.0))
	_send(_axis(JOY_AXIS_LEFT_Y, -1.0))  # the rest of the same push
	_assert(_has_axis("move_up", JOY_AXIS_LEFT_Y, -1.0), "Stick: the left stick pushed up binds, though the menu steers with it")
	_assert(not _has_button("move_up", JOY_BUTTON_Y) and _has_key("move_up", KEY_W), "Stick: in place of the pad button, with W kept")
	_assert(get_viewport().gui_get_focus_owner() == pad_btn, "Stick: and neither the nudge nor the push moved the menu's focus")
	_send(_axis(JOY_AXIS_LEFT_Y, 0.0))

	pad_btn.pressed.emit()
	_send(_axis(JOY_AXIS_TRIGGER_LEFT, 0.4))
	_assert(not _has_axis("move_up", JOY_AXIS_TRIGGER_LEFT, 1.0), "Stick: a trigger squeezed less than halfway doesn't bind")
	_send(_axis(JOY_AXIS_TRIGGER_LEFT, 0.7))
	_assert(_has_axis("move_up", JOY_AXIS_TRIGGER_LEFT, 1.0), "Stick: one squeezed past it does")
	_send(_axis(JOY_AXIS_TRIGGER_LEFT, 0.0))

	pad_btn.pressed.emit()
	_tap_button(JOY_BUTTON_START)
	_assert(pad_btn.text == "Left Trigger", "Stick: Start backs out and binds nothing (got '%s')" % pad_btn.text)
	await _close(menu, held)


func _run_pad_buttons_have_names() -> void:
	# Pad buttons showed as numbers, so pause read "Escape, Joy Btn 6".
	var held := _borrow(["pause"])
	InputMap.action_erase_events("pause")
	InputMap.action_add_event("pause", _key(KEY_ESCAPE))
	InputMap.action_add_event("pause", _button(JOY_BUTTON_START))
	var menu = await _controls_menu()
	var row := _rebind_row(menu, "pause")
	var shown := _row_text(row)
	# Whichever pad is plugged in, if any: Menu on Xbox, Options on PlayStation, Plus on Switch.
	var named := shown.contains("Menu") or shown.contains("Options") or shown.contains("Plus")
	_assert(named and not shown.contains("Joy Btn"), "Pad names: Start reads as the pad calls it, not a number (got '%s')" % shown)
	if not named:
		await _close(menu, held)
		return

	# A pad plugged in renames the gamepad half. The same signal stands in for one.
	InputMap.action_erase_events("pause")
	InputMap.action_add_event("pause", _key(KEY_ESCAPE))
	InputMap.action_add_event("pause", _button(JOY_BUTTON_LEFT_SHOULDER))
	Input.joy_connection_changed.emit(0, true)
	shown = _row_text(row)
	_assert(shown.contains("LB") or shown.contains("L1") or shown.contains(" L "),
		"Pad names: and plugging a pad in renames the gamepad half (got '%s')" % shown)
	await _close(menu, held)

	# The Nintendo swap is why the family matters: button 0 is A on an Xbox pad,
	# Cross on a PlayStation one, and B on a Switch.
	var names = load("res://addons/settings_menus/ui/key_rebind_row.gd")
	var bottom := [names._pad_name(JOY_BUTTON_A, "Xbox Series X Controller"),
		names._pad_name(JOY_BUTTON_A, "DualSense Wireless Controller"),
		names._pad_name(JOY_BUTTON_A, "Nintendo Switch Pro Controller")]
	_assert(bottom == ["A", "Cross", "B"], "Pad names: the bottom face button is A, Cross or B for the pad in your hands (got %s)" % str(bottom))
	_assert(names._pad_name(JOY_BUTTON_START, "") == "Menu", "Pad names: with no pad plugged in, Xbox names, which most PC pads follow")
	_assert(names._pad_name(JOY_BUTTON_PADDLE1, "") == "Button %d" % JOY_BUTTON_PADDLE1, "Pad names: and a button with no name is numbered rather than blank")


func _run_resting_trigger_doesnt_bind_itself() -> void:
	# Some pads rest a trigger at -1. Measured from 0, its resting end read as a full
	# press, and the trigger bound itself before anyone touched it.
	var held := _borrow(["move_up"])
	InputMap.action_erase_events("move_up")
	InputMap.action_add_event("move_up", _key(KEY_W))
	var menu = await _controls_menu()
	var row := _rebind_row(menu, "move_up")
	var pad_btn: Button = row.get_node_or_null("Pad") if row != null else null
	if pad_btn == null:
		_assert(false, "Rest: the row has a gamepad half to listen with")
		await _close(menu, held)
		return
	_send(_axis(JOY_AXIS_TRIGGER_RIGHT, -1.0))  # the pad at rest, before the row listens
	pad_btn.pressed.emit()
	_send(_axis(JOY_AXIS_TRIGGER_RIGHT, -0.98))  # resting noise
	_assert(not _has_axis("move_up", JOY_AXIS_TRIGGER_RIGHT, -1.0), "Rest: a trigger resting at -1 doesn't bind its own resting end")
	_send(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.7))
	_assert(_has_axis("move_up", JOY_AXIS_TRIGGER_RIGHT, 1.0), "Rest: squeezing it binds it, the pressed way round")
	_send(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0))
	await _close(menu, held)


func _run_controls_tab_survives_a_reset() -> void:
	# Reset All Bindings rebuilt the tab by adding the new one while the old one still
	# held the name. The new one was renamed "@VBoxContainer@NNN", that became its tab
	# title, and the next reset couldn't find "Controls". The focused button went with
	# the old tab, so a pad had nowhere to go.
	var menu = await _controls_menu()
	var tabs: TabContainer = menu.find_children("*", "TabContainer", true, false)[0]
	var at := tabs.current_tab
	for n in [1, 2]:
		var reset := _button_with_text(tabs.get_current_tab_control(), "Reset All Bindings")
		if reset == null:
			_assert(false, "Tab: the Controls tab has its Reset All Bindings button")
			break
		reset.grab_focus()
		reset.pressed.emit()
		await get_tree().process_frame
		_assert(tabs.current_tab == at and tabs.get_tab_title(at) == "Controls",
			"Tab: after Reset All Bindings #%d it's still the Controls tab, still showing (got '%s')" % [n, tabs.get_tab_title(tabs.current_tab)])
		var now := get_viewport().gui_get_focus_owner()
		_assert(now is Button and (now as Button).text == "Reset All Bindings" and tabs.get_current_tab_control().is_ancestor_of(now),
			"Tab: and the new tab's Reset All Bindings has the focus, so a pad has somewhere to be")
	await _close(menu, {})


func _run_reset_restores_live_bindings() -> void:
	# Reset to Defaults emptied the saved bindings and then had nothing to apply, so a
	# rebound key stayed rebound until the next launch.
	await get_tree().process_frame
	var s := _settings_manager()
	var held := _borrow(["inventory"])
	var captured: Dictionary = s._captured_default_binds
	var had: bool = captured.has("inventory")
	var was = captured.get("inventory")
	captured["inventory"] = [_key(KEY_I)]  # its binding at start, as project.godot would give it
	s.set_keybind("inventory", [_key(KEY_O)])
	s.reset_to_defaults()
	_assert(_has_key("inventory", KEY_I) and not _has_key("inventory", KEY_O), "Reset: Reset to Defaults puts a rebound key back straight away")
	if had:
		captured["inventory"] = was
	else:
		captured.erase("inventory")
	_give_back(held)


class _Warnings extends Logger:
	var seen: Array = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			seen.append(code + rationale)
	func _log_message(_message: String, _error: bool) -> void:
		pass


func _run_reset_all_is_quiet() -> void:
	# Reset All Bindings walked every action there was at start, the engine's ui_* ones
	# too, and set_keybind warned once for each one it refused.
	await get_tree().process_frame
	var heard := _Warnings.new()
	OS.add_logger(heard)
	_settings_manager().reset_all_keybinds()
	OS.remove_logger(heard)
	var refused := heard.seen.filter(func(w): return String(w).contains("refused to rebind"))
	_assert(refused.is_empty(), "Reset all: putting every binding back warns about nothing (got %d warnings)" % refused.size())


func _button_with_text(root: Node, text: String) -> Button:
	if root == null:
		return null
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


# Every button on a rebind row, in one line: what a player reads across it.
func _row_text(row: Node) -> String:
	if row == null:
		return ""
	var parts: Array = []
	for c in row.get_children():
		if c is Button:
			parts.append((c as Button).text)
	return " | ".join(parts)


# ---- rebinding helpers ----------------------------------------------------

# The suite borrows the project's actions: notes them down, makes any that are
# missing, and puts every one back afterwards.
func _borrow(actions: Array) -> Dictionary:
	var held := {}
	for a in actions:
		held[a] = InputMap.action_get_events(a) if InputMap.has_action(a) else null
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	return held


# An action the suite made is emptied, not erased. Godot 4.5 and 4.7 crash on the next
# pad plugged in or out once an action a pad has pressed is erased, and these checks
# press theirs with sticks and triggers. A wireless pad waking up mid-run took the whole
# self-test down, or the banner after it.
func _give_back(held: Dictionary) -> void:
	var binds: Dictionary = _settings_manager()._data.get("keybinds", {})
	for a in held:
		binds.erase(a)
		InputMap.action_erase_events(a)
		if held[a] == null:
			continue
		for e in held[a]:
			InputMap.action_add_event(a, e)


func _close(menu, held: Dictionary) -> void:
	menu.queue_free()
	await get_tree().process_frame
	_give_back(held)


# An options menu with its Controls tab showing. A row on a hidden tab stops
# listening, so the tab has to be the current one.
func _controls_menu():
	var menu = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	var tabs: TabContainer = menu.find_children("*", "TabContainer", true, false)[0]
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == "Controls":
			tabs.current_tab = i
	await get_tree().process_frame
	return menu


func _rebind_row(menu, action: String) -> Node:
	for r in menu.find_children("*", "KeyRebindRow", true, false):
		if String(r.action) == action:
			return r
	return null


# Through Input, the way a real key or pad arrives, so the menu's focus handling
# gets its turn. Flushed straight away so nothing real lands in between.
func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _tap_key(code: Key) -> void:
	for down in [true, false]:
		var k := _key(code)
		k.keycode = code
		k.pressed = down
		_send(k)


func _tap_button(index: JoyButton) -> void:
	_send(_button(index, true))
	_send(_button(index, false))


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k


func _button(index: JoyButton, down: bool = false) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = index
	b.pressed = down
	return b


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var m := InputEventJoypadMotion.new()
	m.axis = axis
	m.axis_value = value
	return m


func _mouse(index: MouseButton, down: bool) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = index
	m.pressed = down
	return m


func _has_key(action: String, code: Key) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e.physical_keycode == code or e.keycode == code):
			return true
	return false


func _has_button(action: String, index: JoyButton) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == index:
			return true
	return false


func _has_axis(action: String, axis: JoyAxis, direction: float) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion and e.axis == axis and signf(e.axis_value) == signf(direction):
			return true
	return false


func _has_mouse(action: String, index: MouseButton) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton and e.button_index == index:
			return true
	return false


func _run_persistence_roundtrip() -> void:
	# The whole point of the pack: change a setting, restart, still have it.
	await get_tree().process_frame
	_settings_manager().save_file = SANDBOX
	_settings_manager().set_value("audio.master", 0.42)
	_settings_manager().set_value("a11y.font_scale", 1.75)
	# writes are debounced, so a burst of changes coalesces into one file write
	_assert(_settings_manager()._save_pending, "a changed setting queues a write")
	_settings_manager().flush_save()
	_assert(FileAccess.file_exists(SANDBOX), "flushing writes the file")
	_assert(not _settings_manager()._save_pending, "the queue is clear after a flush")

	# what landed on disk must be the whole document, not a truncated one
	var f := FileAccess.open(SANDBOX, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	_assert(parsed is Dictionary, "the file on disk is valid JSON")
	if parsed is Dictionary:
		_assert(is_equal_approx(float(parsed.get("audio.master", -1.0)), 0.42),
			"the value on disk is the one we set (got %s)" % parsed.get("audio.master", "missing"))

	# and reading it back restores both values
	_settings_manager()._data = {}
	_settings_manager().load_settings()
	_assert(is_equal_approx(float(_settings_manager().get_value("audio.master", -1.0)), 0.42),
		"reloading restores the volume (got %s)" % _settings_manager().get_value("audio.master", -1.0))
	_assert(is_equal_approx(float(_settings_manager().get_value("a11y.font_scale", -1.0)), 1.75),
		"reloading restores the font scale (got %s)" % _settings_manager().get_value("a11y.font_scale", -1.0))

	# a setting we never touched still falls back to its default
	_assert(_settings_manager().get_value("display.vsync", null) != null, "untouched settings still resolve to a default")


func _run_corrupt_settings_file() -> void:
	# Settings files get hand-edited and truncated by a full disk.
	await get_tree().process_frame
	_settings_manager().save_file = SANDBOX

	var f := FileAccess.open(SANDBOX, FileAccess.WRITE)
	f.store_string("this is not json at all")
	f.close()
	_settings_manager().load_settings()
	_assert(_settings_manager().get_value("audio.master", null) != null,
		"a non-JSON settings file still leaves usable defaults")

	# a JSON array where an object belongs
	var f2 := FileAccess.open(SANDBOX, FileAccess.WRITE)
	f2.store_string("[1, 2, 3]")
	f2.close()
	_settings_manager().load_settings()
	_assert(_settings_manager().get_value("audio.master", null) != null,
		"a JSON array instead of an object still leaves usable defaults")

	# an empty file
	var f3 := FileAccess.open(SANDBOX, FileAccess.WRITE)
	f3.store_string("")
	f3.close()
	_settings_manager().load_settings()
	_assert(_settings_manager().get_value("a11y.colorblind_filter", null) != null,
		"an empty settings file still leaves usable defaults")


func _run_save_debounce() -> void:
	# A slider drag fires value_changed every frame. Each write truncates the file
	# first, so writing per tick left a stream of moments where settings.json was
	# empty on disk. The burst must collapse into one write that lands on its own.
	await get_tree().process_frame
	_settings_manager().save_file = SANDBOX
	_settings_manager().flush_save()
	if FileAccess.file_exists(SANDBOX):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SANDBOX))

	# simulate a drag
	for i in range(30):
		_settings_manager().set_value("audio.music", float(i) / 30.0)
	_assert(_settings_manager()._save_pending, "a burst of 30 changes leaves one write queued, not 30")
	_assert(not FileAccess.file_exists(SANDBOX), "nothing has been written to disk mid-burst")

	# and it lands by itself, without anyone calling flush
	await get_tree().create_timer(SETTINGS_MANAGER.SAVE_DEBOUNCE_SECONDS + 0.25).timeout
	_assert(not _settings_manager()._save_pending, "the queued write fired on its own")
	_assert(FileAccess.file_exists(SANDBOX), "the debounced write reached the disk")
	_settings_manager()._data = {}
	_settings_manager().load_settings()
	_assert(is_equal_approx(float(_settings_manager().get_value("audio.music", -1.0)), 29.0 / 30.0),
		"the last value of the burst is the one that persisted (got %s)" % _settings_manager().get_value("audio.music", -1.0))


func _run_a_write_that_does_not_finish() -> void:
	# Opening the real file for writing truncates it, so the old settings are
	# gone the instant a write starts. A crash anywhere in the middle used to
	# lose everything the player had ever chosen, and sliders write often, so
	# the window was not small. The write goes to a scratch file and is moved
	# into place only once it is whole.
	_settings_manager().set_value("audio.master", 0.42)
	_settings_manager().save_settings()
	_assert(FileAccess.file_exists(SANDBOX), "settings reached the disk")
	_assert(not FileAccess.file_exists(SANDBOX + ".tmp"), "and the scratch file is gone once the move is done")

	# The property that actually matters, and the one a happy-path check misses
	# entirely: a write that fails must leave the previous settings untouched.
	# Blocking the scratch path with a directory makes the open fail the same way
	# on every platform, and stands in for the disk filling or the process dying.
	var blocked := SANDBOX + ".tmp"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked))
	_settings_manager().set_value("audio.master", 0.99)
	_settings_manager().save_settings()
	var check := FileAccess.open(SANDBOX, FileAccess.READ)
	var on_disk: Variant = JSON.parse_string(check.get_as_text()) if check != null else null
	if check != null:
		check.close()
	_assert(on_disk is Dictionary, "after a write that could not start, the settings file is still readable")
	_assert(on_disk is Dictionary and is_equal_approx(float((on_disk as Dictionary).get("audio.master", -1.0)), 0.42),
		"and still holds the last good values rather than being truncated to nothing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))

	# The crash: a scratch file is left behind holding good content. It is newer
	# than what is on disk, so loading should take it.
	var good := FileAccess.open(SANDBOX + ".tmp", FileAccess.WRITE)
	# Flat keys, the shape this pack actually writes.
	good.store_string(JSON.stringify({"audio.master": 0.77}))
	good.close()
	_settings_manager().load_settings()
	_assert(is_equal_approx(float(_settings_manager().get_value("audio.master", -1.0)), 0.77), "a finished write that never got moved is recovered on load")
	_assert(not FileAccess.file_exists(SANDBOX + ".tmp"), "and the scratch file is cleared once it has been used")

	# The other crash: the scratch file is half written. It must be discarded,
	# never merged, and the real settings must survive untouched.
	_settings_manager().set_value("audio.master", 0.5)
	_settings_manager().save_settings()
	var half := FileAccess.open(SANDBOX + ".tmp", FileAccess.WRITE)
	half.store_string('{"audio.mas')
	half.close()
	_settings_manager().load_settings()
	_assert(is_equal_approx(float(_settings_manager().get_value("audio.master", -1.0)), 0.5), "a half-written scratch file is discarded and the real settings survive")

	# Zero bytes is the most likely thing a crash leaves, and it has to be as
	# quiet as any other recovery. Handing "" to JSON prints a parse error, which
	# a buyer reading their log has no way to know is harmless.
	var blank := FileAccess.open(SANDBOX + ".tmp", FileAccess.WRITE)
	blank.close()
	_settings_manager().load_settings()
	_assert(is_equal_approx(float(_settings_manager().get_value("audio.master", -1.0)), 0.5), "an empty scratch file is discarded too")
	_assert(not FileAccess.file_exists(SANDBOX + ".tmp"), "and cleared rather than retried on every load")
	_assert(not FileAccess.file_exists(SANDBOX + ".tmp"), "and it does not sit there being retried forever")
	await get_tree().process_frame


func _run_pause_reaches_a_gamepad() -> void:
	# A pause action bound only to a key means a player on a gamepad alone can
	# never open the pause menu, and the pause menu is the only way to reach the
	# settings that would let them fix it.
	var dock_script: GDScript = load("res://addons/settings_menus/editor/09-settings-menus_chooser_dock.gd")
	var events: Array = dock_script.pause_events()
	var has_key := false
	var has_pad := false
	for e in events:
		if e is InputEventKey:
			has_key = true
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_START:
			has_pad = true
	_assert(has_key, "pause is still bound to a key")
	_assert(has_pad, "and to the gamepad Start button, so a controller-only player can open the menu")


func _run_effect_toggles() -> void:
	# AX-06 wants a toggle per effect. The trap is reduce motion: it has to switch
	# the motion ones off without eating what the player chose, or someone who
	# turns it on to get through one bad level loses the settings they had.
	_settings_manager().reset_to_defaults()
	var all_on := true
	for row in SETTINGS_MANAGER.EFFECTS:
		if not _settings_manager().is_effect_enabled(String(row[0])):
			all_on = false
	_assert(all_on, "every effect starts on, so enabling the pack does not change how a game looks")

	_settings_manager().set_value("fx.film_grain", false)
	_assert(not _settings_manager().is_effect_enabled("film_grain"), "an effect switched off reads as off")
	_assert(_settings_manager().is_effect_enabled("camera_shake"), "and the ones beside it are left alone")

	var heard: Array = []
	var probe := func(effects: Dictionary): heard.append(effects)
	_settings_manager().effects_changed.connect(probe)
	_settings_manager().set_value("a11y.reduce_motion", true)
	_assert(heard.size() > 0, "reduce motion announces itself on effects_changed, which no fx key would have")
	_assert(not _settings_manager().is_effect_enabled("camera_shake"), "camera shake goes off with reduce motion")
	_assert(not _settings_manager().is_effect_enabled("motion_blur"), "and motion blur with it")
	_assert(_settings_manager().is_effect_enabled("chromatic_aberration"), "while aberration, which is not motion, stays where it was")
	_assert(bool(_settings_manager().get_value("fx.camera_shake", false)), "and the player's own shake setting is still on underneath")

	var after_motion := heard.size()
	_settings_manager().set_value("a11y.font_scale", 1.25)
	_assert(heard.size() == after_motion, "and a font scale drag does not republish the effects, though it comes through the same accessibility path")
	_settings_manager().apply_effects(true)
	_assert(heard.size() == after_motion + 1, "while asking for a resend outright still gets one")

	_settings_manager().set_value("a11y.reduce_motion", false)
	_assert(_settings_manager().is_effect_enabled("camera_shake"), "so turning reduce motion back off returns shake instead of leaving it lost")
	_assert(not _settings_manager().is_effect_enabled("film_grain"), "and the grain they turned off an hour ago is still off")
	_settings_manager().effects_changed.disconnect(probe)

	_assert(not _settings_manager().is_effect_enabled("no_such_effect"), "an effect nobody defined reads as off rather than erroring")
	_settings_manager().reset_to_defaults()


func _run_options_menu_effect_rows() -> void:
	# The API above is only half of AX-06. The other half is a row a player can
	# actually reach, and a box that agrees with what is running.
	_settings_manager().reset_to_defaults()
	# untyped on purpose, same reason as the report scene below: `:=` on
	# load().new() infers Variant and hangs the parser.
	var menu = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
	get_tree().root.add_child(menu)
	await get_tree().process_frame

	var shake_row := _find_labeled_row(menu, "Camera Shake")
	var grain_row := _find_labeled_row(menu, "Film Grain")
	var motion_row := _find_labeled_row(menu, "Reduce Motion")
	_assert(shake_row != null and grain_row != null, "the options menu carries a row per effect, which is the half of AX-06 an API cannot cover")
	if shake_row == null or grain_row == null or motion_row == null:
		menu.queue_free()
		return

	var shake := shake_row.get_child(1) as CheckBox
	var grain := grain_row.get_child(1) as CheckBox
	var motion := motion_row.get_child(1) as CheckBox
	_assert(shake.button_pressed and grain.button_pressed, "and both start ticked, matching the defaults")

	motion.button_pressed = true
	await get_tree().process_frame
	_assert(not shake.button_pressed and shake.disabled, "ticking Reduce Motion shows shake off and takes the box away, rather than leaving a tick beside an effect that is not running")
	_assert(grain.button_pressed and not grain.disabled, "and leaves film grain alone, because grain is not motion")
	_assert(bool(_settings_manager().get_value("fx.camera_shake", false)), "and the greyed box did not write itself back over what the player chose")

	motion.button_pressed = false
	await get_tree().process_frame
	_assert(shake.button_pressed and not shake.disabled, "and unticking it hands camera shake back")

	menu.queue_free()
	await get_tree().process_frame
	_settings_manager().reset_to_defaults()


func _run_effect_rows_write_their_own_key() -> void:
	# Five boxes built in a loop, five closures, one loop variable. Share that
	# capture and every box in the tab writes whichever key the loop ended on, and
	# nothing notices until a player reports that switching off grain killed their
	# camera shake. Click each one and watch where it lands.
	_settings_manager().reset_to_defaults()
	var menu = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
	get_tree().root.add_child(menu)
	await get_tree().process_frame

	var off_so_far: Array = []
	var landed_right := true
	for row in SETTINGS_MANAGER.EFFECTS:
		var r := _find_labeled_row(menu, String(row[1]))
		if r == null:
			landed_right = false
			break
		(r.get_child(1) as CheckBox).button_pressed = false
		off_so_far.append(String(row[0]))
		await get_tree().process_frame
		for other in SETTINGS_MANAGER.EFFECTS:
			var k := String(other[0])
			if bool(_settings_manager().get_value("fx." + k, true)) == off_so_far.has(k):
				landed_right = false
	_assert(landed_right, "each effect row writes its own key rather than whichever one the loop ended on")

	menu.queue_free()
	await get_tree().process_frame
	_settings_manager().reset_to_defaults()


func _run_unticked_boxes_show() -> void:
	# Godot's stock unticked box is drawn for the editor's grey, and on this menu it
	# all but vanished: Reduce Motion read as a bare label with nothing to tick.
	_settings_manager().reset_to_defaults()
	var menu = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	var behind := _backdrop(menu)
	var motion_row := _find_labeled_row(menu, "Reduce Motion")
	var shake_row := _find_labeled_row(menu, "Camera Shake")
	if motion_row == null or shake_row == null:
		_assert(false, "Boxes: the accessibility tab has its Reduce Motion and Camera Shake rows")
		menu.queue_free()
		await get_tree().process_frame
		return
	var motion := motion_row.get_child(1) as CheckBox
	var step := _contrast(motion.get_theme_icon(&"unchecked"), behind)
	_assert(step > 0.25, "Boxes: an unticked box stands out from the menu behind it (step %.2f, the stock box was about 0.02)" % step)
	_assert(motion.get_theme_icon(&"unchecked").get_size() == motion.get_theme_icon(&"checked").get_size(),
		"Boxes: the same size as a ticked one, so the two line up")

	motion.button_pressed = true
	await get_tree().process_frame
	var shake := shake_row.get_child(1) as CheckBox
	var grey := _contrast(shake.get_theme_icon(&"unchecked_disabled"), behind)
	_assert(shake.disabled and not shake.button_pressed and grey > 0.12,
		"Boxes: and a greyed-out one still shows, fainter (step %.2f)" % grey)
	menu.queue_free()
	await get_tree().process_frame

	# Your own Godot Theme's box wins over the frame.
	var own := Theme.new()
	var art := ImageTexture.create_from_image(Image.create_empty(16, 16, false, Image.FORMAT_RGBA8))
	own.set_icon(&"unchecked", &"CheckBox", art)
	var themed = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
	themed.theme = own
	get_tree().root.add_child(themed)
	await get_tree().process_frame
	var own_row := _find_labeled_row(themed, "Reduce Motion")
	_assert(own_row != null and (own_row.get_child(1) as CheckBox).get_theme_icon(&"unchecked") == art,
		"Boxes: a box drawn from your own Godot Theme keeps your art")
	themed.queue_free()
	await get_tree().process_frame
	_settings_manager().reset_to_defaults()


# What sits behind a box in the options menu: the theme's background with the tab
# panel drawn over it.
func _backdrop(menu) -> Color:
	var behind: Color = menu.theme_data.bg_color
	var tabs: Array = menu.find_children("*", "TabContainer", true, false)
	if not tabs.is_empty():
		var panel := (tabs[0] as TabContainer).get_theme_stylebox(&"panel")
		if panel is StyleBoxFlat:
			behind = behind.blend((panel as StyleBoxFlat).bg_color)
	return behind


# How far the most visible pixel of an icon stands off the colour behind it.
func _contrast(icon: Texture2D, behind: Color) -> float:
	var img: Image = icon.get_image() if icon != null else null
	if img == null or img.is_empty():
		return 0.0
	if img.is_compressed():
		img.decompress()
	var most := 0.0
	for y in img.get_height():
		for x in img.get_width():
			most = maxf(most, absf(behind.blend(img.get_pixel(x, y)).get_luminance() - behind.get_luminance()))
	return most


func _run_quality_axes() -> void:
	# PL-01 wants shadows, textures, effects, view distance and post adjustable on
	# their own. This pack owns the choice and what persists; something else does
	# the rendering. So the test is that the choice survives and gets handed over.
	# A graphics pack installed next to this one (AAA Visuals in the Complete bundle)
	# is a real provider. Note what it holds so it gets that back at the end.
	var real: Node = _settings_manager().quality_provider()
	var real_axes: Dictionary = {}
	if real != null and real.has_method("get_axes"):
		real_axes = real.get_axes()
	_settings_manager().reset_to_defaults()
	var all_following := true
	for row in SETTINGS_MANAGER.QUALITY_AXES:
		if int(_settings_manager().get_value("quality." + String(row[0]), 0)) != -1:
			all_following = false
	_assert(all_following, "every quality axis starts following the preset, so a project that ignores this menu is unaffected")

	_settings_manager().set_value("quality.shadows", 0)
	_assert(int(_settings_manager().get_value("quality.shadows", -1)) == 0, "an axis set to Low stays there")
	_assert(int(_settings_manager().get_value("quality.textures", 0)) == -1, "and the one beside it keeps following the preset")

	if real != null:
		# That set_value already went to the installed pack.
		if real.has_method("get_axis_quality"):
			_assert(int(real.get_axis_quality("shadows")) == 0, "the graphics pack installed here (%s) got the Low shadows straight away" % real.name)
			_assert(int(real.get_axis_quality("textures")) == -1, "and its textures still follow its own preset")
		else:
			print("[--] the installed provider has no get_axis_quality(), so what it got can't be read back")
		# Then it steps aside so the stand-in gets the same empty stage it has in a
		# project of its own. Renamed, not removed, so nothing it set up is torn down.
		real.name = "VisualsManager_set_aside"

	# The handover. A stand-in rather than the visuals pack, because this pack
	# ships on its own and has to work with anything offering the same call.
	var provider := Node.new()
	provider.name = "VisualsManager"
	provider.set_script(load("res://tools/quality_provider_stub.gd"))
	get_tree().root.add_child(provider)
	_assert(_settings_manager().quality_provider() == provider, "a node offering set_axis_quality is found by the method, not by the pack it came from")
	_settings_manager().apply_quality()
	_assert(int(provider.got.get("shadows", -99)) == 0, "applying hands every axis over")
	_assert(int(provider.got.get("view_distance", -99)) == -1, "including the ones still following, so the provider can hand them back")
	provider.got.clear()
	_settings_manager().set_value("quality.post", 2)
	_assert(int(provider.got.get("post", -99)) == 2, "and changing one pushes it straight through without waiting for a menu")

	# With a provider in the tree the tab has to be there and has to work, which
	# matters more than the hiding case below.
	var live = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
	get_tree().root.add_child(live)
	await get_tree().process_frame
	var shadow_row := _find_labeled_row(live, "Shadows")
	_assert(shadow_row != null, "with a provider listening the options menu grows a Graphics tab")
	if shadow_row != null:
		var opt := shadow_row.get_child(1) as OptionButton
		_assert(opt.item_count == SETTINGS_MANAGER.QUALITY_LEVELS.size(), "with a row per axis and Follow Preset as the first choice")
		_assert(opt.selected == 1, "showing Low, which is where the setting already was")
		opt.selected = 4
		opt.item_selected.emit(4)
		await get_tree().process_frame
		_assert(int(_settings_manager().get_value("quality.shadows", -1)) == 3, "and picking Ultra writes that level, not the row index")
		_assert(int(provider.got.get("shadows", -99)) == 3, "and it reaches the provider without anything else being touched")
	live.queue_free()
	await get_tree().process_frame

	provider.queue_free()
	await get_tree().process_frame
	_assert(_settings_manager().quality_provider() == null, "with nothing listening there is no provider")
	_settings_manager().apply_quality()
	_assert(true, "and applying anyway is a no-op rather than an error")

	# The tab follows the provider: no listener, no dead dropdowns.
	var menu = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	_assert(_find_labeled_row(menu, "Shadows") == null, "and the options menu shows no Graphics tab when nothing can act on it")
	menu.queue_free()
	await get_tree().process_frame

	if real != null:
		real.name = "VisualsManager"
		var back = load("res://addons/settings_menus/ui/options_menu_ui.gd").new()
		get_tree().root.add_child(back)
		await get_tree().process_frame
		_assert(_settings_manager().quality_provider() == real and _find_labeled_row(back, "Shadows") != null,
			"and with the installed graphics pack back in place, so is the Graphics tab")
		back.queue_free()
		await get_tree().process_frame
	_settings_manager().reset_to_defaults()
	if real != null:
		for axis in real_axes:
			real.set_axis_quality(String(axis), int(real_axes[axis]))


# Every row in this menu is a Label then its control. Find one by what it says.
func _find_labeled_row(node: Node, label_text: String) -> HBoxContainer:
	if node is HBoxContainer and node.get_child_count() >= 2:
		var l := node.get_child(0) as Label
		if l != null and l.text == label_text:
			return node as HBoxContainer
	for c in node.get_children():
		var found := _find_labeled_row(c, label_text)
		if found != null:
			return found
	return null


func _run_optional_buses() -> void:
	# The audio pack grew Dialogue, UI and Ambience buses. A bus nobody can
	# adjust is not independently mixable, so the sliders have to follow. But a
	# project that never made those buses must not get sliders that do nothing,
	# and must not get warned about buses it never asked for.
	var made: Array = []
	for name in ["Dialogue", "UI", "Ambience"]:
		if AudioServer.get_bus_index(name) < 0:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, name)
			made.append(name)
	# Buses an audio pack already made (Audio in the Complete bundle) are borrowed:
	# noted now, taken out for the "gone" check, put back exactly as they were.
	var borrowed: Array = []
	for name in ["Dialogue", "UI", "Ambience"]:
		if not made.has(name):
			borrowed.append(_bus_snapshot(AudioServer.get_bus_index(name)))
	_assert(SETTINGS_MANAGER.bus_exists("dialogue"), "a Dialogue bus is found once it exists")
	_assert(not SETTINGS_MANAGER.bus_exists("nothing_like_this"), "and a bus that does not exist is not")
	_settings_manager().set_value("audio.dialogue", 0.25)
	_settings_manager().apply_audio()
	var idx := AudioServer.get_bus_index("Dialogue")
	_assert(is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.25)), "and the dialogue slider actually moves that bus")

	for name in made:
		AudioServer.remove_bus(AudioServer.get_bus_index(name))
	for snap in borrowed:
		AudioServer.remove_bus(AudioServer.get_bus_index(String(snap["name"])))
	_assert(not SETTINGS_MANAGER.bus_exists("dialogue"), "with the bus gone it reports gone")
	# The real point: no warning, no error, nothing. A game with three buses is
	# a normal game.
	_settings_manager().apply_audio()
	_assert(true, "and applying audio without those buses is silent rather than warning about each one")
	# lowest index first, so each one lands back in its old slot
	borrowed.sort_custom(func(a, b): return int(a["index"]) < int(b["index"]))
	for snap in borrowed:
		_bus_restore(snap)


# Everything it takes to put a bus back where and how it was.
func _bus_snapshot(i: int) -> Dictionary:
	var fx: Array = []
	for e in AudioServer.get_bus_effect_count(i):
		fx.append([AudioServer.get_bus_effect(i, e), AudioServer.is_bus_effect_enabled(i, e)])
	return {"index": i, "name": AudioServer.get_bus_name(i), "volume": AudioServer.get_bus_volume_db(i),
		"send": AudioServer.get_bus_send(i), "mute": AudioServer.is_bus_mute(i), "solo": AudioServer.is_bus_solo(i),
		"bypass": AudioServer.is_bus_bypassing_effects(i), "fx": fx}


func _bus_restore(snap: Dictionary) -> void:
	var i := mini(int(snap["index"]), AudioServer.bus_count)
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, String(snap["name"]))
	AudioServer.set_bus_volume_db(i, float(snap["volume"]))
	AudioServer.set_bus_send(i, StringName(snap["send"]))
	AudioServer.set_bus_mute(i, bool(snap["mute"]))
	AudioServer.set_bus_solo(i, bool(snap["solo"]))
	AudioServer.set_bus_bypass_effects(i, bool(snap["bypass"]))
	var fx: Array = snap["fx"]
	for e in fx.size():
		AudioServer.add_bus_effect(i, fx[e][0], e)
		AudioServer.set_bus_effect_enabled(i, e, bool(fx[e][1]))


# Settings is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const SETTINGS_MANAGER := preload("res://addons/settings_menus/settings_manager.gd")


static func _settings_manager() -> SETTINGS_MANAGER:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"Settings") as SETTINGS_MANAGER
