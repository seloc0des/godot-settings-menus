# Quick Start

Five minutes from copy to a working main menu → game → pause → options loop.

## 1. Install

1. Copy `addons/settings_menus/` into your project's `addons/` folder.
2. Project → Project Settings → Plugins → enable **Settings + Menus**.
3. Confirm `Settings` appears under Autoload (the plugin registers it).

## 2. Set up the main menu

Make a new scene whose root is a `MainMenuUI` (a Control derivative):

```gdscript
extends Node

const MainMenuUIScript := preload("res://addons/settings_menus/ui/main_menu_ui.gd")
const MenuThemeScript := preload("res://addons/settings_menus/resources/menu_theme.gd")

func _ready() -> void:
    var menu: MainMenuUI = MainMenuUIScript.new()
    var theme: MenuTheme = MenuThemeScript.new()
    theme.game_title = "Your Game"
    theme.game_subtitle = "A short tag line."
    menu.theme_data = theme
    menu.play_scene_path = "res://scenes/world.tscn"
    menu.anchor_right = 1
    menu.anchor_bottom = 1
    add_child(menu)
```

Project Settings → Application → Run → Main Scene → point to this scene.

## 3. Wire pause into your game

In your gameplay scene's root script:

```gdscript
const PauseMenuUIScript := preload("res://addons/settings_menus/ui/pause_menu_ui.gd")
const MenuThemeScript := preload("res://addons/settings_menus/resources/menu_theme.gd")

func _ready() -> void:
    var pause: PauseMenuUI = PauseMenuUIScript.new()
    pause.theme_data = MenuThemeScript.new()
    pause.main_menu_scene_path = "res://scenes/main_menu.tscn"
    add_child(pause)
```

The pause overlay listens for the `pause` input action (Esc by default) and toggles the tree's `paused` state. If you want a different key, change the `pause_action` export on the `PauseMenuUI`.

## 4. Reading settings in your game

The `Settings` autoload is the source of truth:

```gdscript
# Read.
var master_vol := Settings.get_value("audio.master", 1.0)
var font_scale := Settings.get_font_scale()
var cb_filter := Settings.get_colorblind_filter()

# Write (persists immediately, fires setting_changed).
Settings.set_value("audio.music", 0.5)

# Listen for changes.
Settings.setting_changed.connect(func(key, value):
    if key == "a11y.font_scale":
        _rebuild_my_hud(value))
```

## 5. Custom settings

The Settings autoload stores anything. Add your own key in a script that runs before _ready completes:

```gdscript
# In your game's bootstrap autoload:
func _ready() -> void:
    Settings.set_default("game.difficulty", 1)
    Settings.set_default("game.tutorial_seen", false)
```

Then write a custom UI page (or extend `OptionsMenuUI` with another tab) and let players adjust them.

## 6. Rebindable actions

Add your action ids to `Settings.rebindable_actions` if you want them to surface in the Controls tab. The defaults are `move_left`, `move_right`, `move_up`, `move_down`, `jump`, `attack`, `interact`, `inventory`, `pause`.

```gdscript
Settings.rebindable_actions = PackedStringArray([
    "move_left", "move_right", "jump", "attack", "interact",
])
```

Only actions that exist in your InputMap show up — undefined ones are silently skipped.

## What's next

- [theming.md](theming.md) — recolor / rebrand every menu via a `MenuTheme` Resource.
- [cross-promo.md](cross-promo.md) — the paid systems this funnel exists to advertise.
