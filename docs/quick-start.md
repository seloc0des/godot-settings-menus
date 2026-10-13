# Quick Start

Five minutes from copy to a working main menu → game → pause → options loop.

## 0. Fastest path: the setup panel (no code)

Enable the plugin, open the **Menus · Setup** tab in the editor, pick what your game
needs (main menu, pause menu, options screen, or all three), choose where they land,
and press **Apply**. The menus are spawned and wired into your scene for you. Fill in
*Play loads this scene* while you're there and the main menu's Play button is done. The
`pause` input action is registered for you if your project doesn't have one yet.
The main menu and options screen are set to fill the screen. With **All three**, the
options screen starts hidden so the main menu shows first. The main and pause menus
open their own Options. Re-pick and Apply any time, and it updates in place instead
of duplicating. Restyle everything at once from the sibling **Menu Theme** tab.

The steps below are the manual route if you'd rather build it by hand or understand
each piece.

## 1. Install

1. Copy `addons/settings_menus/` into your project's `addons/` folder.
2. Project → Project Settings → Plugins → enable **Settings + Menus**.
3. Confirm `Settings` appears under Autoload (the plugin registers it).

## 2. Set up the main menu

The **Menus · Setup** panel builds this for you (pick **Main menu** → **Apply**).
By hand, make a new scene whose root is a `MainMenuUI` (a Control derivative):

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

The **Menus · Setup** panel does this for you. Open your gameplay scene, pick
**Pause menu**, press **Apply**. By hand, in your gameplay scene's root script:

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

Effects work the same way, with one wrinkle worth knowing. Ask `is_effect_enabled` rather than reading the key, because Reduce Motion switches camera shake and motion blur off without touching what the player chose, and the key on its own does not know that:

```gdscript
# Nothing here owns your camera or your post-processing, so this pack decides
# and your game applies.
func _ready() -> void:
    Settings.effects_changed.connect(_apply_effects)
    _apply_effects(Settings.get_effects())  # anything connecting now has missed the first one

func _apply_effects(fx: Dictionary) -> void:
    $CameraShake.enabled = fx["camera_shake"]
    $Camera3D.attributes.dof_blur_far_enabled = fx["depth_of_field"]
    $Grain.visible = fx["film_grain"]  # whatever draws yours
```

Depth of field is a Godot property. Film grain and chromatic aberration are not: Godot ships no built-in for either, so they come from your own shader or a visuals addon, which is the same reason this pack publishes the toggle rather than applying it.

The keys are `fx.camera_shake`, `fx.motion_blur`, `fx.chromatic_aberration`, `fx.film_grain` and `fx.depth_of_field`, all on by default so installing this pack does not change how your game looks.

Settings land in `user://settings.json`. They keep their own file on purpose, because settings belong to the player rather than to a save slot, so deleting every slot leaves them intact. Point them somewhere else with `Settings.save_file`, which is useful for per-profile settings and for tests that shouldn't stomp your real ones:

```gdscript
Settings.save_file = "user://profiles/alice_settings.json"
Settings.load_settings()
```

Call `load_settings()` after changing it, as above, or the values in memory stay as they were.

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

Only actions that exist in your InputMap show up. Undefined ones are silently skipped.

Each row has two bindings: a key or mouse button on the left, a gamepad button, trigger or stick on the right. Rebinding one leaves the other alone. A player presses Esc, or Start on a gamepad, to back out.

A binding another of your actions already uses is refused, and the button says which action has it. Keys and buttons that menu navigation uses don't count (Space, Enter, the arrows, and A and B once you put them on `ui_accept` and `ui_cancel`), because games bind those on purpose. To count them too:

```gdscript
Settings.menu_navigation_clashes = true
```

## What's next

- [theming.md](theming.md): recolor / rebrand every menu via a `MenuTheme` Resource.
- [cross-promo.md](cross-promo.md): the paid systems that pair with it.
