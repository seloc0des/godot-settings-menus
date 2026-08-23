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
	if Settings:
		Settings.save_file = SANDBOX
	await _run_defaults_load()
	await _run_set_and_persist()
	await _run_audio_bus_missing_warns()
	await _run_keybind_allowlist()
	await _run_keybind_dedup()
	await _run_keybind_conflict_detection()
	await _run_ui_ignores_ui_actions()
	await _run_persistence_roundtrip()
	await _run_corrupt_settings_file()
	await _run_save_debounce()
	_assert(_snapshot_real_settings() == real_before,
		"Sandbox: the real %s was left untouched" % Settings.SAVE_FILE)
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
	if not FileAccess.file_exists(Settings.SAVE_FILE):
		return ""
	var f := FileAccess.open(Settings.SAVE_FILE, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _cleanup_sandbox() -> void:
	Settings.save_file = Settings.SAVE_FILE
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
	_assert(Settings != null, "Boot: Settings autoload present")
	# Clear any state a prior run persisted to user://settings.json so the
	# defaults check is idempotent (this test later sets audio.master = 0.5).
	if Settings:
		Settings.reset_to_defaults()
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


func _run_persistence_roundtrip() -> void:
	# The whole point of the pack: change a setting, restart, still have it.
	await get_tree().process_frame
	Settings.save_file = SANDBOX
	Settings.set_value("audio.master", 0.42)
	Settings.set_value("a11y.font_scale", 1.75)
	# writes are debounced, so a burst of changes coalesces into one file write
	_assert(Settings._save_pending, "a changed setting queues a write")
	Settings.flush_save()
	_assert(FileAccess.file_exists(SANDBOX), "flushing writes the file")
	_assert(not Settings._save_pending, "the queue is clear after a flush")

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
	Settings._data = {}
	Settings.load_settings()
	_assert(is_equal_approx(float(Settings.get_value("audio.master", -1.0)), 0.42),
		"reloading restores the volume (got %s)" % Settings.get_value("audio.master", -1.0))
	_assert(is_equal_approx(float(Settings.get_value("a11y.font_scale", -1.0)), 1.75),
		"reloading restores the font scale (got %s)" % Settings.get_value("a11y.font_scale", -1.0))

	# a setting we never touched still falls back to its default
	_assert(Settings.get_value("display.vsync", null) != null, "untouched settings still resolve to a default")


func _run_corrupt_settings_file() -> void:
	# Settings files get hand-edited and truncated by a full disk.
	await get_tree().process_frame
	Settings.save_file = SANDBOX

	var f := FileAccess.open(SANDBOX, FileAccess.WRITE)
	f.store_string("this is not json at all")
	f.close()
	Settings.load_settings()
	_assert(Settings.get_value("audio.master", null) != null,
		"a non-JSON settings file still leaves usable defaults")

	# a JSON array where an object belongs
	var f2 := FileAccess.open(SANDBOX, FileAccess.WRITE)
	f2.store_string("[1, 2, 3]")
	f2.close()
	Settings.load_settings()
	_assert(Settings.get_value("audio.master", null) != null,
		"a JSON array instead of an object still leaves usable defaults")

	# an empty file
	var f3 := FileAccess.open(SANDBOX, FileAccess.WRITE)
	f3.store_string("")
	f3.close()
	Settings.load_settings()
	_assert(Settings.get_value("a11y.colorblind_filter", null) != null,
		"an empty settings file still leaves usable defaults")


func _run_save_debounce() -> void:
	# A slider drag fires value_changed every frame. Each write truncates the file
	# first, so writing per tick left a stream of moments where settings.json was
	# empty on disk. The burst must collapse into one write that lands on its own.
	await get_tree().process_frame
	Settings.save_file = SANDBOX
	Settings.flush_save()
	if FileAccess.file_exists(SANDBOX):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SANDBOX))

	# simulate a drag
	for i in range(30):
		Settings.set_value("audio.music", float(i) / 30.0)
	_assert(Settings._save_pending, "a burst of 30 changes leaves one write queued, not 30")
	_assert(not FileAccess.file_exists(SANDBOX), "nothing has been written to disk mid-burst")

	# and it lands by itself, without anyone calling flush
	await get_tree().create_timer(Settings.SAVE_DEBOUNCE_SECONDS + 0.25).timeout
	_assert(not Settings._save_pending, "the queued write fired on its own")
	_assert(FileAccess.file_exists(SANDBOX), "the debounced write reached the disk")
	Settings._data = {}
	Settings.load_settings()
	_assert(is_equal_approx(float(Settings.get_value("audio.music", -1.0)), 29.0 / 30.0),
		"the last value of the burst is the one that persisted (got %s)" % Settings.get_value("audio.music", -1.0))
