# Upgrade to the selodev RPG Toolkit

This template is free because the rest of the catalog exists. If you've shipped a settings/menus pass and want the systems underneath, here's the full line.

## The selodev no-code stack

Everything below is pure GDScript, Inspector-first, save-aware, and same-bus integrated.

| System | Role |
|---|---|
| **Save / Load** | Atomic save + load with migrations. The contract every other system below opts into. |
| **Inventory** | Shared `ItemResource`, weight + categories, drag-drop, hotbar. Most of the other systems read its items. |
| Equipment | Paper-doll slots, two-handed conflicts, modifier aggregation. |
| Loot | Weighted tables, nested tables, conditions, magic find, pity counter. |
| Crafting | Shaped + shapeless recipes, queue, unlocks. |
| Vendor / Shop | Multi-currency, buyback, restock timers, conditional offers. |
| Quests | 8 objective types, chains, prerequisites, log UI, NPC givers. |
| Stats / Skill Trees | Stat aggregator, visual skill-tree runtime, unlock + respec. |

The **RPG Toolkit** bundles all eight. **SELODEV Complete** adds the rest of the catalog on top: Dialogue, Combat, Controller, Enemy AI, Scene Flow, Audio, Weather, Day/Night, Achievements, Level Builder, Animation Builder and AAA Visuals.

## Why these systems

The systems are designed to compose. Every one of them implements the same save contract, emits modifiers in the same `{stat, op, amount}` shape, and shares a single `Events` autoload bus. You don't write glue code. Drop a component, set a NodePath, you're done.

Most free addons solve one problem. The selodev stack solves the **gap between them**.

## Try the Lite tiers first

Each paid system ships a free **Lite** tier with the working core. Same APIs, same components, just stripped of the production-grade features. If you want to try the wedge before paying, grab a Lite tier first.

## Where to buy

- itch.io: `selodev.itch.io` (primary)
- Godot Asset Store: search "selodev"
- Direct: `selodev.com`

## Stay in the loop

Discord: https://discord.com/invite/vaXGnXHFmC. Roadmap visible. Bug reports welcome. Feature requests go in `#wishlist` and the most-upvoted ones ship.

## License

This template is MIT. Each paid system's license is on its store page.
