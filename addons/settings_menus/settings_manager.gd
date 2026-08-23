extends Node

# Settings autoload. Loads persisted settings on _ready, applies them, and
# saves on every change. Holds:
#   * audio bus volumes (one entry per AudioServer bus)
#   * window mode / resolution
#   * key rebindings (action -> Array of InputEvent dicts)
#   * accessibility toggles (font scale, colorblind filter)
#   * arbitrary game-supplied extras via set/get
#
# Persistence: settings live in their own file (user://settings.json by default,
# see `save_file`). That's deliberate — settings belong to the player, not to a
# save slot, so they survive deleting every slot.
#
# This used to try handing them to /root/SaveManager first, via a pair of
# write_side_channel/read_side_channel methods the Save/Load pack has never had.
# has_method() was false every time, so the branch never ran and the file path
# below did all the work. If you want settings inside the Save pack's
# slot-independent global store instead, its GameSettings helper already does
# that; point `save_file` somewhere else and drive SaveManager.set_global yourself.

signal setting_changed(key: String, value)
signal settings_loaded
signal settings_reset

const SAVE_FILE := "user://settings.json"

# Where settings actually land. Point this somewhere else (before anything calls
# save_settings) to sandbox a test or keep per-profile settings. Setting it also
# opts out of the SaveManager side-channel below — if you named a file, you want
# that file.
var save_file: String = SAVE_FILE

# Defaults applied when no save file exists. Game code can override via
# Settings.set_default("key", value) before _ready completes.
var _defaults: Dictionary = {
	"audio.master": 1.0,
	"audio.music": 1.0,
	"audio.sfx": 1.0,
	"display.window_mode": 0,        # 0 windowed, 1 fullscreen, 2 borderless
	"display.resolution_index": 0,   # index into Settings.RESOLUTIONS
	"display.vsync": true,
	"display.fps_visible": false,
	"a11y.font_scale": 1.0,
	"a11y.colorblind_filter": "none",  # none | protanopia | deuteranopia | tritanopia
	"a11y.reduce_motion": false,
	"keybinds": {},
}

const RESOLUTIONS: Array = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

const COLORBLIND_FILTERS: Array = ["none", "protanopia", "deuteranopia", "tritanopia"]

# Default action allowlist for key rebinding UI. Filter your game's actions
# to this list to avoid exposing internal "ui_*" bindings.
var rebindable_actions: PackedStringArray = PackedStringArray([
	"move_left", "move_right", "move_up", "move_down",
	"jump", "attack", "interact", "inventory", "pause",
])

var _data: Dictionary = {}
var _captured_default_binds: Dictionary = {}

# Dragging a slider fires value_changed every frame, and each one used to rewrite
# the file. Opening for write truncates it first, so a drag left a stream of
# moments where settings.json was empty on disk. Coalesce instead: the last
# change in a burst wins, and we flush on the way out so nothing is lost.
const SAVE_DEBOUNCE_SECONDS := 0.35
var _save_timer: Timer
var _save_pending: bool = false


func _ready() -> void:
	_capture_default_binds()
	load_settings()
	apply_all()
	_save_timer = Timer.new()
	_save_timer.name = "SettingsSaveDebounce"
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SECONDS
	_save_timer.timeout.connect(flush_save)
	add_child(_save_timer)
	settings_loaded.emit()


func _notification(what: int) -> void:
	# Don't let a queued write die with the process.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		flush_save()


## Queue a debounced write. Use this from anything that fires rapidly (sliders).
## save_settings() stays immediate for callers that need the file on disk now.
func request_save() -> void:
	_save_pending = true
	if _save_timer != null and is_instance_valid(_save_timer):
		_save_timer.start()
	else:
		save_settings()  # before _ready, or outside the tree: just write


## Write now if a debounced save is waiting. Safe to call any time.
func flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	save_settings()


# ---- public API -----------------------------------------------------------

func set_default(key: String, value) -> void:
	_defaults[key] = value
	if not _data.has(key):
		_data[key] = value


func get_value(key: String, fallback = null):
	if _data.has(key):
		return _data[key]
	if _defaults.has(key):
		return _defaults[key]
	return fallback


## Set a setting and persist. Triggers `apply_*` for the affected category.
func set_value(key: String, value) -> void:
	var old = _data.get(key, _defaults.get(key, null))
	if typeof(old) == typeof(value) and old == value:
		return
	_data[key] = value
	setting_changed.emit(key, value)
	_apply_one(key, value)
	request_save()


func reset_to_defaults() -> void:
	_data = _defaults.duplicate(true)
	apply_all()
	settings_reset.emit()
	save_settings()


## Persist the current snapshot to disk (or the Save backend).
func save_settings() -> void:
	var f := FileAccess.open(save_file, FileAccess.WRITE)
	if f == null:
		# Surface the actual open error code, not just "could not open".
		# Players hitting read-only user dirs or quota issues need this in
		# the log to diagnose lost-settings reports.
		push_warning("Settings: could not open %s for write (%s)" % [save_file, error_string(FileAccess.get_open_error())])
		return
	var text := JSON.stringify(_data, "  ")
	var expected := text.to_utf8_buffer().size()
	f.store_string(text)
	f.close()
	# Measure what actually landed. The previous check called
	# FileAccess.get_open_error() here, which reports the last *open* result and
	# is always OK by this point, so a full disk went unnoticed.
	var check := FileAccess.open(save_file, FileAccess.READ)
	if check == null:
		push_warning("Settings: wrote %s but could not read it back." % save_file)
		return
	var written := check.get_length()
	check.close()
	if written != expected:
		push_warning("Settings: %s is %d bytes but should be %d. The disk may be full; settings may not persist." % [save_file, written, expected])


func load_settings() -> void:
	if not FileAccess.file_exists(save_file):
		_data = _defaults.duplicate(true)
		return
	var f := FileAccess.open(save_file, FileAccess.READ)
	if f == null:
		_data = _defaults.duplicate(true)
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = (parsed as Dictionary).duplicate(true)
	else:
		_data = {}
	_apply_defaults_for_missing()


# ---- audio ----------------------------------------------------------------

func apply_audio() -> void:
	for key in ["master", "music", "sfx"]:
		_apply_audio_one(key)


func _apply_audio_one(bus_key: String) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_key.capitalize())
	if bus_idx < 0:
		# Fall back to lowercased name.
		bus_idx = AudioServer.get_bus_index(bus_key)
	if bus_idx < 0:
		# Surface this loudly — silent -1 means a sound bus the developer
		# renamed or never created, and audio sliders quietly do nothing.
		push_warning("Settings: no audio bus named '%s' or '%s'; '%s' slider will be inert." % [bus_key.capitalize(), bus_key, bus_key])
		return
	var vol: float = float(get_value("audio.%s" % bus_key, 1.0))
	if vol <= 0.0001:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(vol))


# ---- display --------------------------------------------------------------

func apply_display() -> void:
	# Window mode
	var mode: int = int(get_value("display.window_mode", 0))
	match mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	# Defer size + vsync to the next frame. Window mode changes are processed
	# asynchronously by the platform window manager; setting size/vsync in the
	# same frame can race the mode change and leave the window at the wrong
	# size or with the wrong vsync after a fullscreen→windowed swap.
	call_deferred("_apply_display_post_mode", mode)


func _apply_display_post_mode(mode: int) -> void:
	if mode == 0 or mode == 2:
		var idx: int = clampi(int(get_value("display.resolution_index", 0)), 0, RESOLUTIONS.size() - 1)
		var size: Vector2i = RESOLUTIONS[idx]
		DisplayServer.window_set_size(size)
	var vsync: bool = bool(get_value("display.vsync", true))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


# ---- accessibility --------------------------------------------------------

func apply_accessibility() -> void:
	# Font scale is applied at the project Theme level. Themes expose font_size
	# overrides; this autoload just exposes the value and a helper for theme
	# rebuilding. UI code should call get_value("a11y.font_scale") when
	# initializing labels/buttons.
	pass


func get_font_scale() -> float:
	return float(get_value("a11y.font_scale", 1.0))


func get_colorblind_filter() -> String:
	return String(get_value("a11y.colorblind_filter", "none"))


# ---- key rebinding --------------------------------------------------------

func _capture_default_binds() -> void:
	for action in InputMap.get_actions():
		_captured_default_binds[String(action)] = InputMap.action_get_events(action)


func apply_keybinds() -> void:
	var binds: Dictionary = get_value("keybinds", {})
	for action in binds.keys():
		var action_s := String(action)
		if not InputMap.has_action(action_s):
			continue
		InputMap.action_erase_events(action_s)
		var events_data = binds[action]
		if not (events_data is Array):
			continue
		for ev_dict in events_data:
			var ev := _deserialize_event(ev_dict)
			if ev != null:
				InputMap.action_add_event(action_s, ev)


## Replace an action's bindings with the supplied list of InputEvent objects.
## Persists immediately. Rejects (silently) attempts to rebind anything outside
## `rebindable_actions` — the allowlist exists to keep ui_* / engine bindings
## off limits so a stray keypress in the rebind UI can't break menu navigation.
func set_keybind(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		return
	if not _is_rebindable(action):
		push_warning("Settings: refused to rebind '%s', not in rebindable_actions allowlist." % action)
		return
	# De-duplicate events by serialized shape so the same key can't be added
	# twice (e.g. clicking the row, hitting the same key, then hitting it
	# again before exiting listen mode).
	var unique_events: Array = []
	var seen: Dictionary = {}
	for ev in events:
		if not (ev is InputEvent):
			continue
		var sig: String = JSON.stringify(_serialize_event(ev))
		if seen.has(sig):
			continue
		seen[sig] = true
		unique_events.append(ev)
	InputMap.action_erase_events(action)
	for ev in unique_events:
		InputMap.action_add_event(action, ev)
	# Persist as dicts.
	var binds: Dictionary = _data.get("keybinds", {}).duplicate(true)
	binds[action] = unique_events.map(_serialize_event)
	_data["keybinds"] = binds
	save_settings()
	setting_changed.emit("keybinds", binds)


func _is_rebindable(action: String) -> bool:
	if action.begins_with("ui_"):
		return false
	for a in rebindable_actions:
		if String(a) == action:
			return true
	# When the game hasn't published an allowlist (empty), default to "any
	# non-ui_ action" so this autoload still works out of the box.
	return rebindable_actions.is_empty()


## Returns the first action (other than `exclude_action`) that currently
## listens for the given event. Empty string if none. Use this from the
## rebind UI to detect conflicts BEFORE committing a new binding.
func find_conflicting_action(event: InputEvent, exclude_action: String = "") -> String:
	if event == null:
		return ""
	for action in InputMap.get_actions():
		var a := String(action)
		if a == exclude_action:
			continue
		for existing in InputMap.action_get_events(a):
			if _events_equivalent(existing, event):
				return a
	return ""


func _events_equivalent(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a.get_class() != b.get_class():
		return false
	return JSON.stringify(_serialize_event(a)) == JSON.stringify(_serialize_event(b))


func get_keybind_events(action: String) -> Array:
	if not InputMap.has_action(action):
		return []
	return InputMap.action_get_events(action)


## Restore one action to its original bindings (captured at _ready).
func reset_keybind(action: String) -> void:
	if not _captured_default_binds.has(action):
		return
	var defaults: Array = _captured_default_binds[action]
	set_keybind(action, defaults)


func reset_all_keybinds() -> void:
	for action in _captured_default_binds.keys():
		reset_keybind(String(action))


# ---- internals ------------------------------------------------------------

func apply_all() -> void:
	apply_audio()
	apply_display()
	apply_accessibility()
	apply_keybinds()


func _apply_one(key: String, _value) -> void:
	if key.begins_with("audio."):
		var bus := key.substr(6)
		_apply_audio_one(bus)
	elif key.begins_with("display."):
		apply_display()
	elif key.begins_with("a11y."):
		apply_accessibility()
	elif key == "keybinds":
		apply_keybinds()


func _apply_defaults_for_missing() -> void:
	for k in _defaults.keys():
		if not _data.has(k):
			_data[k] = _defaults[k]


# Limited input-event serialization: keyboard, mouse button, joypad button.
# Good enough for v1 rebinding. Game code can override by subclassing.
func _serialize_event(ev) -> Dictionary:
	if ev is InputEventKey:
		return {"t": "key", "keycode": int(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)}
	if ev is InputEventMouseButton:
		return {"t": "mb", "button_index": int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"t": "jb", "button_index": int(ev.button_index)}
	return {}


func _deserialize_event(d) -> InputEvent:
	if not (d is Dictionary):
		return null
	match String(d.get("t", "")):
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = int(d.get("keycode", 0))
			return ev
		"mb":
			var ev := InputEventMouseButton.new()
			ev.button_index = int(d.get("button_index", 0))
			return ev
		"jb":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(d.get("button_index", 0))
			return ev
	return null
