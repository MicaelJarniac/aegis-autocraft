# A.E.G.I.S. autocraft for CC:Tweaked

A recursive autocrafting system written in vanilla CC:Tweaked Lua.
<details><summary>view screenshot</summary><img src="2026-08-09-20-23-25.png" width="500"></details>

You teach the system by laying out a recipe in a 3x3 pattern in the center of the T.BOX barrel, picking the machine in `+RECIPES`, and hitting SCAN. A.E.G.I.S. saves the recipe to disk and automates it from then on.

Order any end product and the recursive engine builds the full crafting tree, checks your vaults, and crafts all missing dependencies in parallel across your machine banks. Works via standard CC:Tweaked Inventory API and supports complex modded machines, fluid/hybrid recipes, multiblocks, durability tools, and RNG crafts.

---

## Requirements

- **Advanced Computer** — MUST BE PLACED DIRECTLY TO THE LEFT OF THE MONITOR WALL.
- **Advanced Monitors** — Recommended 5x3 or larger (any layout supported).
- **Crafty Turtle** — Advanced Turtle running `turtle/startup.lua` for 3x3 grid recipes.
- **Storage** — Connected chests, vaults, drawers, or tanks.
- **Train Box (T.BOX)** — 1 barrel or chest used as the staging area for recipe teaching and item delivery.
- **Wired Network** — Modems on every machine/chest, connected by cable and activated (red ring on).

---

## Quick Setup

1. Drag `computer/startup.lua` onto the Advanced Computer terminal, drag `turtle/startup.lua` onto your turtle, then  `reboot`.
2. On the monitor, open the **NETWORK** tab and tag your peripherals:
   - Storages → `[VAULT]`
   - Staging barrel → `[T.BOX]`
   - Crafting turtles → `[TURTLE]`
   - Fluid tanks → `[TNK]` (optional)
   <details><summary>view screenshot</summary><img src="2026-08-09-20-36-05.png" width="500"></details>

---

## How to Teach Recipes (+RECIPES)

- **3x3 Crafting Grid**: Lay ingredients in the 3x3 center of T.BOX → `+RECIPES → TURTLE` → SCAN. <details><summary>view screenshot</summary><img src="2026-08-09-20-26-45.png" width="500"></details>
- **Machine Recipes**: Place ingredients in T.BOX → select machine on computer → `+RECIPES → MACHINES` → SCAN. <details><summary>view screenshot</summary><img src="2026-08-09-20-27-09.png" width="500"></details>
- **Fluid & Hybrid**: Put solid items in T.BOX, type fluid type & mB volume on computer → `+RECIPES → FLUID` → SCAN. <details><summary>view screenshot</summary><img src="2026-08-09-20-30-35.png" width="500"></details>
- **Alternatives (+ALT)**: If an item already has a recipe, you can add another as `+ALT`. System checks them top-to-bottom. <details><summary>view screenshot</summary><img src="2026-08-09-20-32-34.png" width="500"></details>
- **Editing Recipes [E]**: Hit `[E]` in the RECIPES tab to swap machines or reassign an entire machine tag across all saved recipes. <details><summary>view screenshot</summary><img src="2026-08-09-20-34-39.png" width="500"></details>

---

## Core Features & Breakdown

### Recursive Engine & Parallel Execution
- **Dependency Trees**: Order a final item and A.E.G.I.S. calculates every raw sub-ingredient needed based on current vault stock.
- **Parallel Crafting**: Independent recipe branches execute at the same time across available machine banks. `parallel X` shows active sub-tasks. <details><summary>view screenshot</summary><img src="2026-08-09-20-48-33.png" width="500"></details>
- **Multi-Machine Batching**: Sub-tasks split workloads evenly across all free machines in a group. `pm3` means 3 machines are processing that task. <details><summary>view screenshot</summary><img src="2026-08-09-20-48-13.png" width="500"></details>
- **RNG Top-Up**: For recipes with probabilistic outputs, the system keeps feeding ingredients until the requested item count is reached.
- **Queueing**: Queue multiple crafts at once. If resources run dry for one item, it flags a warning, skips to the next order, and leaves the skipped craft in queue. <details><summary>view screenshot</summary><img src="2026-08-09-20-50-54.png" width="500"></details>
- **Tool Support**: Uses GT-style durability tools (saws, hammers, files). If a tool breaks mid-craft, A.E.G.I.S. crafts a replacement first, then resumes. <details><summary>view screenshot</summary><img src="2026-08-09-21-13-50.png" width="500"></details>
- **Machine Cleanup & CANCEL**: Clears output slots before sub-tasks and on finish. Hit `CANCEL` to stop a craft and dump output slots to vaults (Note: some mods block CC:Tweaked from pulling out of input slots).<details><summary>view screenshot</summary><img src="2026-08-09-20-44-09.png" width="500"></details>

### Machine Grouping & Multiblocks
- **Auto-Grouping**: Machines with the same peripheral name automatically form a pool. <details><summary>view screenshot</summary><img src="2026-08-09-20-37-29.png" width="500"></details>
- **Custom Groups**: Group specific machines manually (e.g. split Create Depots into `Depot Forge` vs `Depot Press`). (IF YOU ADD CARS TO A CUSTOM GROUP, CAREFULLY EXCLUDE THEM FROM THE AUTOMATIC GROUPING) .<details><summary>view screenshot</summary><img src="2026-08-09-20-39-38.png" width="500"></details>
- **Exclusions & Suffixes**: Exclude specific machines from pools, or add custom visual suffixes (`SUF`) in the NETWORK tab without breaking pooling. <details><summary>view screenshot</summary><img src="2026-08-09-20-25-28.png" width="500"></details>
- **Multiblock Split I/O**: Supports separate input and output hatches on multiblocks. <details><summary>view screenshot</summary><img src="2026-08-09-20-20-44.png" width="500"></details>

### Fluids & Tanks
- **Hybrid & Sequential Pouring**: Handles solid+fluid inputs, mB tracking, and multi-fluid sequential fills. For machines with multiple fluid hatches, route fluids through transfer TANKs with attached hatches. <details><summary>view screenshot</summary><img src="2026-08-09-20-16-47.png" width="500"></details>
- **Stock - Fluid & OPTIMIZE**: View total fluids and tank usage. Hit `OPTIMIZE` to scan, merge, and defrag fluid storage. <details><summary>view screenshot</summary><img src="2026-08-09-20-07-57.png" width="500"></details>
- **KEEP-FLUID**: Set automated mB fluid buffers. <details><summary>view screenshot</summary><img src="2026-08-09-20-06-57.png" width="500"></details>

### KEEP (Auto-Stocking)
- **Hysteresis (Threshold → Target)**: Triggers crafting only when stock drops below threshold, then crafts up to target (RS-trigger logic prevents constant re-crafting spam). <details><summary>view screenshot</summary><img src="2026-08-09-20-05-35.png" width="500"></details>
- **KEEP is executed according to the hierarchy you set, which is higher first <details><summary>view screenshot</summary><img src="2026-08-09-20-51-53.png" width="500"></details>
- **Idle Execution**: Runs automatically when the system is idle for 3 minutes without active manual crafts. Can be paused anytime. <details><summary>view screenshot</summary><img src="2026-08-09-21-00-11.png" width="500"></details>

### Storage & Logistics
- **STOCK & REQ**: Unified view of all connected vaults. Request items directly into T.BOX inactive slots. <details><summary>view screenshot</summary><img src="2026-08-09-20-04-36.png" width="500"></details>
- **Stock OPTIMIZE**: Scans all vaults and merges unstacked item stacks. <details><summary>view screenshot</summary><img src="2026-08-09-20-03-47.png" width="500"></details>
- **LOGICK Transfer Rules**: Replaces item/fluid pipes with rule-based transfers (`Standard`, `Provider` pull-only, and conditional `IF` statements like "move wood if charcoal < 32"). <details><summary>view screenshot</summary><img src="2026-08-09-20-02-54.png" width="500"></details>

### Remote Control & Integrations
- **RedNet Remote**: Run `remote_control` on a pocket computer with an Ender Modem to order items and check live progress from anywhere in loaded chunks. <details><summary>view screenshot</summary><img src="2026-08-09-19-51-42.png" width="500"></details>
- **GitHub Sync**: Export/import your recipe library via GitHub Personal Access Token (masked in UI, cleared from RAM on reboot). <details><summary>view screenshot</summary><img src="2026-08-09-19-51-12.png" width="500"></details>
- **ntfy Push Alerts**: Optional push notifications to your phone when crafts finish. <details><summary>view screenshot</summary><img src="2026-08-09-19-50-38.png" width="500"></details>

---

## Troubleshooting & Important Notes

- **1MB Filesystem Limit**: CC:Tweaked caps total computer directory size to 1MB. If new recipes fail to save or vanish on reboot, your computer folder is full — delete old `.BAK` backup files.
- **Computer Placement**: Advanced Computer MUST be directly to the LEFT of the monitor wall.
- **Mod Inventory Restrictions**: Some modded machines restrict pulling items from input slots. If you cancel a craft, check input slots manually. <details><summary>view screenshot</summary><img src="2026-08-09-21-08-50.png" width="500"></details>
- **Direct Modem Issues**: If a modded block don't care about with CC:Tweaked's Inventory API or modem connection, route items through a standard transfer chest. [The workaround is that your mod doesn't use the API cc tweced](https://www.reddit.com/r/ComputerCraft/comments/1uyx4td/comment/oy8femh/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button)
- **Solid fuel furnace EXPANSION** [ FUEL FURNACE ](https://www.reddit.com/r/ComputerCraft/comments/1uyx4td/comment/oyb7z51/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button)
- **Vault Capacity**: Keep an eye on free vault and tank space at the top of the monitor so collection tasks have room to unload. <details><summary>view screenshot</summary><img src="2026-08-09-20-57-35.png" width="500"></details>

---

Community & Support: https://www.reddit.com/r/ComputerCraft/comments/1uyx4td/aegis_autocraft_for_computercraft_cctweaked/