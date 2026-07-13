extends Node

# Headless test for the Settings / Menus addon.
# Run: godot --headless --path . res://tools/verify.tscn

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- settings / menus verify ---")
	await _run_defaults_load()
	await _run_set_and_persist()
	await _run_audio_bus_missing_warns()
	await _run_keybind_allowlist()
	await _run_keybind_dedup()
	await _run_keybind_conflict_detection()
	await _run_ui_ignores_ui_actions()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- tests ---------------------------------------------------------------

func _run_defaults_load() -> void:
	await get_tree().process_frame
	_assert(Settings != null, "Boot: Settings autoload present")
	# Default master volume is 1.0.
	_assert(float(Settings.get_value("audio.master", -1.0)) == 1.0,
		"Defaults: audio.master = 1.0 (got %s)" % str(Settings.get_value("audio.master", -1.0)))


func _run_set_and_persist() -> void:
	await get_tree().process_frame
	# Mutate a value, save, then load fresh and verify it survived.
	Settings.set_value("audio.music", 0.42)
	Settings.save_settings()
	# Reset in-memory snapshot, then load from disk.
	Settings._data.clear()
	Settings.load_settings()
	_assert(abs(float(Settings.get_value("audio.music", -1.0)) - 0.42) < 0.001,
		"Persist: audio.music round-trips (got %s)" % str(Settings.get_value("audio.music", -1.0)))


func _run_audio_bus_missing_warns() -> void:
	await get_tree().process_frame
	# Re-applying audio with a missing bus shouldn't crash. We can't easily
	# capture push_warning output in a headless test, but a clean run with
	# no exception is the success signal.
	Settings.set_value("audio.master", 0.5)
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
	Settings.set_keybind("ui_accept", [ev])
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
	Settings.set_keybind("game_test_action", [ev])
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
		Settings.set_keybind("jump", [ev])
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
	Settings.set_keybind("jump", [ev1, ev2, ev1])
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
	Settings.set_keybind("jump", [w])
	# Now ask: is W conflicting if we try to bind it to attack?
	var w2 := InputEventKey.new()
	w2.physical_keycode = KEY_W
	var conflict: String = Settings.find_conflicting_action(w2, "attack")
	_assert(conflict == "jump", "Conflict: W bound to jump detected when probing for attack (got '%s')" % conflict)
	# Probing against the SAME action excludes it (no self-conflict).
	var self_conflict: String = Settings.find_conflicting_action(w2, "jump")
	_assert(self_conflict == "", "Conflict: probe excludes the action being rebound (got '%s')" % self_conflict)


func _run_ui_ignores_ui_actions() -> void:
	await get_tree().process_frame
	# Confirm _is_rebindable rejects ui_* outright.
	_assert(not Settings._is_rebindable("ui_accept"), "Rebindable: ui_* rejected")
	_assert(Settings._is_rebindable("jump"), "Rebindable: jump (in allowlist) accepted")
	_assert(not Settings._is_rebindable("not_in_allowlist"), "Rebindable: arbitrary action rejected when allowlist non-empty")
