# Settings + Menus

Free, polished main menu / pause / options / credits template for Godot 4.5+. Persistent settings, audio buses, resolution + window mode, key rebinding, accessibility (font scale, colorblind filter, reduce motion).

This is the **top-of-funnel** for the selodev RPG Toolkit. Built to give away. Maaack's templates dominate the space. This one is here so you have a polished selodev-themed alternative if you've already bought into the rest of the toolkit, and because shipping it free with cross-promo links is the cheapest user-acquisition channel we have.

## What's inside

```
addons/settings_menus/    ← copy this folder into your project
demo/                     ← runnable main-menu → game → pause loop
docs/                     ← quick start + theming + cross-promo
LICENSE
CHANGELOG.md
```

## 5-minute install

1. Copy `addons/settings_menus/` into your project's `addons/` folder.
2. Project → Project Settings → Plugins → enable **Settings + Menus**.
3. Set your main scene to a script that instantiates `MainMenuUI` (or use a packed scene with one as the root, see `demo/main_menu_scene.tscn`).
4. Set `play_scene_path` to your gameplay scene.
5. Drop a `PauseMenuUI` into your gameplay scene root.
6. Press Play.

See [docs/quick-start.md](docs/quick-start.md) for the worked example.

## Features

- `MainMenuUI`: Play / Options / Credits / Quit, configurable scene path.
- `PauseMenuUI`: listens for the `pause` action and pauses the tree. Resume / Options / Main Menu / Quit.
- `OptionsMenuUI`: tabbed. Audio (master / music / sfx buses), Display (window mode + resolution + vsync + fps counter), Controls (one-click key rebind for any project action), Accessibility (font scale, colorblind filter, reduce motion).
- `CreditsUI`: scrolling credits authored as a single multiline string with `#` headings.
- `KeyRebindRow`: drop-in row for one rebindable action. Used by the Controls tab, and reusable in your own UIs.
- `MenuTheme` Resource: recolor every menu in one swap. Brand title + subtitle + background.
- `Settings` autoload: settings dict with `get_value` / `set_value` / `reset_to_defaults`, persistence (uses Save addon if installed, falls back to `user://settings.json`, redirect with `Settings.save_file`).
- Key rebinding persisted as serialized events. Keyboard / mouse buttons / joypad buttons supported.

## Status

v1.4.0. Tested against Godot 4.5+ (verified on 4.5 and 4.7). Pure GDScript. MIT licensed.

## License

MIT. See `LICENSE`.

## Want more?

This addon is the funnel. If you want the rest of the systems (Save, Inventory, Equipment, Loot, Crafting, Vendor, Quests, Stats / Skill Trees), see [docs/cross-promo.md](docs/cross-promo.md).

---

## Part of a family

The free Lite tier of one system in a set of Godot 4 RPG systems built to
interoperate (shared item + save contracts) — each also works fully standalone.

**Free tiers — try before you buy:**

- [Inventory Lite](https://github.com/seloc0des/godot-inventory-lite) — item slots, stack merging, capacity
- [Equipment Lite](https://github.com/seloc0des/godot-equipment-lite) — 4-slot gear manager
- [Save/Load Lite](https://github.com/seloc0des/godot-save-load-lite) — single-slot JSON persistence
- [Crafting Lite](https://github.com/seloc0des/godot-crafting-lite) — shapeless instant recipes
- [Quests Lite](https://github.com/seloc0des/godot-quests-lite) — COLLECT + KILL quests
- [Stats/Skills Lite](https://github.com/seloc0des/godot-stats-skills-lite) — stat aggregator
- [Vendor Lite](https://github.com/seloc0des/godot-vendor-lite) — single fixed-currency shop
- [Settings + Menu System](https://github.com/seloc0des/godot-settings-menus) — complete, free, no paid tier

**Full versions** — drop-in UI, weight/categories, timed crafting, restock & currencies,
save-aware cross-system integration, and more — are on itch.io:
**https://selodev.itch.io**
