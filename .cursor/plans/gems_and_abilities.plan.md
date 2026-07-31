---
name: Gems, inventory and abilities
overview: "Staged plan: (1) district gem distribution + budgets + explore score, (2) crafting and powers, (3) scenarios later. Sandbox vs Adventure; scrap infection/undead score POC."
todos:
  - id: stage1-sources
    content: "Stage 1: gem sources beyond hills (chests, rare tree gems)"
    status: pending
  - id: stage1-budgets
    content: "Stage 1: per-district per-type budgets on first create + save row"
    status: pending
  - id: stage1-explore
    content: "Stage 1: scrap old score POC; explore-once score on HUD + explored flag"
    status: pending
  - id: stage2-tray
    content: "Stage 2: ability tray + Sandbox/Adventure modes"
    status: pending
  - id: stage2-craft
    content: "Stage 2: hardness, unlocks, affinities, trap, starter blaster"
    status: pending
  - id: stage3
    content: "Stage 3: place-bound scenarios, mob loot, combat score hooks"
    status: pending
isProject: true
---

# Gems, inventory and abilities

Living design doc. **Locked** items are decided; **Open** items are the ones to argue about next.

## Design pillars (locked)

- **No pressure.** A player who wants to explore the city must be able to do that without being
  shot at. Danger is an opportunity that is taken, never one that arrives uninvited.
- **Consented escalation.** The player turns the dial up. The meteor (M) and the monster summon
  (N) are already the player *creating* trouble, so they stay free — they are the difficulty dial,
  not a power. Reward scales with the dial.
- **Gems are the currency of capability, not of fun.** Sandbox toys (tetris machine, pedestrian
  spawn, day/night, aim panel, builds) stay free. Combat and traversal power is what gets priced.
- **Spend the renewable resource on verbs, the rare resource on nouns.** Energy per use, gems per
  unlock. Charging gems every time a key is pressed turns exploration into grinding and makes
  players hoard instead of play.

## Where the game stands today

Facts worth having in one place, because most of the design hangs off them.

| Thing | Today |
| --- | --- |
| Gem sources | `HillComposer` only — one cluster per ~250 solid host voxels, cap 880, 1–4 nuggets |
| Gem rarity | Global weighted roll: quartz 48, amber 24, topaz 14, sapphire 8, emerald 4, diamond 2 |
| Gem hosts | `STONE`, `BRICK`, `GRAVEL` (`_is_gem_host`) — the starting tool must break these |
| Collection | Proximity pickup (1.35 m × scale) plus anything inside a carve sphere |
| Recipes | Exactly one: 5 quartz → 1 trap. The trap has no world effect at all |
| Energy | 100 max, regen 1/s ÷ character scale; blaster 1, laser 1, stomp 10, charged blast 20 |
| Powers | Every hotkey power is free and uncapped except the undead radar (30 s cooldown) |
| Melee | `_start_melee_punch` / `_start_melee_kick` fully implemented, 34 damage, **bound to nothing** |
| Death | `Enter` respawns in the same world, full health, keeps everything |
| Progression | Score only (tendril 1000, monster 50, giant 1000). No XP, no unlocks, no levels |

## 1. Persistence: per-district gem budgets (locked, blocking)

`CityStreamer._unload_district()` calls `DistrictInstance.destroy_and_clear()`, and re-entering the
tile bakes it again from its seed. There is no voxel edit persistence, and the save deliberately
carries no district voxels. Serialising whole districts is out of scope and not needed.

**Per-type gem budgets, shared across sources.** Each district has a remaining count for every gem
type (quartz, amber, topaz, sapphire, emerald, diamond) — six small integers, not one lump sum.
Cave nuggets, chests, trees, and later mob loot all draw from that same per-type pool. Collecting a
sapphire decrements sapphire only; when a type hits zero, that type stops paying from every source
in the tile.

**Assigned once, on first create.** The first time a district instance is created in a run, its
budgets are rolled (from the district seed / theme rules) and written into the save. Later unload /
re-bake / revisit never re-roll — they only read and decrement what is already stored. Unvisited
tiles do not appear in the save at all, so the footprint stays “six ints × districts the player
has actually loaded.”

How the bake cooperates without remembering positions:

- Hills may still place gem voxels from the seed as today (or skip painting types whose budget is
  already zero, so a stripped hill does not look full of candy).
- Pickup / chest open / tree harvest asks the live budget for that coord + gem type. Empty → refuse
  (or inert chest / no drop).

Consequences worth having on purpose:

- **Camping is self-defeating.** Strip a tile’s diamonds and they stay gone; travel is the answer.
- Rarity stays meaningful: emptying quartz does not empty diamond, and a diamond-light roll on first
  create stays diamond-light forever for that tile.
- No voxel edit stream, no chest-open bitfields, no cluster skip lists.

**Open:** do budgets refill? Default for v1: no. Revisit once the rate is felt.
How large the first-create roll is per theme (hill rich, residential modest) is still open; the
*shape* of the data is locked.

## 2. Gem sources (locked in kind, open in numbers)

The one-source problem, fixed by spreading *delivery* across district types while keeping the
*rarity curve* global.

- **Cave nuggets (hills).** Stay as they are — easter eggs for the player who goes underground.
- **Chests.** Runtime Node3D (not a voxel prop), placed by the interior decorator in buildings.
  Mesh: Kenney Pirate Kit `chest.glb` (CC0) — body + lid with baked `open` / `close` animations —
  vendored under `assets/city/chests/`. Interact with `E` (same hint path as doors/elevators).
  Chests are the everyday source, and they put gems in every district that has interiors.
- **Tree gems.** Very rare, so it reads as a small event rather than a harvest. Parks and the
  landmark forests.
- **Mob loot.** Deferred until mob combat is developed, then the reward for the player who engages.

### Rarity comes from effort, not from address

No signature gem per district — that would make one district the diamond district and everyone
would live there. Instead every source rolls the same global curve, and *effort inside that source*
shifts the roll:

- deeper in the cave network → better roll
- higher floors of a tower → better chest
- tougher mob → better drop

Every district type has depth, height or mobs, so no address dominates, and rarity still feels
earned rather than handed out.

## 3. The ability tray (locked in shape)

Nine slots: **F1–F6 plus the three mouse actions** (LMB, Ctrl+LMB, Alt+LMB). Today F1–F6 live in
`player_action_bar.gd` and hold build recipes, while the three mouse attacks are hardwired in
`city_walker.gd`. The work is one ability registry that both read from, so a slot can hold a build,
a weapon, a boost or a summon, with its cost drawn on the slot.

"Unlocked" then means nothing more than **may be assigned to a slot**. No new UI concept, and
`Shift+F1–F6` already exists as the assign menu to extend.

**Open:** does `Q` (stomp) become a tenth slot, or stay a fixed key? Same question for the
situational keys (J hop, U radar, E interact) — my read is those are not tray material.

## 4. Costs (proposed)

Three categories, kept strictly apart so the economy stays legible:

1. **Unlock (noun).** One-time gem investment, weighted toward the rare end so the 2% diamond rate
   does real work. Permanent, saved.
2. **Use (verb).** Energy, every time, forever. Already the mechanism for the four attacks.
3. **Consumable (object).** Crafted from gems and spent — traps, boosts. The only place gems are
   consumed repeatedly, and it is a deliberate choice each time.

### Gem affinities instead of six denominations of cash

Give each gem a meaning so recipes read like a story rather than a price list, and so the rarity
curve is load-bearing:

| Gem | Affinity |
| --- | --- |
| Quartz (48%) | Raw filler, structure |
| Amber (24%) | Duration — how long a temporary thing lasts |
| Topaz (14%) | Energy — pool size, regen, cheaper casts |
| Sapphire (8%) | Shielding, cold, protection |
| Emerald (4%) | Life and growth — minions, scale |
| Diamond (2%) | Permanence and hardness — the top hardness tier, lasting unlocks |

## 5. Hardness tiers (locked, replaces the per-material matrix)

A weapon × material unlock matrix would be ~65 materials of mostly boring entries, and taking voxel
destruction away from a new player removes the best-feeling thing in the game. Four tiers instead,
as a single upgrade line:

| Tier | Materials | Note |
| --- | --- | --- |
| Soft | dirt, grass, wood, glass, thatch | Always breakable |
| Rock | stone, brick, gravel, sand | **Always breakable** — the gem hosts live here, so the starting tool must clear this or the first gem is unreachable |
| Reinforced | concrete, steel, castle block, seating | First real unlock |
| Exotic | meteor rock, infection materials, fractal bands | `METEOR_ROCK` is already described in the code as indestructible "until unlocked" |
| Never | bedrock, arena shell, LOS veil | Stays absolute |

Gate **rate**, not possibility, at the edges: one tier above your tool is slow and chippy, two tiers
above refuses with an obvious visual and audible cue. A tool that silently does nothing reads as a
bug.

## 6. The trap (locked)

The one crafted item that exists, now with a concrete job: **a throwable hold**.

- **Throw, do not place underfoot.** Deployed as a projectile / lob so laying it cannot auto-trigger
  on the thrower. Lands as a short-lived armed plate (or similar) on the ground.
- **Any actor.** Mobs, pedestrians, and the player — whoever steps on it. Symmetric by design.
- **Hold 10 seconds**, then release. The trap is **consumed on trigger** (one use).
- Craft recipe stays the existing 5 quartz → 1 trap until affinities and costs are tuned.

This is the first real consumable and the natural prep tool for the opt-in loop: craft, throw ahead
of a chase or at a doorway, then engage. Collapse plates and infection tools stay out of v1.

## 7. Keeping the explorer unmolested

The pillar needs teeth in the systems, not just intent:

- Threats stay **bound to where they were invited** — the arena pit, a themed event district, a
  crypt — and do not wander into the path of someone who never opted in.
- Escalation is **legible before entry**: you can see that a district is hot from outside it.
- **Infection + meteor + undead invasion toggles are POCs.** The infection *idea* (spreading
  threat you can fight back) is worth keeping later as something like a **graveyard-themed event**,
  not a global settings toggle that paints the whole city. Same fate for the invasion toggle: re-cut
  into place-bound content when that work happens. Until then, Adventure score must not depend on
  those systems staying as they are.
- The arena district is already the venue for consented combat, with its summon boards and pit. It
  is where the engaged player goes, and it can pay accordingly.

## 8. Save format

`game_save.gd` needs a version bump to carry: unlock state, play mode, run score, per-district
rows (per-type gem budgets on first create + explored flag), and slot assignments. Worth doing
before the format spreads further — it is currently at `VERSION = 1` with no migration path
exercised.

## 9. Starting loadout (locked)

**Primary weapon is the repeat blaster** (LMB hold), not melee. Melee punch/kick stay unbound /
optional later; they are not the onboarding attack. What the starter blaster *cannot* do yet is the
interesting half of hardness — see §5: carve Rock from the start (gem hosts), Reinforced/Exotic
behind unlocks. Exact starter package for laser / charged blast / stomp still open.

## 10. Play modes (locked in shape)

Two modes, chosen when starting a run (and stored on the save):

| | **Sandbox** | **Adventure** |
| --- | --- | --- |
| Abilities | All unlocked, assign freely | Gated by gem unlocks |
| Gem budgets | Optional / still fun to collect, but not required for power | Live; first-create rolls, deplete |
| Score | Off — not shown, not saved | On |
| Threats | Same opt-in toys (meteor, summon, arena) | Same, but they also feed score |

Sandbox is the current game’s spirit preserved: explore and play with everything. Adventure is where
the gem / unlock / score loop lives. New Game asks which mode (or a toggle on the Game menu before
the world is sealed — open).

**Open:** do Sandbox saves still track gem budgets for flavour, or skip budgets entirely? Lean: skip
budgets in Sandbox so re-entering a hill always has ore; collectibles are infinite toys again.

## 11. Scoring — scrap the POC, keep it simple (brainstorm)

### What exists today (to delete)

Score is owned by `InfectionDirector`, mirrored into `CityRoot._player_score`, always on the FPS HUD:

- Kill a tendril → bank its remaining value (starts at 1000, digests down as it spreads)
- Undead chew a building voxel → −1 (spam)
- Player converted by invasion → −150
- Monster kill → +50 / giant +1000 (via undead unit)

Problems: opaque decaying tendril values, penalty noise for world damage the player may have
invited, score lives inside infection, and **the number does nothing** — no high score, no goal.

**Locked:** scrap that POC. New score is a small, separate system. Infection / undead keep their
gameplay; they stop owning the counter.

### Design goal

Score answers one question: **how much consented spectacle did this Adventure run pull off?**
It must not punish exploration, must not require reading a manual, and must not grow a second
economy beside gems.

### Proposed rules (simple)

1. **Stage 1: score is on for everyone** (explore only). Stage 2: Sandbox hides score; Adventure
   keeps it and gains later deed types.
2. **Points for clear deeds, flat numbers.** No decaying tendril wallets, no −1 per voxel.
3. **Score sources by stage:**
   - **Stage 1 — Explore a district** → flat once per tile (e.g. 50). First visit / discover.
   - **Stage 2 — Trap a hostile** (not a ped, not yourself) → small flat when traps ship.
   - **Stage 3 — Defeat a monster** → flat by tier when combat scenarios mature.
4. **Exploration is persisted on the district save row.** Same tiny per-district record as gem
   budgets: add an explored flag. Re-entering after unload does not pay again.
5. **Do not wire score to the infection / meteor / invasion POCs.** When infection returns as a
   place-bound event (e.g. graveyard), add a flat “clear event” payout then. Until that rewrite,
   those systems are not part of the score design.
6. **No arena-clear score** (and no building-damage penalties). Arena stays a playground; it does
   not own the counter.
7. **Death does not wipe the run score** (no pressure). Score is a climbing counter for the save /
   session until New Game.
8. **One number on the HUD** in Adventure. No multipliers, combos, or star ratings in v1.

Optional later (still simple): remember **best score** for this world seed / this save slot. Not
required for v1 if a climbing run total is enough.

### What score is not

- Not a currency (gems buy power; score is bragging rights)
- Not XP / levels
- Not a reason to farm pedestrians or blast empty streets
- Not a reason to keep the infection toggle alive

### Open (scoring)

1. **When does the counter reset?** Only on New Game, or also on death / load?
2. **What counts as “explored”?** First time the district finishes loading with the player inside
   it? First time they leave the spawn tile? Crossing a threshold distance from the district
   origin? Lean: first time that coord’s instance becomes playable while the walker is in it —
   simple, matches the budget “first create” moment.
3. **Special vs ordinary tiles:** same flat payout, or a small bonus for landmark themes?
4. **Pedestrians / wrecked cars:** never score (lean: never — keeps it spectacle, not grief).
5. **Best-score persistence** in the save: yes/no for v1?
6. **Mode pick UI:** at New Game only, or also “convert this Sandbox save” (probably never — mode
   is fixed per save).
7. **Later graveyard event:** what “clear” means for a payout — park until that content is designed.

## Roadmap (locked shape)

Three stages. Combat scenarios stay out until Stage 3. Each stage should leave the game playable.

### Stage 1 — District gem distribution (+ score foundation)

Goal: gems exist across the city, deplete honestly, and **a real score is already on the HUD** —
exploration only for now, so the counter means something before powers and scenarios arrive.

1. **Save district row** — per-type remaining budgets + explored flag; assigned on first create of
   that coord. Version bump designed so Stage 2 can add mode / unlocks / slot map without another
   rewrite if we leave room (or accept a clean bump then). Persist run score on the save too.
2. **Budget roll + deplete** — shared pool across all sources in the tile; pickup/chest/tree refuse
   when that type is empty.
3. **Sources beyond hills** — chests (decorator + E), rare tree gems; hills keep cave nuggets.
4. **Scrap old score POC** — tear infection/undead score wiring out of the HUD and directors.
5. **Explore-once score (live in Stage 1)** — flat points the first time a district is explored;
   persist the explored flag; show the climbing total on the HUD. This is how we establish score
   before Adventure mode exists. Monster/trap score waits for Stage 2–3.

Stage 1 does **not** gate abilities. Everyone still has today’s free hotkeys. Budgets + explore
score are the new loop; the power fantasy stays open so the economy can be felt and tuned.

When Stage 2 adds Sandbox vs Adventure: **Adventure keeps this score**; Sandbox hides it (and may
skip further score writes). Stage 1 itself has no mode flag — score is simply on for everyone.

### Stage 2 — Crafting and powers

Goal: gems buy capability; energy pays per use; Sandbox preserves the toybox.

1. **Sandbox vs Adventure** play mode on the save.
2. **Ability registry + 9-slot tray** (F1–F6 + three mouse actions).
3. **Hardness tiers** on carve.
4. **Unlock costs + gem affinities**; Adventure starter = blaster primary.
5. **Throwable hold trap** (craft + throw + 10 s hold); optional trap-hostile score once traps work.
6. Temporary boosts / grow-shrink / shield / minions / hop & tetris as unlocks — as designed in the
   earlier list, paced so the tray does not explode in one drop.

### Stage 3 — Scenarios

Goal: place-bound, opt-in content. Not toggles.

- Infection core idea → e.g. graveyard-themed event (not a city-wide toggle)
- Meteor / invasion POCs re-cut the same way
- Mob combat maturity + loot drawing district budgets
- Combat score hooks (monster tiers, later event clears)
- Arena stays a playground unless a future design gives it a scored mode on purpose

### Gaps worth naming (not new stages — park or fold in)

| Gap | Where it belongs |
| --- | --- |
| **Play modes** | Stage 2 (Stage 1: budgets + explore score always on; Sandbox later hides score / may skip budgets) |
| **Explore score** | **Locked in Stage 1** — HUD + save from day one |
| **Monster / trap score** | After those verbs exist (trap = Stage 2, monsters as score = Stage 3) |
| **Travel / hop pricing or “known districts from signposts”** | Optional Stage 2 spice; not required for Stage 1 |
| **Gem affinities** | Stage 2 with recipes; Stage 1 can still use the global rarity weights for rolls |
| **UI for “this district is spent”** | Stage 1 polish — empty chest / no pickup is enough at first |

## Out of scope (whole plan)

- XP, character levels, skill trees
- Vendors, currency exchange, gem trading
- Per-material weapon unlocks
- Serialising district voxels / full edit streams
- Death penalties of any kind
- Keeping the infection/undead score POC
- City-wide infection / meteor / invasion toggles as permanent design
- Melee as the primary starting weapon
- Score as a second currency that buys unlocks

## Open questions

### Stage 1
1. **First-create roll sizes** per theme (hill rich, residential modest)? Theme-tinted mixes or
   same global weights with different totals?
2. **Budget refill** — never for Stage 1 (lean: never).
3. **What flips explored?** Lean: first time that coord is playable with the walker in it.
4. **Special vs ordinary** explore payout — same flat, or landmark bonus?
5. **Explore points amount** — pick a flat number that still feels good after dozens of tiles.

### Stage 2
6. **Starter kit beyond the blaster** — laser / charged blast / stomp free or locked?
7. **Stomp** and situational keys — tray or fixed?
8. **Scale pads** vs paid grow ability.
9. **Trap throw UX** — slot, arm delay, giant / player break-out.
10. **Sandbox** — skip gem budgets entirely?

### Stage 3
11. Graveyard (or other) event shape when infection returns.
