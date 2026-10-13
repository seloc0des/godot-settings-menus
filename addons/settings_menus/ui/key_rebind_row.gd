class_name KeyRebindRow
extends HBoxContainer

# One row in the controls tab: the action's name, its keyboard and mouse binding,
# and its gamepad binding. Click either one and press the new input. Each half is
# rebound on its own. One button used to replace every binding on the action, so
# setting a new key took the pad's binding away with it.

signal rebound(action: String)

## How far a trigger or stick has to go before it counts: past any drift, short of
## a full push.
const AXIS_PRESS := 0.6
## Listening gives up by itself after this long, so a pad player who opened it by
## accident isn't stuck with it.
const LISTEN_SECONDS := 5.0
## Every row is in this group, so only one listens at a time.
const ROWS := &"key_rebind_rows"

# Pad buttons as [Xbox, PlayStation, Nintendo] name them, the way the Controller pack
# does. The family matters because of the Nintendo swap: Godot numbers the bottom
# face button 0 on every pad, and on a Switch that one says B. Used to read "Joy Btn 0".
const PAD_NAMES := {
	JOY_BUTTON_A: ["A", "Cross", "B"],
	JOY_BUTTON_B: ["B", "Circle", "A"],
	JOY_BUTTON_X: ["X", "Square", "Y"],
	JOY_BUTTON_Y: ["Y", "Triangle", "X"],
	JOY_BUTTON_BACK: ["View", "Create", "Minus"],
	JOY_BUTTON_GUIDE: ["Guide", "PS", "Home"],
	JOY_BUTTON_START: ["Menu", "Options", "Plus"],
	JOY_BUTTON_LEFT_STICK: ["L3", "L3", "LS"],
	JOY_BUTTON_RIGHT_STICK: ["R3", "R3", "RS"],
	JOY_BUTTON_LEFT_SHOULDER: ["LB", "L1", "L"],
	JOY_BUTTON_RIGHT_SHOULDER: ["RB", "R1", "R"],
	JOY_BUTTON_DPAD_UP: ["D-Pad Up", "D-Pad Up", "D-Pad Up"],
	JOY_BUTTON_DPAD_DOWN: ["D-Pad Down", "D-Pad Down", "D-Pad Down"],
	JOY_BUTTON_DPAD_LEFT: ["D-Pad Left", "D-Pad Left", "D-Pad Left"],
	JOY_BUTTON_DPAD_RIGHT: ["D-Pad Right", "D-Pad Right", "D-Pad Right"],
}

@export var action: String = ""
@export var theme_data: MenuTheme

var _label: Label
var _key_btn: Button
var _pad_btn: Button
var _reset_btn: Button
var _listening := ""  # "", "key" or "pad"
var _listen_left := 0.0
var _rest := {}  # Vector2i(device, axis) -> where it sat when listening began


func _ready() -> void:
	if theme_data == null:
		theme_data = MenuTheme.new()
	add_to_group(ROWS)
	set_process(false)
	add_theme_constant_override("separation", 8)
	_label = Label.new()
	_label.text = _humanize(action)
	_label.add_theme_font_size_override("font_size", theme_data.body_font_size)
	_label.add_theme_color_override("font_color", theme_data.text)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)

	_key_btn = _bind_button("Key", "key", "Keyboard or mouse")
	_pad_btn = _bind_button("Pad", "pad", "Gamepad")

	_reset_btn = Button.new()
	_reset_btn.name = "Reset"
	_reset_btn.text = "↺"
	_reset_btn.tooltip_text = "Reset to default"
	_reset_btn.pressed.connect(_reset)
	_reset_btn.custom_minimum_size = Vector2(34, 0)
	theme_data.apply_to_button(_reset_btn)
	add_child(_reset_btn)
	# a method, not a lambda: a lambda left on Input when the row goes crashes the exit
	Input.joy_connection_changed.connect(_on_pads_changed)
	_show()


func _bind_button(node_name: String, half: String, tip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(160, 0)
	b.pressed.connect(_listen.bind(half))
	theme_data.apply_to_button(b)
	add_child(b)
	return b


func _process(delta: float) -> void:
	_listen_left -= delta
	if _listen_left <= 0.0:
		_stop()


# _input, not _unhandled_input: the menu moves its focus on the stick and the d-pad
# before an unhandled pass sees them, so a stick never reached the row. A focused
# button acts on Space, Enter and A as well: Space bound itself, then its release
# pressed the button and started listening all over again.
func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	if not is_visible_in_tree():
		_stop()  # the menu closed under us. Its next key belongs to the game
		return
	if _is_cancel(event):
		var btn := _key_btn if _listening == "key" else _pad_btn
		_stop()
		btn.grab_focus()
		get_viewport().set_input_as_handled()
		return
	var got := _heard(event)
	if got != null:
		get_viewport().set_input_as_handled()
		_commit(got)
	elif _belongs(event, _listening):
		# a stick nudged short of a press is still meant for this row. Let it
		# through and the menu walks the focus off somewhere else
		get_viewport().set_input_as_handled()


func _listen(half: String) -> void:
	# one row at a time, or a key meant for this one could land on another
	get_tree().call_group(ROWS, "_stop")
	_listening = half
	_listen_left = LISTEN_SECONDS
	set_process(true)
	# Some pads rest a trigger at -1. Counted from 0, that trigger's resting end read as
	# a full press and bound itself, so note where every axis sits before anyone pushes.
	_rest.clear()
	if half == "pad":
		for device in 16:
			for axis in JOY_AXIS_MAX:
				_rest[Vector2i(device, axis)] = Input.get_joy_axis(device, axis as JoyAxis)
	if half == "key":
		_key_btn.text = "Press a key…"
	else:
		_pad_btn.text = "Press a button…"


func _stop() -> void:
	_listening = ""
	set_process(false)
	_show()


# A pad plugged in or out changes what its buttons are called.
func _on_pads_changed(_device: int, _connected: bool) -> void:
	if _listening == "":
		_show()


# Esc gives up either half, and Start gives up the pad half, since a pad has no
# Esc. B doesn't: a game puts dodge or back on it on purpose, so it has to be
# something you can bind.
func _is_cancel(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.is_action_pressed("ui_cancel")
	return _listening == "pad" and event is InputEventJoypadButton and event.pressed \
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START


# The binding to store for what the listening half just heard, or null if it isn't
# a press for that half. Built the way Settings loads one back, for any keyboard or
# any pad, so it works the same before and after a restart.
func _heard(event: InputEvent) -> InputEvent:
	if _listening == "key":
		if event is InputEventKey and event.pressed and not event.echo:
			var key := event as InputEventKey
			var k := InputEventKey.new()
			k.physical_keycode = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			k.device = -1
			return k
		if event is InputEventMouseButton and event.pressed:
			var m := InputEventMouseButton.new()
			m.button_index = (event as InputEventMouseButton).button_index
			return m
		return null
	if event is InputEventJoypadButton and event.pressed:
		var b := InputEventJoypadButton.new()
		b.button_index = (event as InputEventJoypadButton).button_index
		b.device = -1
		return b
	if event is InputEventJoypadMotion and _pushed(event as InputEventJoypadMotion):
		var j := InputEventJoypadMotion.new()
		j.axis = (event as InputEventJoypadMotion).axis
		j.axis_value = signf((event as InputEventJoypadMotion).axis_value)
		j.device = -1
		return j
	return null


# Far enough out, and far enough from where it sat when listening began.
func _pushed(m: InputEventJoypadMotion) -> bool:
	var rest: float = _rest.get(Vector2i(m.device, m.axis), 0.0)
	return absf(m.axis_value) >= AXIS_PRESS and absf(m.axis_value - rest) >= AXIS_PRESS


func _commit(got: InputEvent) -> void:
	var half := _listening
	_stop()
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	# Conflict check: if the captured event is already bound to another
	# action, refuse the rebind and surface the clash in the button label
	# rather than silently double-binding (which would break the conflicting
	# action's input handling). The game can wire its own resolution UI by
	# listening for `rebound` and reading find_conflicting_action() itself.
	var other: String = settings.find_conflicting_action(got, action)
	if other != "":
		var btn := _key_btn if half == "key" else _pad_btn
		btn.text = "%s used by %s" % [_format_event(got), _humanize(other)]
		# Restore label after a short pause so the user sees the message
		# without it becoming permanent.
		get_tree().create_timer(1.8).timeout.connect(func():
			if is_instance_valid(self) and _listening == "":
				_show())
		return
	# Only this half changes. The other device's bindings stay as they were.
	var events: Array = []
	for ev in InputMap.action_get_events(action):
		if not _belongs(ev, half):
			events.append(ev)
	events.append(got)
	settings.set_keybind(action, events)
	_show()
	rebound.emit(action)


func _reset() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.reset_keybind(action)
	_stop()
	rebound.emit(action)


# Keyboard and mouse are one half, the pad the other. Anything else on the action
# (touch, say) belongs to neither and is never touched.
static func _belongs(ev: InputEvent, half: String) -> bool:
	if half == "pad":
		return ev is InputEventJoypadButton or ev is InputEventJoypadMotion
	return ev is InputEventKey or ev is InputEventMouseButton


func _show() -> void:
	_key_btn.text = _half_label("key")
	_pad_btn.text = _half_label("pad")


func _half_label(half: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	var parts: Array = []
	for ev in InputMap.action_get_events(action):
		if _belongs(ev, half):
			parts.append(_format_event(ev))
	if parts.is_empty():
		return "Unbound"
	return ", ".join(parts)


func _format_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var key_str := OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)
		return key_str
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "Left Click"
			MOUSE_BUTTON_RIGHT: return "Right Click"
			MOUSE_BUTTON_MIDDLE: return "Middle Click"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		return "Mouse %d" % ev.button_index
	if ev is InputEventJoypadButton:
		return _pad_name(ev.button_index, _first_pad_name())
	if ev is InputEventJoypadMotion:
		return _format_axis(ev.axis, ev.axis_value)
	return "?"


static func _pad_name(button: int, joy_name: String) -> String:
	var row: Array = PAD_NAMES.get(button, [])
	if row.is_empty():
		return "Button %d" % button
	return row[_pad_family(joy_name)]


# Which column of PAD_NAMES, off the pad's reported name. Substring matching, the
# Controller pack's, because drivers name pads however they like. Xbox when there's
# no pad or one it doesn't know, since most PC pads follow Xbox names.
static func _pad_family(joy_name: String) -> int:
	var n := joy_name.to_lower()
	for hint in ["nintendo", "switch", "joy-con", "joycon", "pro controller"]:
		if n.contains(hint):
			return 2
	for hint in ["dualsense", "dualshock", "playstation", "ps5", "ps4", "ps3", "sony"]:
		if n.contains(hint):
			return 1
	return 0


static func _first_pad_name() -> String:
	var pads := Input.get_connected_joypads()
	return Input.get_joy_name(pads[0]) if not pads.is_empty() else ""


# Sticks and triggers, named the way the Controller pack names them. Used to be "?".
func _format_axis(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "Left Stick " + ("Right" if value > 0.0 else "Left")
		JOY_AXIS_LEFT_Y: return "Left Stick " + ("Down" if value > 0.0 else "Up")
		JOY_AXIS_RIGHT_X: return "Right Stick " + ("Right" if value > 0.0 else "Left")
		JOY_AXIS_RIGHT_Y: return "Right Stick " + ("Down" if value > 0.0 else "Up")
		JOY_AXIS_TRIGGER_LEFT: return "Left Trigger"
		JOY_AXIS_TRIGGER_RIGHT: return "Right Trigger"
	return "Axis %d %s" % [axis, "+" if value > 0.0 else "-"]


func _humanize(s: String) -> String:
	return s.replace("_", " ").capitalize()
