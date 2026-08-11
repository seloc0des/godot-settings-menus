# Changelog

## 1.3.0 (2026-08-10)

Your saved settings are safe from the pack's own test.

- **Settings can be pointed at a different file.** Where the settings land is no longer fixed, so you can keep a separate set per player profile, or send a test somewhere harmless. Leave it alone and nothing changes. (If you do write scripts: it's `Settings.save_file`, and naming a file also opts out of the Save/Load pack's shared file.)
- **Fixed: running the pack's own self-test wiped your saved settings.** The test resets everything to defaults and re-binds keys on purpose, but it was doing that to your real settings file, so your volume, resolution and key bindings were lost. It now works on a scratch file, deletes it when it's finished, and checks your real one came out untouched. That check runs every time, so it can't come back.
- **The download can't damage a project you're already working on.** It now unzips into one folder named after the pack, instead of scattering files around. Before this, unzipping it straight into an existing game could wipe that game's name, its start-up scene and the list of add-ons you had switched on. It can't reach any of that now. Two plain-text files sit at the top of the folder: **START-HERE.txt** (what's in here, plus the two-minute install) and **INSTALLING.txt** (the longer version, including running several packs side by side).

## 1.2.0 (2026-07-24)

One-click no-code setup.

- New **Menus · Setup** panel (the first dock tab): pick what you want for your game → **Apply** → it's built into your scene and stays fully editable. Re-pick and Apply any time. It updates in place, never duplicates.
- Outcomes: Main menu · Pause menu · Options screen · All three.
- The existing detail-authoring dock stays alongside it as the tuner.

## 1.1.0 (2026-07-23)

No-code editor dock.

- New **Menu Theme** dock: restyle the menu (colors, fonts, spacing) with live UI pickers.
- Test suite: made the default-volume check idempotent.

## 1.0.0 (2026-06-01)

Initial release.

- `Settings` autoload: `get_value` / `set_value` / `reset_to_defaults`, audio bus apply, display apply, key rebind apply, persistence (Save addon side-channel if present, else `user://settings.json`).
- `MenuTheme` Resource: palette, typography, layout, branding (title + subtitle + background texture).
- `MainMenuUI`: Play / Options / Credits / Quit. Configurable scene transition.
- `PauseMenuUI`: pause-action listener, paused tree, Resume / Options / Main Menu / Quit.
- `OptionsMenuUI`: 4 tabs. Audio (master / music / sfx), Display (window mode + resolution + vsync + fps), Controls (one-click key rebind), Accessibility (font scale, colorblind filter, reduce motion).
- `CreditsUI`: multiline credits with `#` headings.
- `KeyRebindRow`: one row, listens for next key/mouse/joypad press.
- Demo: main menu → tiny moveable-square game scene → pause overlay with full options flow.
- 3 docs: quick start, theming, cross-promo (paid systems).
