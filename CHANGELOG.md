# Changelog

## 1.0.0 — 2026-06-01

Initial release.

- `Settings` autoload: `get_value` / `set_value` / `reset_to_defaults`, audio bus apply, display apply, key rebind apply, persistence (Save addon side-channel if present, else `user://settings.json`).
- `MenuTheme` Resource: palette, typography, layout, branding (title + subtitle + background texture).
- `MainMenuUI`: Play / Options / Credits / Quit. Configurable scene transition.
- `PauseMenuUI`: pause-action listener, paused tree, Resume / Options / Main Menu / Quit.
- `OptionsMenuUI`: 4 tabs — Audio (master / music / sfx), Display (window mode + resolution + vsync + fps), Controls (one-click key rebind), Accessibility (font scale, colorblind filter, reduce motion).
- `CreditsUI`: multiline credits with `#` headings.
- `KeyRebindRow`: one row, listens for next key/mouse/joypad press.
- Demo: main menu → tiny moveable-square game scene → pause overlay with full options flow.
- 3 docs: quick start, theming, cross-promo (paid systems).
