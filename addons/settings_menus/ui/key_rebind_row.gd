class_name KeyRebindRow
extends HBoxContainer

# One row in the controls tab. Shows action name + current binding. Click the
# binding button → enters listen mode → next key/mouse/joypad press is
# captured and stored.

signal rebound(action: String)

@export var action: String = ""
@export var theme_data: MenuTheme

var _label: Label
var _bind_btn: Button
var _reset_btn: Button
var _listening: bool = false


func _ready() -> void:
	if theme_data == null:
		theme_data = MenuTheme.new()
	add_theme_constant_override("separation", 8)
	_label = Label.new()
	_label.text = _humanize(action)
	_label.add_theme_font_size_override("font_size", theme_data.body_font_size)
	_label.add_theme_color_override("font_color", theme_data.text)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)

	_bind_btn = Button.new()
	_bind_btn.text = _current_label()
	_bind_btn.pressed.connect(_start_listen)
	_bind_btn.custom_minimum_size = Vector2(160, 0)
	theme_data.apply_to_button(_bind_btn)
	add_child(_bind_btn)

	_reset_btn = Button.new()
	_reset_btn.text = "↺"
	_reset_btn.tooltip_text = "Reset to default"
	_reset_btn.pressed.connect(_reset)
	_reset_btn.custom_minimum_size = Vector2(34, 0)
	theme_data.apply_to_button(_reset_btn)
	add_child(_reset_btn)


func _unhandled_input(event: InputEvent) -> void:
	if not _listening:
		return
	# Esc cancels listen mode without rebinding, so keyboard users aren't
	# trapped if they click the bind button by accident.
	if event.is_action_pressed("ui_cancel"):
		_listening = false
		_bind_btn.text = _current_label()
		_bind_btn.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_capture([event])
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_capture([event])
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		_capture([event])
		get_viewport().set_input_as_handled()


func _start_listen() -> void:
	_listening = true
	_bind_btn.text = "Press a key…"


func _capture(events: Array) -> void:
	_listening = false
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		_bind_btn.text = _current_label()
		return
	# Conflict check: if the captured event is already bound to another
	# action, refuse the rebind and surface the clash in the button label
	# rather than silently double-binding (which would break the conflicting
	# action's input handling). The game can wire its own resolution UI by
	# listening for `rebound` and reading find_conflicting_action() itself.
	if not events.is_empty() and events[0] is InputEvent:
		var other: String = settings.find_conflicting_action(events[0], action)
		if other != "":
			_bind_btn.text = "%s used by %s" % [_format_event(events[0]), _humanize(other)]
			# Restore label after a short pause so the user sees the message
			# without it becoming permanent.
			get_tree().create_timer(1.8).timeout.connect(func():
				if is_instance_valid(self) and is_instance_valid(_bind_btn):
					_bind_btn.text = _current_label())
			return
	settings.set_keybind(action, events)
	_bind_btn.text = _current_label()
	rebound.emit(action)


func _reset() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.reset_keybind(action)
	_bind_btn.text = _current_label()
	rebound.emit(action)


func _current_label() -> String:
	if not InputMap.has_action(action):
		return "—"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "Unbound"
	var parts: Array = []
	for ev in events:
		parts.append(_format_event(ev))
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
		return "Joy Btn %d" % ev.button_index
	return "?"


func _humanize(s: String) -> String:
	return s.replace("_", " ").capitalize()
