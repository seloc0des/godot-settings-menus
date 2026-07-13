class_name CreditsUI
extends Control

# Scrolling credits. Author the text via the `credits_text` export — sections
# headed by # become section headers; everything else is body. A Back button
# returns to the previous menu.

signal close_requested

@export var theme_data: MenuTheme

@export_multiline var credits_text: String = """# Built with
CindieForge Settings + Menus
CindieForge RPG Toolkit (paid expansion — see docs/cross-promo.md)

# Engine
Godot Engine — godotengine.org

# Made by
You, eventually.
"""

var _back_btn: Button


func _ready() -> void:
	if theme_data == null:
		theme_data = MenuTheme.new()
	anchor_right = 1
	anchor_bottom = 1
	_build()
	focus_default()


func focus_default() -> void:
	if _back_btn != null:
		_back_btn.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = theme_data.bg_color
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	add_child(dim)

	var margin := MarginContainer.new()
	margin.anchor_right = 1
	margin.anchor_bottom = 1
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "Credits"
	title.add_theme_font_size_override("font_size", theme_data.heading_font_size)
	title.add_theme_color_override("font_color", theme_data.text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.pressed.connect(_on_close)
	theme_data.apply_to_button(_back_btn)
	header.add_child(_back_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	for raw in credits_text.split("\n"):
		var line := String(raw)
		if line == "":
			body.add_child(_spacer(8))
			continue
		if line.begins_with("# "):
			var hdr := Label.new()
			hdr.text = line.substr(2)
			hdr.add_theme_font_size_override("font_size", theme_data.heading_font_size)
			hdr.add_theme_color_override("font_color", theme_data.accent)
			body.add_child(hdr)
		else:
			var l := Label.new()
			l.text = line
			l.add_theme_font_size_override("font_size", theme_data.body_font_size)
			l.add_theme_color_override("font_color", theme_data.text)
			body.add_child(l)


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _on_close() -> void:
	close_requested.emit()
