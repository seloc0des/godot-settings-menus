# Theming

Recolor and rebrand every menu in one swap via a `MenuTheme` Resource.

## Author a theme

Create a new `MenuTheme` Resource in your project. Tweak fields in the Inspector:

| Group | Fields |
|---|---|
| Palette | `bg_color`, `panel_bg`, `panel_border`, `accent`, `accent_hover`, `text`, `text_dim`, `button_bg`, `button_bg_hover`, `button_bg_pressed`, `slider_track`, `slider_fill` |
| Typography | `title_font_size`, `heading_font_size`, `body_font_size`, `button_font_size` |
| Layout | `panel_corner_radius`, `panel_padding`, `menu_max_width` |
| Branding | `game_title`, `game_subtitle`, `background_texture`, `logo_texture` |

## Apply it

Set `theme_data` on each menu Control:

```gdscript
var theme: MenuTheme = preload("res://my_theme.tres")

main_menu.theme_data = theme
pause_menu.theme_data = theme
options_menu.theme_data = theme
credits.theme_data = theme
```

Or set `theme_data` in the Inspector if the menu is a packed scene.

## Background image

Drop a Texture2D into `theme_data.background_texture`. The `MainMenuUI` shows it under a darkening overlay. The others use the flat `bg_color`. For a fully custom background, leave the texture null and put your own setup behind the menu Control in your scene.

## Font

`MenuTheme` doesn't carry a font directly. Drop a stock Godot Theme on the menu Control (or globally via Project → GUI → Theme → Custom Theme) and the menus pick it up. The `font_size_override` calls only affect size, not face.

## Per-platform defaults

If you need different defaults on mobile vs. desktop, swap themes in code before the menu builds:

```gdscript
var theme: MenuTheme
if OS.has_feature("mobile"):
    theme = preload("res://themes/mobile.tres")
else:
    theme = preload("res://themes/desktop.tres")
main_menu.theme_data = theme
```

## Reusing the stylebox helpers

`MenuTheme` exposes helpers for the built-in stylebox shapes. Handy if you're building your own custom UI page (e.g. a stats screen) and want it to match:

```gdscript
var sb := theme.panel_stylebox()
my_panel.add_theme_stylebox_override("panel", sb)
theme.apply_to_button(my_button)
theme.apply_to_checkbox(my_checkbox)
```

`apply_to_checkbox` draws the unticked box as a frame in `text_dim`, so it shows on a dark background. The options menu does this to its own boxes, except a box your own Godot Theme already styles.
