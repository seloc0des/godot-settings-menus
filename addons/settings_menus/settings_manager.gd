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
# Fires whenever the effect toggles or reduce motion move. Reduce motion changes
# what is on without changing any fx key, so watching setting_changed for fx.*
# alone would miss half of it.
signal effects_changed(effects: Dictionary)

const SAVE_FILE := "user://settings.json"

# Where settings actually land. Point this somewhere else (before anything calls
# save_settings) to sandbox a test or keep per-profile settings. It used to also
# opt out of the SaveManager side-channel, which no longer exists.
var save_file: String = SAVE_FILE

# Defaults applied when no save file exists. Game code can override via
# Settings.set_default("key", value) before _ready completes.
var _defaults: Dictionary = {
	"audio.master": 1.0,
	"audio.music": 1.0,
	"audio.sfx": 1.0,
	# Dialogue, UI and Ambience are optional: a project with only Master, Music
	# and SFX buses gets no sliders for them and no warnings about them. They
	# are here because a bus nobody can adjust is not independently mixable, and
	# voice level is the one most often asked for by name.
	"audio.dialogue": 1.0,
	"audio.ui": 1.0,
	"audio.ambience": 1.0,
	# -1 for both: the window opens the way the project sets it up, until the player
	# picks something. Defaults of windowed and 1280x720 resized every game on its
	# first launch, a portrait one into landscape.
	"display.window_mode": -1,       # -1 as the project opens, 0 windowed, 1 fullscreen, 2 borderless
	"display.resolution_index": -1,  # -1 the project's own size, else an index into Settings.RESOLUTIONS
	# As the project has it, so turning this pack on doesn't switch VSync on or off.
	"display.vsync": int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", 1)) != DisplayServer.VSYNC_DISABLED,
	"display.fps_visible": false,
	"a11y.font_scale": 1.0,
	"a11y.colorblind_filter": "none",  # none | protanopia | deuteranopia | tritanopia
	"a11y.reduce_motion": false,
	# One toggle per effect rather than a single post switch, because the reason
	# someone kills camera shake is not the reason they kill film grain. All
	# default on: turning this pack on must not change how a game already looks.
	"fx.camera_shake": true,
	"fx.motion_blur": true,
	"fx.chromatic_aberration": true,
	"fx.film_grain": true,
	"fx.depth_of_field": true,
	# Per-feature quality. -1 means "follow whatever preset is selected", which is
	# how everyone starts, so a project that never opens this menu is unaffected.
	# One preset slider is the usual answer and the standard says it is not
	# enough: the player dropping shadows to hold a frame rate rarely wants their
	# textures dropped too.
	"quality.shadows": -1,
	"quality.textures": -1,
	"quality.effects": -1,
	"quality.view_distance": -1,
	"quality.post": -1,
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

# key, label, does reduce motion switch it off. Ordered because the options menu
# builds its rows straight from this.
## key, label. The names are this pack's, not the visuals pack's: settings owns
## what a player sees and what persists, and hands the level over to whoever is
## doing the rendering.
const QUALITY_AXES: Array = [
	["shadows", "Shadows"],
	["textures", "Textures"],
	["effects", "Effects"],
	["view_distance", "View Distance"],
	["post", "Post Processing"],
]

## Level names, in order, with the first standing for "follow the preset".
const QUALITY_LEVELS: Array = ["Follow Preset", "Low", "Medium", "High", "Ultra"]

const EFFECTS: Array = [
	["camera_shake", "Camera Shake", true],
	["motion_blur", "Motion Blur", true],
	["chromatic_aberration", "Chromatic Aberration", false],
	["film_grain", "Film Grain", false],
	["depth_of_field", "Depth of Field", false],
]

# Default action allowlist for key rebinding UI. Filter your game's actions
# to this list to avoid exposing internal "ui_*" bindings.
var rebindable_actions: PackedStringArray = PackedStringArray([
	"move_left", "move_right", "move_up", "move_down",
	"jump", "attack", "interact", "inventory", "pause",
])

## Does a key or button that menu navigation uses (Space, Enter, the arrows, and A
## and B once a game puts them on ui_accept and ui_cancel) count as taken when
## rebinding? Off by default. Games put jump on Space and A, and a dodge on B, on
## purpose, and counting them meant jump could never go back to Space.
var menu_navigation_clashes: bool = false

## Show FPS draws its counter in the top left corner. Turn this off if your game draws
## its own, and read display.fps_visible to show it. Takes effect straight away.
var draw_fps_counter: bool = true:
	set(value):
		draw_fps_counter = value
		if is_node_ready():
			_apply_fps_counter()

## The colorblind filter is drawn over the whole screen, menus included. Turn this off
## if your game applies its own, or colours get corrected twice. Takes effect straight away.
var draw_colorblind_filter: bool = true:
	set(value):
		draw_colorblind_filter = value
		if is_node_ready():
			_apply_colorblind_filter()

## True in a browser build. Kept in a variable so the self-test can build the menus
## the way a browser shows them.
static var is_web: bool = OS.has_feature("web")

# True while quit_game is telling the tree, so a handler that calls it again quits.
static var _quitting := false

const COLORBLIND_SHADER := preload("res://addons/settings_menus/shaders/colorblind.gdshader")

var _data: Dictionary = {}
var _captured_default_binds: Dictionary = {}
var _last_effects: Dictionary = {}

# Dragging a slider fires value_changed every frame, and each one used to rewrite
# the file. Opening for write truncates it first, so a drag left a stream of
# moments where settings.json was empty on disk. Coalesce instead: the last
# change in a burst wins, and we flush on the way out so nothing is lost.
const SAVE_DEBOUNCE_SECONDS := 0.35
var _save_timer: Timer
var _save_pending: bool = false

var _fps_layer: CanvasLayer
var _fps_label: Label
var _fps_timer: Timer
var _colorblind_layer: CanvasLayer
var _colorblind_material: ShaderMaterial
# Only while _ready applies the saved settings. A saved size un-maximizes the window
# then, and when the player picks one, but not on every later display change.
var _launching := false


func _ready() -> void:
	_capture_default_binds()
	load_settings()
	_launching = true
	apply_all()
	_launching = false
	# An audio pack listed after this one makes its Dialogue, UI and Ambience buses
	# in its own _ready, so the saved levels get a second pass once everyone's up.
	call_deferred("apply_audio")
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
	_restore_default_binds()
	apply_all()
	settings_reset.emit()
	save_settings()


## Persist the current snapshot to disk (or the Save backend).
##
## Written to a scratch file first, checked, then moved over the real one.
## Opening the real file for writing truncates it, so the old version is gone
## the instant the write starts. Crash anywhere in the middle and the player
## loses every setting they ever chose, not the last few seconds of them.
## Sliders write often, so the window is not small.
func save_settings() -> void:
	var tmp := save_file + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		# Surface the actual open error code, not just "could not open".
		# Players hitting read-only user dirs or quota issues need this in
		# the log to diagnose lost-settings reports.
		push_warning("Settings: could not open %s for write (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	var text := JSON.stringify(_data, "  ")
	var expected := text.to_utf8_buffer().size()
	f.store_string(text)
	f.close()

	# Measure what actually landed before anything replaces the good file. The
	# old check called FileAccess.get_open_error() here, which reports the last
	# *open* result and is always OK by this point, so a full disk went
	# unnoticed and then overwrote the settings with a truncated file.
	var check := FileAccess.open(tmp, FileAccess.READ)
	if check == null:
		push_warning("Settings: wrote %s but could not read it back, so %s was left alone." % [tmp, save_file])
		return
	var written := check.get_length()
	check.close()
	if written != expected:
		push_warning("Settings: %s is %d bytes but should be %d. The disk may be full. %s was left alone." % [tmp, written, expected, save_file])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return

	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_file))
	if err != OK:
		push_warning("Settings: could not move %s into place (%s). The previous settings are still there." % [tmp, error_string(err)])


func load_settings() -> void:
	_recover_interrupted_write()
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


## A scratch file left behind means the game died between writing it and moving
## it. If it parses it is newer than what is on disk, so it is worth keeping.
## If it does not, it is the half-written file the real one was saved from.
func _recover_interrupted_write() -> void:
	var tmp := save_file + ".tmp"
	if not FileAccess.file_exists(tmp):
		return
	var f := FileAccess.open(tmp, FileAccess.READ)
	var good := false
	if f != null:
		var text := f.get_as_text()
		f.close()
		# Checked for emptiness first. A zero byte file is exactly what a crash
		# during a write leaves behind, and handing "" to JSON.parse_string
		# prints a parse error at game start on a path that is working as
		# designed. A buyer reading that log has no way to know it is harmless.
		good = not text.strip_edges().is_empty() and JSON.parse_string(text) is Dictionary
	if good:
		push_warning("Settings: recovered %s from a write that did not finish." % save_file)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_file))
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


# ---- quitting -------------------------------------------------------------

## Can the game close itself here? Not in a browser: quit() stops the engine and
## leaves its last frame frozen on the page until the player reloads. Not on iOS
## either, where the player closes apps and quit() does nothing.
static func can_quit() -> bool:
	return not (is_web or OS.has_feature("ios"))


## Close the game the way the window's close button does. Everything listening for
## the close request hears it first: Save/Load's save on quit, a "Really quit?"
## dialog, this pack's own pending save. quit() on its own skipped all of them, so
## a Quit button never saved. Whoever switched auto-accept off does the quitting.
static func quit_game(tree: SceneTree) -> void:
	if not can_quit():
		return
	# Asked again from inside a close handler: everyone has heard it, so this is
	# the handler saying it is done. Going round again never ends.
	if _quitting:
		tree.quit()
		return
	_quitting = true
	_tell_closing(tree.root)
	_quitting = false
	if tree.auto_accept_quit:
		tree.quit()


# The way the engine tells the tree when the window's close button is pressed. Not
# propagate_notification: that reached a "Really quit?" dialog too, which cancelled
# itself, and held every node busy so a handler couldn't add one.
static func _tell_closing(node: Node) -> void:
	node.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for child in node.get_children(true):
		if not child is Window:
			_tell_closing(child)


# ---- audio ----------------------------------------------------------------

## The three that every project has, then the three that only exist if an audio
## pack made them. Missing optional buses are skipped in silence: a project that
## never created a Dialogue bus does not have a bug.
const CORE_BUSES := ["master", "music", "sfx"]
const OPTIONAL_BUSES := ["dialogue", "ui", "ambience"]
## A project with no Music or SFX bus gets one, sent to Master, so the sliders
## work in a fresh project instead of warning on every Play. Named the way the
## Audio pack names them, so the two packs share one SFX bus, never SFX and Sfx.
const MADE_BUSES := {"music": "Music", "sfx": "SFX"}


func apply_audio() -> void:
	for key in CORE_BUSES:
		_apply_audio_one(key)
	for key in OPTIONAL_BUSES:
		if bus_exists(key):
			_apply_audio_one(key)


## Is there a bus for this key? Used to decide which sliders to build, so a
## settings menu shows exactly the buses the project actually has.
static func bus_exists(bus_key: String) -> bool:
	return _bus_index(bus_key) >= 0


# Any spelling counts: this pack's own layout says Sfx, the Audio pack says SFX and
# UI. Only Sfx and ui were ever looked for, so the Audio pack's SFX and UI buses
# never got a working slider.
static func _bus_index(bus_key: String) -> int:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).to_lower() == bus_key.to_lower():
			return i
	return -1


func _apply_audio_one(bus_key: String) -> void:
	var bus_idx := _bus_index(bus_key)
	if bus_idx < 0 and MADE_BUSES.has(bus_key):
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, String(MADE_BUSES[bus_key]))
		AudioServer.set_bus_send(bus_idx, &"Master")
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

## Can the game set its own window mode, size and VSync here? Not in a browser. The
## page is the browser's: it refuses fullscreen unless the player has just clicked
## or pressed a key, ignores a window size, and syncs frames itself.
static func has_window_controls() -> bool:
	return not is_web


## size_picked: the player just chose a Resolution entry. Picking Default puts the
## window back to the project's size then, where at launch Default leaves it alone.
func apply_display(size_picked: bool = false) -> void:
	if not has_window_controls():
		return
	# Window mode. -1 leaves it as the project opened it.
	var mode: int = int(get_value("display.window_mode", -1))
	var idx: int = int(get_value("display.resolution_index", -1))
	match mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			# A project that opens maximized has no size to set until it isn't. Only for a
			# size the player chose, now or before this launch: toggling VSync must not
			# pull a window they maximized by hand back down.
			var size_wanted := size_picked or (_launching and idx >= 0)
			if size_wanted and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Defer size + vsync to the next frame. Window mode changes are processed
	# asynchronously by the platform window manager; setting size/vsync in the
	# same frame can race the mode change and leave the window at the wrong
	# size or with the wrong vsync after a fullscreen→windowed swap.
	call_deferred("_apply_display_post_mode", mode, size_picked)


func _apply_display_post_mode(mode: int, size_picked: bool = false) -> void:
	var now := DisplayServer.window_get_mode()
	var fullscreen := now == DisplayServer.WINDOW_MODE_FULLSCREEN or now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var windowed := mode == 0 or mode == 2 or (mode < 0 and not fullscreen)
	var idx: int = int(get_value("display.resolution_index", -1))
	if windowed and idx >= 0:
		DisplayServer.window_set_size(RESOLUTIONS[mini(idx, RESOLUTIONS.size() - 1)])
	elif windowed and size_picked:
		DisplayServer.window_set_size(project_window_size())
	# Only when it differs, so a project on adaptive or mailbox VSync keeps it.
	var vsync: bool = bool(get_value("display.vsync", true))
	var vsync_on := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	if vsync != vsync_on:
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## The window mode as the Display tab should show it: what the player picked, or,
## before they pick, what the window is actually doing.
func get_window_mode_shown() -> int:
	var mode: int = int(get_value("display.window_mode", -1))
	if mode >= 0:
		return mode
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return 1
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		return 2
	return 0


## The project's own window size, for the Resolution list's first entry.
static func project_window_size() -> Vector2i:
	var w := int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))
	var h := int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	if w <= 0 or h <= 0:
		w = int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152))
		h = int(ProjectSettings.get_setting("display/window/size/viewport_height", 648))
	return Vector2i(w, h)


# ---- FPS counter ----------------------------------------------------------

func _apply_fps_counter() -> void:
	var show := draw_fps_counter and bool(get_value("display.fps_visible", false))
	if show and _fps_layer == null:
		_fps_layer = CanvasLayer.new()
		_fps_layer.name = "SettingsFpsCounter"
		_fps_layer.layer = 1026  # over everything, the colorblind filter included
		_fps_layer.process_mode = Node.PROCESS_MODE_ALWAYS  # keeps counting while paused
		_fps_label = Label.new()
		_fps_label.position = Vector2(8, 6)
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_label.add_theme_font_size_override("font_size", 14)
		_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_fps_label.add_theme_constant_override("outline_size", 4)
		_fps_layer.add_child(_fps_label)
		_fps_timer = Timer.new()
		_fps_timer.wait_time = 0.5
		_fps_timer.timeout.connect(_update_fps_counter)
		_fps_layer.add_child(_fps_timer)
		add_child(_fps_layer)
	if _fps_layer == null:
		return
	_fps_layer.visible = show
	if show:
		_update_fps_counter()
		if _fps_timer.is_inside_tree():
			_fps_timer.start()
	else:
		_fps_timer.stop()


func _update_fps_counter() -> void:
	_fps_label.text = "FPS: %d" % int(Engine.get_frames_per_second())


# ---- accessibility --------------------------------------------------------

func apply_accessibility() -> void:
	# Font scale is applied at the project Theme level. Themes expose font_size
	# overrides; this autoload just exposes the value and a helper for theme
	# rebuilding. UI code should call get_value("a11y.font_scale") when
	# initializing labels/buttons.
	# Reduce motion is not theme-level. It gates the motion effects, so applying
	# accessibility has to re-publish those.
	apply_effects()
	_apply_colorblind_filter()


func get_font_scale() -> float:
	return float(get_value("a11y.font_scale", 1.0))


func get_colorblind_filter() -> String:
	return String(get_value("a11y.colorblind_filter", "none"))


# The filter used to be a stored choice and nothing more, so picking one changed
# nothing on screen unless the game had written its own. It is drawn here now, one
# layer under the FPS counter so the counter stays readable.
func _apply_colorblind_filter() -> void:
	var mode := COLORBLIND_FILTERS.find(get_colorblind_filter())
	var on := draw_colorblind_filter and mode > 0
	if on and _colorblind_layer == null:
		_colorblind_layer = CanvasLayer.new()
		_colorblind_layer.name = "SettingsColorblindFilter"
		# Over the layer Godot draws popups and dropdown lists on (1024). At 127 an open
		# Options dropdown was left uncorrected.
		_colorblind_layer.layer = 1025
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks go through to the game
		_colorblind_material = ShaderMaterial.new()
		_colorblind_material.shader = COLORBLIND_SHADER
		rect.material = _colorblind_material
		_colorblind_layer.add_child(rect)
		add_child(_colorblind_layer)
	if _colorblind_layer == null:
		return
	_colorblind_layer.visible = on
	if on:
		_colorblind_material.set_shader_parameter("mode", mode)
		_sync_filter_hdr()
	# A game can switch HDR 2D while it runs, so the filter checks each frame it is on.
	var watching := get_tree().process_frame.is_connected(_sync_filter_hdr)
	if on and not watching:
		get_tree().process_frame.connect(_sync_filter_hdr)
	elif not on and watching:
		get_tree().process_frame.disconnect(_sync_filter_hdr)


func _sync_filter_hdr() -> void:
	# Compatibility ignores HDR 2D and keeps the screen in sRGB (checked on 4.5 and 4.7),
	# so only Forward+ and Mobile hand the filter linear light.
	var hdr := get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var told: Variant = _colorblind_material.get_shader_parameter("hdr_linear")  # null until first set
	if typeof(told) != TYPE_BOOL or told != hdr:
		_colorblind_material.set_shader_parameter("hdr_linear", hdr)


# ---- quality --------------------------------------------------------------

## Whoever is willing to act on a per-feature quality level, or null. Found by
## the method rather than by the pack, so anything offering the same call works
## and a project without a visuals pack gets no dead controls.
func quality_provider() -> Node:
	# Safe to call from _ready whatever the autoload order: every autoload is in
	# the tree before any autoload's _ready runs, so a renderer listed after
	# this pack is already findable here. Checked, not assumed.
	var vm := get_node_or_null("/root/VisualsManager")
	if vm != null and vm.has_method("set_axis_quality"):
		return vm
	return null


## Push every axis at the provider. Nothing here renders anything, so this pack
## remembers the choice and the visuals pack acts on it.
func apply_quality() -> void:
	var vm := quality_provider()
	if vm == null:
		return
	for row in QUALITY_AXES:
		var key := String(row[0])
		vm.set_axis_quality(key, int(get_value("quality." + key, -1)))


# ---- effects --------------------------------------------------------------

## Is this effect on, right now, for this player? Folds the toggle and reduce
## motion together so a caller never has to remember which effects reduce motion
## is meant to gate. An unknown name comes back false rather than erroring: a
## typo should switch an effect off, not take a frame down.
func is_effect_enabled(effect: String) -> bool:
	var row := _effect_row(effect)
	if row.is_empty():
		return false
	if bool(row[2]) and bool(get_value("a11y.reduce_motion", false)):
		return false
	return bool(get_value("fx." + effect, true))


## Every effect and whether it is on. For a visuals pack that would rather apply
## the lot in one pass than ask five times, and for reading the state on start,
## since anything connecting after this autoload is ready has missed the first
## effects_changed.
func get_effects() -> Dictionary:
	var out := {}
	for row in EFFECTS:
		out[String(row[0])] = is_effect_enabled(String(row[0]))
	return out


## Re-publish the effect state, if it moved. Nothing in here owns a camera or a
## post pass, so this pack decides and the game applies.
##
## Only emits on an actual change, because every a11y key routes through
## apply_accessibility and a font scale drag would otherwise republish the
## effects thirty times on the way past. Pass force to resend anyway, which is
## what you want after rebuilding whatever was listening.
func apply_effects(force: bool = false) -> void:
	var now := get_effects()
	if not force and now == _last_effects:
		return
	_last_effects = now
	effects_changed.emit(now)


func _effect_row(effect: String) -> Array:
	for row in EFFECTS:
		if String(row[0]) == effect:
			return row
	return []


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
## rebind UI to detect conflicts BEFORE committing a new binding. The engine's
## ui_* actions don't count, unless `menu_navigation_clashes` is on, and then
## only the menu navigation ones do.
func find_conflicting_action(event: InputEvent, exclude_action: String = "") -> String:
	if event == null:
		return ""
	for action in InputMap.get_actions():
		var a := String(action)
		if a == exclude_action or _is_widget_action(a):
			continue
		if not menu_navigation_clashes and MENU_NAV_ACTIONS.has(a):
			continue
		for existing in InputMap.action_get_events(a):
			if _events_equivalent(existing, event):
				return a
	return ""


# Of the engine's own ui_* actions, only menu navigation can clash with a game's
# controls, and only with menu_navigation_clashes on. The rest are shortcuts inside
# text boxes, file dialogs, graph and colour widgets, and they share keys with games
# by design: H shows hidden files, F5 refreshes a dialog, Ctrl+F finds a file. They
# used to refuse H and F outright.
const MENU_NAV_ACTIONS := ["ui_accept", "ui_select", "ui_cancel", "ui_focus_next", "ui_focus_prev",
	"ui_left", "ui_right", "ui_up", "ui_down", "ui_page_up", "ui_page_down", "ui_home", "ui_end"]


func _is_widget_action(action: String) -> bool:
	return action.begins_with("ui_") and not MENU_NAV_ACTIONS.has(action)


# `a` is the binding already there, `b` the key just pressed. Order matters for
# modifiers, the way Godot matches them: a binding that needs Ctrl doesn't fire on
# a bare F, but a plain W binding fires on Shift+W too, so that still clashes.
func _events_equivalent(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a.get_class() != b.get_class():
		return false
	if JSON.stringify(_serialize_event(a)) != JSON.stringify(_serialize_event(b)):
		return false
	if a is InputEventWithModifiers:
		var need: int = (a as InputEventWithModifiers).get_modifiers_mask()
		var held: int = (b as InputEventWithModifiers).get_modifiers_mask()
		return (need & held) == need
	return true


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


## Every rebindable action back to its original bindings. Only those: walking every
## captured action took in the engine's ui_* ones too, and set_keybind warned about
## each one it refused.
func reset_all_keybinds() -> void:
	for action in _captured_default_binds.keys():
		if _is_rebindable(String(action)):
			reset_keybind(String(action))


# Reset to Defaults empties the saved bindings, which left apply_keybinds() nothing to
# apply, so a rebound key stayed rebound until the next launch. Put the live ones back.
func _restore_default_binds() -> void:
	for action in _captured_default_binds.keys():
		var a := String(action)
		if not _is_rebindable(a) or not InputMap.has_action(a):
			continue
		InputMap.action_erase_events(a)
		for ev in _captured_default_binds[action]:
			InputMap.action_add_event(a, ev)


# ---- internals ------------------------------------------------------------

func apply_all() -> void:
	apply_audio()
	apply_display()
	_apply_fps_counter()
	apply_accessibility()
	apply_quality()
	apply_keybinds()


func _apply_one(key: String, _value) -> void:
	if key.begins_with("audio."):
		var bus := key.substr(6)
		_apply_audio_one(bus)
	elif key == "display.fps_visible":
		# Not apply_display: that snapped a window the player had dragged to a new
		# size back to the saved one.
		_apply_fps_counter()
	elif key.begins_with("display."):
		apply_display(key == "display.resolution_index")
	elif key.begins_with("a11y."):
		apply_accessibility()
	elif key.begins_with("fx."):
		apply_effects()
	elif key.begins_with("quality."):
		apply_quality()
	elif key == "keybinds":
		apply_keybinds()


func _apply_defaults_for_missing() -> void:
	for k in _defaults.keys():
		if not _data.has(k):
			_data[k] = _defaults[k]


# Limited input-event serialization: keyboard, mouse button, joypad button and
# joypad motion (a trigger or a stick, and which way it was pushed). Good enough
# for v1 rebinding. Game code can override by subclassing.
func _serialize_event(ev) -> Dictionary:
	if ev is InputEventKey:
		return {"t": "key", "keycode": int(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)}
	if ev is InputEventMouseButton:
		return {"t": "mb", "button_index": int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"t": "jb", "button_index": int(ev.button_index)}
	# Triggers and sticks used to come out as {}, so a rebound action lost them on
	# the next launch, and every stick looked like every other one to the dedup.
	if ev is InputEventJoypadMotion:
		return {"t": "jm", "axis": int(ev.axis), "dir": 1 if ev.axis_value >= 0.0 else -1}
	return {}


func _deserialize_event(d) -> InputEvent:
	if not (d is Dictionary):
		return null
	match String(d.get("t", "")):
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = int(d.get("keycode", 0))
			ev.device = -1  # any keyboard, whichever id this engine version gives it
			return ev
		"mb":
			var ev := InputEventMouseButton.new()
			ev.button_index = int(d.get("button_index", 0))
			return ev
		"jb":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(d.get("button_index", 0))
			ev.device = -1  # any pad, not just the first
			return ev
		"jm":
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(d.get("axis", 0)) as JoyAxis
			ev.axis_value = 1.0 if int(d.get("dir", 1)) >= 0 else -1.0
			ev.device = -1
			return ev
	return null
