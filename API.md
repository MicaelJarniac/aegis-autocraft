# A.E.G.I.S scripting API

A small Lua API under the `aegis.*` namespace - for other in-game computers, turtles and pocket clients to query stock, look up recipes, kick off crafts and follow their progress.

Every method is reachable two ways: as a direct Lua call on the A.E.G.I.S. computer itself, or over RedNet on protocol `aegis_remote` using the `rpc` envelope described [below](#remote-calls-rpc).

The API is intentionally thin - it forwards to the same internals the on-monitor UI uses, so anything you can do by tapping the screen you can also drive from code.

---

## Storage

Everything about what's currently in the vaults.

<table border="0" cellspacing="0" cellpadding="8" style="border-collapse:collapse;border:0;background:transparent;">
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><b>Method</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Args</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Returns</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Notes</b></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.storage.count(name)</code></td>
<td valign="top" style="border:0;background:transparent;">item id</td>
<td valign="top" style="border:0;background:transparent;">number</td>
<td valign="top" style="border:0;background:transparent;">Effective stock including group alternatives. Can be larger than <code>storage.list()[name]</code>.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.storage.list()</code></td>
<td valign="top" style="border:0;background:transparent;">-</td>
<td valign="top" style="border:0;background:transparent;"><code>stock, totalItems, vaults, freeSlots, totalSlots</code></td>
<td valign="top" style="border:0;background:transparent;">Five returns; the first is <code>{[name]=count}</code>. Cached snapshot with ~4 s TTL.</td>
</tr>
</table>

---

## Recipes

The item recipe library - primary recipes and any ALTs attached to them.

<table border="0" cellspacing="0" cellpadding="8" style="border-collapse:collapse;border:0;background:transparent;">
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><b>Method</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Args</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Returns</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Notes</b></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.recipes.get(name)</code></td>
<td valign="top" style="border:0;background:transparent;">item id</td>
<td valign="top" style="border:0;background:transparent;">recipe or <code>nil</code></td>
<td valign="top" style="border:0;background:transparent;">Primary recipe for the item.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.recipes.list()</code></td>
<td valign="top" style="border:0;background:transparent;">-</td>
<td valign="top" style="border:0;background:transparent;"><code>{[name]=recipe}</code></td>
<td valign="top" style="border:0;background:transparent;">Every known item recipe.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.recipes.alts(name)</code></td>
<td valign="top" style="border:0;background:transparent;">item id</td>
<td valign="top" style="border:0;background:transparent;">array or <code>nil</code></td>
<td valign="top" style="border:0;background:transparent;">Alternative recipes attached to the same item.</td>
</tr>
</table>

---

## Fluids

Fluid recipes and current tank contents. Keys come in two shapes - see [Gotchas](#gotchas) before mixing them.

<table border="0" cellspacing="0" cellpadding="8" style="border-collapse:collapse;border:0;background:transparent;">
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><b>Method</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Args</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Returns</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Notes</b></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.fluids.get(fk)</code></td>
<td valign="top" style="border:0;background:transparent;">internal key, e.g. <code>"f:create:water"</code></td>
<td valign="top" style="border:0;background:transparent;">recipe or <code>nil</code></td>
<td valign="top" style="border:0;background:transparent;">Takes the internal fluid key. For a plain fluid name use <code>producers(name)</code> instead.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.fluids.list()</code></td>
<td valign="top" style="border:0;background:transparent;">-</td>
<td valign="top" style="border:0;background:transparent;"><code>{[fk]=recipe}</code></td>
<td valign="top" style="border:0;background:transparent;">All fluid recipes, keyed by internal <code>fk</code>.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.fluids.producers(name)</code></td>
<td valign="top" style="border:0;background:transparent;">plain item or fluid id</td>
<td valign="top" style="border:0;background:transparent;">array</td>
<td valign="top" style="border:0;background:transparent;">Every recipe that outputs <code>name</code>, whether as a fluid or as an item side-output.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.fluids.inventory()</code></td>
<td valign="top" style="border:0;background:transparent;">-</td>
<td valign="top" style="border:0;background:transparent;"><code>{[fk]=amount}</code></td>
<td valign="top" style="border:0;background:transparent;">Cached fluid snapshot, keyed by internal <code>fk</code>.</td>
</tr>
</table>

---

## Craft

Ask the planner what's craftable, and enqueue a craft. Nothing here blocks - `start` just adds to the queue.

<table border="0" cellspacing="0" cellpadding="8" style="border-collapse:collapse;border:0;background:transparent;">
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><b>Method</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Args</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Returns</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Notes</b></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.craft.max(name)</code></td>
<td valign="top" style="border:0;background:transparent;">item or fluid id</td>
<td valign="top" style="border:0;background:transparent;">number</td>
<td valign="top" style="border:0;background:transparent;">Planner estimate off the cached stock. <b>Not</b> a reservation and not a guarantee of successful execution.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.craft.canMake(name, n)</code></td>
<td valign="top" style="border:0;background:transparent;">id, <code>n = 1</code></td>
<td valign="top" style="border:0;background:transparent;">boolean</td>
<td valign="top" style="border:0;background:transparent;">Shortcut for <code>max(name) >= n</code>. <code>n</code> defaults to 1.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.craft.start(name, n, opts)</code></td>
<td valign="top" style="border:0;background:transparent;">id, n, <code>{run = true}</code></td>
<td valign="top" style="border:0;background:transparent;">queue index, or <code>nil, err</code></td>
<td valign="top" style="border:0;background:transparent;">Enqueues an item or fluid craft. <code>n</code> is floored and clamped to <code>>= 1</code>. <code>run = false</code> enqueues silently; <code>run = true</code> asks the main loop to drain the queue on the next idle tick (still not synchronous).</td>
</tr>
</table>

---

## Jobs

Follow what's running, drop a queued entry, or cancel the current craft.

<table border="0" cellspacing="0" cellpadding="8" style="border-collapse:collapse;border:0;background:transparent;">
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><b>Method</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Args</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Returns</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Notes</b></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.jobs.status()</code></td>
<td valign="top" style="border:0;background:transparent;">-</td>
<td valign="top" style="border:0;background:transparent;">snap table</td>
<td valign="top" style="border:0;background:transparent;">Full picture of the queue and current run - shape below.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.jobs.queue()</code></td>
<td valign="top" style="border:0;background:transparent;">-</td>
<td valign="top" style="border:0;background:transparent;">array</td>
<td valign="top" style="border:0;background:transparent;">Live internal table, not a copy. Treat as read-only.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>aegis.jobs.cancel(idx?)</code></td>
<td valign="top" style="border:0;background:transparent;">optional index</td>
<td valign="top" style="border:0;background:transparent;">boolean</td>
<td valign="top" style="border:0;background:transparent;">With no argument, cooperatively cancels the running craft and breaks out of <code>runQueueAll</code>. With an index, drops that queue entry.</td>
</tr>
</table>

### Status snap shape

<table border="0" cellspacing="0" cellpadding="8" style="border-collapse:collapse;border:0;background:transparent;">
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><b>Field</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Type</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Meaning</b></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>busy</code></td>
<td valign="top" style="border:0;background:transparent;">boolean</td>
<td valign="top" style="border:0;background:transparent;">System is not <code>IDLE</code>.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>keepPaused</code></td>
<td valign="top" style="border:0;background:transparent;">boolean</td>
<td valign="top" style="border:0;background:transparent;">Autostock is disabled.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>epoch</code></td>
<td valign="top" style="border:0;background:transparent;">integer</td>
<td valign="top" style="border:0;background:transparent;">Stock version counter - bumps whenever inventory changes.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>queue</code></td>
<td valign="top" style="border:0;background:transparent;"><code>{{name, count}, ...}</code></td>
<td valign="top" style="border:0;background:transparent;">Pending queue entries.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>job</code></td>
<td valign="top" style="border:0;background:transparent;"><code>{name, done, total, pct}</code></td>
<td valign="top" style="border:0;background:transparent;">Present only while a craft is running.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>note</code></td>
<td valign="top" style="border:0;background:transparent;">string</td>
<td valign="top" style="border:0;background:transparent;"><code>"crafting"</code>, <code>"N queued"</code> or <code>""</code>.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>resultId</code></td>
<td valign="top" style="border:0;background:transparent;">integer</td>
<td valign="top" style="border:0;background:transparent;">Bumps after every finished queue entry.</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>result</code></td>
<td valign="top" style="border:0;background:transparent;">table or <code>nil</code></td>
<td valign="top" style="border:0;background:transparent;">Last finished entry - one of the two shapes below.</td>
</tr>
</table>

On success `result` is `{ ok = true, name, made }`.
On failure `result` is `{ ok = false, name, err, stage, total }`, where `stage` and `total` describe the last execution attempt, not the whole queued request.

---

## Remote calls (RPC)

Any `aegis.<namespace>.<method>` call can be driven over RedNet. Protocol is `aegis_remote`. Address by explicit computer id - A.E.G.I.S. does not register a hostname, so `rednet.lookup("aegis_remote")` returns `nil`. Use a **wireless** modem on the caller.

```lua
local m = peripheral.find("modem", function(_, p) return p.isWireless() end)
rednet.open(peripheral.getName(m))
rednet.send(0,   -- AEGIS computer id
    { cmd = "rpc", method = "craft.start",
      args = { "minecraft:iron_ingot", 32 }, rid = 1 },
    "aegis_remote")
local _, reply = rednet.receive("aegis_remote", 5)
```

Replies come back on the same protocol:

```lua
{ cmd = "rpcr", rid = 1, ok = true,  result = <first return> }
{ cmd = "rpcr", rid = 1, ok = false, err    = "..."          }
```

**RPC keeps only the first return value.** Multi-return methods such as `storage.list` lose the trailing values over the wire - call them locally when you need the tail.

**Error convention:** methods signal expected errors as `return nil, "message"`. RPC maps that to `{ ok = false, err = ... }`; a plain `nil` result stays `ok = true`.

---

## Legacy RedNet commands

The older pocket client still uses the direct commands below. New callers should prefer `rpc` - these are kept for backward compatibility only.

<table border="0" cellspacing="0" cellpadding="8" style="border-collapse:collapse;border:0;background:transparent;">
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><b>Command</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Args</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Reply</b></td>
<td valign="top" style="border:0;background:transparent;"><b>Equivalent RPC</b></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>remote_pull</code></td>
<td valign="top" style="border:0;background:transparent;">-</td>
<td valign="top" style="border:0;background:transparent;">jobs snap</td>
<td valign="top" style="border:0;background:transparent;"><code>jobs.status</code></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>remote_search</code></td>
<td valign="top" style="border:0;background:transparent;"><code>q</code> (string)</td>
<td valign="top" style="border:0;background:transparent;">items + fluids matching name, capped ~80 rows</td>
<td valign="top" style="border:0;background:transparent;">-</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>remote_max</code></td>
<td valign="top" style="border:0;background:transparent;"><code>name</code></td>
<td valign="top" style="border:0;background:transparent;"><code>{max, have}</code></td>
<td valign="top" style="border:0;background:transparent;"><code>craft.max</code> + <code>storage.count</code></td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>remote_craft</code></td>
<td valign="top" style="border:0;background:transparent;"><code>name, count, now?</code></td>
<td valign="top" style="border:0;background:transparent;">jobs snap</td>
<td valign="top" style="border:0;background:transparent;"><code>craft.start</code>. <code>now = true</code> maps to <code>{ run = true }</code> (queue-drain request, not sync).</td>
</tr>
<tr style="background:transparent;">
<td valign="top" style="border:0;background:transparent;"><code>remote_do</code></td>
<td valign="top" style="border:0;background:transparent;"><code>id [, arg]</code></td>
<td valign="top" style="border:0;background:transparent;">jobs snap</td>
<td valign="top" style="border:0;background:transparent;"><code>id</code> is one of: <code>cancel</code>, <code>runall</code>, <code>keep_on</code>, <code>keep_off</code>, <code>keep_run</code>, <code>qdel</code>.</td>
</tr>
</table>

---

## Craft lifecycle

Recommended client pattern - preflight → enqueue → poll → inspect:

```
1. aegis.craft.canMake(name, n)     -- optional preflight
2. aegis.craft.start(name, n)       -- returns queue index
3. loop:
     snap = aegis.jobs.status()
     if snap.resultId changed since last check:
         inspect snap.result
         break
4. on failure: read result.err and decide whether to retry
```

A remote client follows the same flow - each step is just wrapped in an `rpc` envelope, and replies are correlated by `rid`.

---

## Gotchas

- Item ids are plain Minecraft ids (`minecraft:iron_ingot`, `create:andesite_alloy`).
- Fluid inputs come in two shapes: the plain fluid name (`modern_industrialization:styrene_butadiene_rubber`, used by `producers` and `remote_max`) and the internal fluid key (`f:modern_industrialization:naphtha`, used by `get`, `list` and `inventory`). Mixing them silently returns `nil` or an empty result.
- `storage.count(name)` includes group alternatives - it can be larger than `storage.list()[name]`.
- `craft.max` is a planner estimate off the cached stock. It is **not** a reservation. Between `max` and `start` the stock can move; do not treat it as a guarantee.
- `craft.start` never blocks. It enqueues and returns; the main loop drains the queue. Poll `jobs.status()`, watch `resultId` bump, then read `result`.
- `craft.max` and `storage.list` sit on cached snapshots (~4 s TTL). Fine for UI, unreliable for tight retry loops - call `resetStock()` first if you must.
- `jobs.cancel()` is cooperative - it flags `Craft.cancelled` and breaks the queue loop after the current entry unwinds, not instantly.
- `jobs.queue()` hands back the live table. Treat it as read-only - direct mutation races the scheduler.
- If `craft.start` returns `nil, "no recipe: X"` the item is not in the recipe database and is not produced as a fluid side-output either.

---
