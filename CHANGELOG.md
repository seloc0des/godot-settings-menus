# Changelog

## 1.8.2 (2026-10-12)

The tabs show their names on Godot 4.5.

- **The Menus · Setup and Menu Theme tabs were blank on Godot 4.5.** Their tabs beside the Inspector
  had no title, so "open the Menus · Setup tab" pointed at nothing. They are named when the pack
  switches on now. Godot 4.7 was not affected.

## 1.8.1 (2026-10-02)

Reset buttons that reset everything, and triggers that wait to be pressed.

- **A trigger that rests at -1 no longer binds itself.** Some pads report a trigger you're not
  touching as -1, and the gamepad half measured from 0, so the resting trigger read as a full
  press the moment it started listening. It measures from where each stick and trigger sat when
  it started.
- **Reset to Defaults puts rebound controls back straight away.** It cleared the saved bindings
  but left the live ones, so a rebound key stayed rebound until the game restarted.
- **The Controls tab keeps its name after Reset All Bindings.** It came back titled
  "@VBoxContainer@" and a number, and a second reset did nothing. The tab stays where it was, and
  the new Reset All Bindings button takes the focus, so a gamepad still has somewhere to go.
- **Reset All Bindings no longer fills Output with warnings.** It tried Godot's own `ui_` actions
  too, and warned about each one it isn't allowed to change.
- **The self-test survives a gamepad connecting or disconnecting.** Godot 4.5 and 4.7 crash on the
  next pad plugged in or out once an action a pad has pressed is deleted, and the self-test
  deleted the ones it made for its stick and trigger checks. A wireless pad waking up during the
  test, or while its PASS banner showed, crashed it. It empties those actions instead.

## 1.8.0 (2026-10-02)

Rebinding that keeps your gamepad controls, and boxes you can see.

- **Each action has a keyboard half and a gamepad half in Controls.** Rebinding replaced every
  binding on the action with the one you pressed, so a new key took the gamepad's button away.
  The left button takes a key or a mouse button, the right one a gamepad button, trigger or
  stick, and changing one leaves the other alone.
- **Triggers and sticks can be bound.** Push one past about halfway while the gamepad half is
  listening. The menu used to move its focus on the stick instead, and the row ignored triggers.
- **Triggers and sticks are saved.** They were written to the settings file as nothing, so a
  rebound action came back on the next launch without them.
- **Gamepad buttons have names in Controls.** They showed as numbers, so Start read "Joy Btn 6".
  Names follow the pad that's plugged in: the bottom button is A on an Xbox pad, Cross on a
  PlayStation one and B on a Switch. With no pad plugged in, Xbox names.
- **Space, A and B can be bound again.** Rebinding refused anything menu navigation also uses,
  so jump could never go back to Space. A game that wants those kept apart can set
  `Settings.menu_navigation_clashes` to true. B no longer cancels listening in a game that puts
  it on `ui_cancel`. Esc or Start does.
- **Mouse buttons can be bound from the Controls tab.** The menu took the click first, so the row
  never heard it.
- **Binding Space or Enter sticks.** Letting go of the key pressed the focused button, which
  started listening again, so the next key you pressed replaced it.
- **Only one binding listens at a time**, so one key can't land on two actions, and listening
  stops by itself after five seconds.
- **Unticked boxes show on the dark menu.** Godot's own unticked box all but vanished against the
  menu, so Reduce Motion looked like a label. Boxes get a frame in the theme's dim text colour.
  A box your own Godot Theme styles keeps its look.

## 1.7.4 (2026-09-28)

Menus that work from the keyboard, and sliders that work in any project.

- **Keyboard and gamepad work on the main menu from the start.** With All three, the hidden Options
  screen took the focus, so Enter and the arrows did nothing. Menus take focus when they show, and
  Resume hands it back.
- **A new Menu Theme starts with a blank subtitle** instead of the demo's line.
- **Gamepad sticks and triggers have names in Controls**, like Left Stick Left, where a "?" was.
- **Rebinding no longer refuses keys that are free.** F was refused for the editor's Ctrl+F, and H
  for a file dialog shortcut. The check now respects Ctrl, Shift and Alt and ignores text box and
  file dialog shortcuts. Menu navigation keys still count.
- **Volume sliders work in a project without Music and SFX buses.** Every Play warned about them and
  the sliders did nothing. They're made at start with the Audio pack's names and sent to Master, and
  saved levels reach the Audio pack's buses.
- **A file the tab makes is registered with Godot as soon as it's written**, so pressing Play
  straight away can't warn "invalid UID".

## 1.7.3 (2026-09-27)

Installs without errors, and its tab works the moment you switch it on.

- **Its tab works the moment you switch it on.** Right after installing, All three added the main
  and pause menus but no Options screen until you restarted Godot.
- **No red errors when you install it.** Installing it filled the Output panel with "Failed to
  load script" errors before you'd even switched it on. Some of its scripts named a part of the
  pack that only exists once the pack is on.
- **Both tabs fit a default-width dock.** Menus · Setup and Menu Theme fit at any editor scale.
  Headings wrap and both tabs scroll. Menu Theme is one scrolling column now, with the theme list on
  top and the picked theme's settings under it, and a long folder path wraps instead of stretching
  the tab.

## 1.7.2 (2026-09-27)

The one place the old name was still hiding.

- **The demo project's description said CindieForge.** Project Settings showed "Funnel for the
  CindieForge RPG Toolkit" as the demo's description, the one line 1.7.1 missed. It now reads
  "Pairs with the selodev RPG Toolkit", like the plugin's own description.

## 1.7.1 (2026-09-26)

The menus the Setup tab makes now look like menus the moment you press Play.

- **The main menu filled no screen at all.** The Setup tab added it with no layout, so it had
  no background and its buttons sat packed in the top-left corner. Menus from the Setup tab now
  fill the screen. One you've already placed by hand is left alone.
- **"All three" no longer stacks the Options screen on top of the main menu.** It starts hidden,
  the way a game would open it, and the status line says so.
- **Apply stopped running the menus inside the editor.** It built them in a way that ran their
  game code there, which printed a script error and gave each menu a blank theme instead of the
  shipped one. They're added quiet now, like a node you add by hand, with the default theme.
- **Pressing Play right after Apply includes the menus.** The Setup tab never marked the scene
  as changed, so Play ran the version on disk without them unless you saved first.
- **Saving a theme in the Menu Theme tab keeps your scene linked to the file.** Saving used to
  leave any scene using that theme holding an old, orphaned copy, which the scene then saved
  inside itself.
- **Nodes the Setup tab adds get readable names.** A second one under the same parent is
  called something like `UILayer2`, instead of a generated name full of `@` signs.
- **A value changed in the Inspector now survives the Menu Theme tab's Save.** The tab edits its
  own copy of the theme, so a colour, font size or texture changed in the Inspector went back to
  the old value on the next Save. The other packs' tabs got this fix earlier, and this one was missed.
- **The pack says selodev throughout.** The plugin description, the credits screen's default text,
  a new theme's default subtitle, the demo menu and the docs still carried the old CindieForge
  name, and the README and docs had our own marketing notes in them. They describe the pack for you
  now, and the upgrade page links selodev.itch.io, selodev.com and the Discord.
- **The self-test passes inside the Complete bundle.** It assumed nothing else could handle
  graphics quality, so with AAA Visuals installed it failed checks that weren't real. It now hands
  the quality settings to AAA Visuals and back, and borrows the Audio pack's buses instead of
  expecting none. In the pack's own project it tests exactly what it did before.
- **Closing the editor no longer takes the Settings autoload out of project.godot.** The plugin
  removed it on every close and added it back on the next start, so project.godot changed each
  session. Now it adds the autoload once, when it's missing, and switching the plugin off removes
  it only if the plugin was the one that added it. A project that declares the autoload itself,
  like the Complete bundle, keeps it.
- **Closing the editor no longer asks you to save modified resources when you changed nothing.**
  The plugin re-added its autoload on every start, even when it was already there, and Godot counts
  that as an unsaved change.
- **The Menu Theme tab shows its fields in the editor.** After New, or when you opened a theme, it
  showed only its group headings, because the editor loads these files as placeholders and the tab
  skipped every field on one. Its settings are there to edit now, and a change you make saves.

## 1.7.0 (2026-09-10)

A Graphics tab, for the players who need one setting down and the rest left alone.

- **Shadows, textures, effects, view distance and post processing each get their own
  control.** A single low-to-high preset is what most settings menus ship and the standard
  says plainly that it is not enough. Someone dropping shadows to hold a frame rate rarely
  wants their textures dropped as well.
- **The tab only exists when something can act on it.** This pack renders nothing, so it
  remembers the choice and hands the level to whoever is doing the rendering, found by the
  method it offers rather than by the pack it came from. Install the AAA Visuals pack and
  the tab appears wired. Install neither and there is no tab, because five dropdowns that
  move nothing are worse than none.
- **Every axis starts at Follow Preset**, so a project that never opens the tab is
  unaffected, and putting one back is one choice rather than a reset.

## 1.6.0 (2026-09-10)

The effect toggles a settings menu is supposed to have, and Reduce Motion finally doing
something.

- **Camera shake, motion blur, chromatic aberration, film grain and depth of field each
  have their own toggle**, on the Accessibility tab. One switch per effect rather than a
  single post-processing checkbox, because the reason someone turns off camera shake is
  motion sickness and the reason they turn off film grain is taste, and a single switch
  makes them trade one for the other. All five default to on, so enabling the pack does
  not change how a game already looks.
- **Reduce Motion is read by something now.** It was a saved boolean that nothing
  consulted. It switches camera shake and motion blur off, leaves the other three alone,
  and does it without overwriting what the player chose, so turning it off again gives
  them back the settings they had rather than defaults. The two boxes it governs grey out
  and show off while it is on, instead of sitting there ticked next to an effect that is
  not running.
- **`Settings.is_effect_enabled("film_grain")`** answers for your game, folding the toggle
  and Reduce Motion together so no caller has to remember which effects Reduce Motion is
  meant to gate. `get_effects()` returns the lot in one dictionary. Nothing in this pack
  owns a camera or a post pass, so the new `effects_changed` signal is where your game
  picks the work up. Watch that rather than `setting_changed`: Reduce Motion changes what
  is running without changing any effect key, and a listener filtering on `fx.` would miss
  half of it.

## 1.5.0 (2026-09-09)

Two fixes that outrank everything else in this pack. Both are the kind of thing you only
find out about from a player who has already lost something.

- **A crash while settings were being saved no longer loses all of them.** The old write
  opened the real file, which truncates it, so the previous settings were gone the instant
  a write began. Die anywhere in the middle and the player lost every choice they had ever
  made, not the last few seconds of them. Sliders write often, so the window was not small.
  Settings are now written to a scratch file, checked, and moved into place only once they
  are whole. A scratch file left behind by a crash is picked up on the next load if it is
  complete, and discarded if it is not.
- **The pause menu can now be opened on a gamepad.** The pause action was bound to Escape
  and nothing else, so a player using a controller alone could never open the pause menu,
  and the pause menu is the only way to reach the settings that would have let them fix it.
  It is Escape and Start now. If you already have a pause action with only a key on it,
  enabling the pack adds the gamepad button and leaves everything you bound alone.

## 1.4.1 (2026-09-09)

Documentation that matches the code again.

- **The README and the quick start no longer describe a Save/Load hand-off.** That path was
  removed in 1.4.0, and both pages still promised it. Settings keep their own file on
  purpose, because they belong to the player rather than to a save slot, so deleting every
  slot leaves them intact. The text says that now.
- The demo window title uses the same separator as the rest of the catalogue.

## 1.4.0 (2026-08-22)

Settings that actually report when they can't be saved.

- **Settings failing to save is now reported.** The check meant to catch a failed write was asking the wrong question and always came back clean, so a full disk or a read-only folder lost your settings silently. It now measures what actually reached the file.
- **Removed a Save/Load hand-off that never happened.** The code tried to pass settings to the Save/Load pack through a pair of methods that pack has never had, so the attempt was skipped every time and settings went to their own file anyway. Behaviour is unchanged. The comment that promised otherwise is gone, and settings staying in their own file is the right thing regardless: they belong to the player, not to a save slot, so deleting every slot leaves them intact.
- **Dragging a slider no longer rewrites the settings file on every frame of the drag.** Each write empties the file before refilling it, so a drag left a stream of moments where the settings file was blank on disk. Changes are now collected and written once the player stops moving, and anything still waiting is written out when the game closes.
- The demo project targets Godot 4.5, matching the rest of the catalogue.
- The bundled self-test no longer prints leaked-object errors after passing, and now covers saving, reloading and recovering from a damaged settings file.

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
