# Mob combat system

Architecture reference for living-monster combat: kit resolution, attack cadence, hunt/aggro goals, damage routing, and the Siege Quarter special cases. Read this before changing any of the files listed below.

## Ownership chain

```
gamedata.json (attacks / behaviours / templates / monsters)
        │
        ▼
CombatTable.resolve → EffectiveStats
        │
        ▼
MonsterCombat.bind ◄── UndeadUnit.setup / setup_siege_tower
        │                      │
        │                      ├── UndeadGoalProvider (hunt / push / aggro)
        │                      └── NavAgent / NavMotor
        ▼
try_attack_living / strike_structure
        │
        ├── CityRoot.damage_player_scaled   (PLAYER damage sources)
        └── UndeadUnit.apply_damage_scaled (CREATURE damage sources)
                    │
                    └── promote_attacker → aggro queue
```

| Role | File |
|------|------|
| Per-body attack kit | `scripts/city/monster_combat.gd` |
| Living body + nav state | `scripts/city/undead_unit.gd` |
| Goals, aggro, push objectives | `scripts/city/undead_goal_provider.gd` |
| Allegiance rules | `scripts/city/monster_faction.gd` |
| Kit resolution | `scripts/city/combat_table.gd` |
| Damage amounts / targets | `scripts/city/damage_source.gd` |
| Spawn + living queries | `scripts/city/monster_roster.gd` |
| City-wide prey / player damage | `scripts/city/city_root.gd` |
| Authored tables | `assets/gamedata.json` |
| Python merge mirror | `tools/combat_resolve.py` |
| Siege run / stones / towers | `scripts/city/siege_controller.gd` |
| Tower stamps + hit radius | `scripts/city/siege_tower_catalog.gd` |
| Map objectives (beacons) | `scripts/city/beacon_registry.gd` |
| Stamp immunity while alive | `scripts/city/voxel_ward.gd` |

`MonsterCombat` owns attack choice and damage. `UndeadUnit` owns Role/State, navigation, growth, and health. `UndeadGoalProvider` owns *who* to fight and *where* to stand.

---

## Kit resolution

1. `CombatTable.ensure_loaded()` reads `GameData.attacks / behaviours / templates / monsters`.
2. `UndeadUnit._bind_combat()` or `_bind_combat_for_id(id)` → `CombatTable.resolve(id)` → `MonsterCombat.bind(unit, stats)`.
3. Faction comes from the monster row via `MonsterFaction.for_body(body_id)` (required field).

### Merge rules

Keep in sync with `tools/combat_resolve.py`.

| Kind | Rule |
|------|------|
| Scalars (`hp_mult`, `damage_mult`, `speed_mult`, `aggro_range_m`, `leash_m`, `preferred_range_m`, …) | Max across templates; body overrides |
| Lists (`behaviour`, `attacks`, `tags`, `auras`, …) | Union templates; body `*_extra` adds; bare key **hard-replaces** |
| Attack pool | Default = behaviour-derived ∪ template/body specialty. Body hard `attacks` replaces the whole pool |
| Damage table | `attack_damage[id] = base × damage_mult` for `vs_player` / `vs_mob` |

### Behaviours → seed attacks

| Behaviour | Attacks |
|-----------|---------|
| `ambient` | none |
| `chase` / `guard` / `wander_hunt` | `melee` |
| `skirmish` | `blaster`, `eye_laser` |

Templates add specialties (`stomp`, `charged_blast`, `orb_convert`, …). Siege tower rows use template `siege_tower` + a hard `attacks` list of one specialty and `speed_mult: 0`.

### Who hunts

`MonsterCombat.hunts_living()` is true only when the kit has attacks **and** `aggro_range_m > 0`. Ambient bodies have neither.

---

## Attack cadence

### Attack ids

Monster attacks: `melee`, `orb_convert`, `eye_laser`, `blaster`, `stomp`, `charged_blast`.

Ranged kinds (`MonsterCombat.RANGED_KINDS`): everything except contact `melee` — includes `stomp` and `charged_blast` for stand-off / LOS purposes.

### Constants (`monster_combat.gd`)

| Constant | Value | Meaning |
|----------|------:|---------|
| `GLOBAL_COOLDOWN_S` | 2.0 | Shared recovery after **any** attack fires |
| `CHEWER_STANDOFF_M` | 3.0 | Terrain-chewer hunt distance |
| `MELEE_STANDOFF_FRACTION` | 0.7 | Corridor aim as a fraction of melee reach |
| `MELEE_REFERENCE_HIT_RADIUS_M` | 0.55 | Fat bodies grow melee reach above this |

Without the global cooldown, a multi-attack kit empties its whole pool the moment LOS opens.

`is_attack_ready(id)` ignores the GCD on purpose (orb stand-off / cast checks). The GCD only blocks *starting* a new attack in `try_attack_living` / `_pick_attack`.

### Selection (`_pick_attack`)

Uses **surface gap**: `max(0, flat_dist − prey_hit_radius)`. Prey volume (creature capsule or tower stamp) must not strand melee at a wall.

Among ready attacks with `gap ≤ reach`, score bias:

| Attack | Bias |
|--------|------|
| `melee` | `1000 − dist` (prefer when close) |
| `orb_convert` | 800 |
| `eye_laser` | 700 |
| `blaster` | 650 |
| `stomp` | 600 |
| `charged_blast` | 550 |

### Reach

- Melee: table range + `max(0, attacker.hit_radius − 0.55)`.
- Others: `CombatTable.monster_attack_range_m` (prefers `monster_range_m`, else `range_m`).

### Stand-off vs engage

| Method | Role |
|--------|------|
| `hunt_standoff_m()` | Where the **corridor aims** (chewer 3 m; ready orb ≈ 0.92× range; ready ranged → `preferred_range_m`; melee → 0.7× reach) |
| `hunt_engage_m()` | Where the body **stops and strikes** (melee reach if kit has melee, else stand-off) |

Provider `_hunt`:

- If `distance ≤ engage + prey_r` **or immobile** → `null` goal (engage-in-place), set combat prey.
- Else aim at `prey + away × (min(standoff, engage) + prey_r)` with `HUNT_ARRIVE_TOLERANCE_M = 0.35`.

**Never** issue `go_to(self)` for engage-in-place — that re-paths every physics frame.

### Windup / execute

1. `try_attack_living` → pick → optional voxel LOS for ranged → `_begin_attack`.
2. Windup from `monster_attack_windup_s`.
3. `_finish_windup` re-checks gap ≤ `reach × 1.15` and LOS.
4. `_execute_*` → `_set_cooldown` sets per-attack CD **and** `GLOBAL_COOLDOWN_S`.

Frame loop: `UndeadUnit.tick` → `MonsterCombat.tick` (CDs, windup, blaster burst) → `_tick_combat_strikes` → `try_attack_living(_combat_prey)` or `strike_structure(objective_strike_aim)`.

---

## Hunt, aggro, and acquisition

### Faction: damage vs acquire

Two different questions (`monster_faction.gd`):

| API | Meaning |
|-----|---------|
| `is_hostile(a, b)` | May A **damage** B? |
| `can_acquire(hunter, prey)` | May A pick B as **fresh** prey? |

Rules of thumb:

- Same faction / either `SPECTATOR` → not hostile.
- `SIEGE_DEFENDER` is hostile **only** to `SIEGE_ATTACKER` (and vice versa for that pair).
- `can_acquire` requires hostility, then **rejects** `SIEGE_DEFENDER` as fresh prey.
- Forced retaliation (`promote_attacker`) bypasses `can_acquire`.

City queries match the split:

- Fresh hunt → `collect_acquirable_monsters` → `can_acquire_prey`.
- Splash / strike near aim → `find_nearest_hostile_monster` → `is_hostile_to`.

Silent towers are hostile for damage but not fresh prey. The horde walks past them until shot.

### Prey authority order (`_nearest_living_prey`)

1. Aggro queue head (`_forced_prey_aim`) — damage-driven.
2. Sticky committed target (`_committed_aim`) — must stay in leash + LOS (immobile: LOS loss clears, no Investigate wander).
3. Else `_acquire_prey`: closest acquirable with voxel LOS from muzzle.

Cache: `PREY_CACHE_SEC = 0.28` (aligned with `UndeadUnit.PED_QUERY_INTERVAL_SEC`).

### Sticky prey

- Nodes: `_target_node` (player / `UndeadUnit`).
- Peds: `_target_ped`, rematched within `STICKY_PED_MATCH_M`.
- Commit until dead, unleashed, or (immobile + LOS lost).

### Aggro queue (`promote_attacker`)

- Append if not already queued. **Later hitters do not steal the head** (avoids aim ping-pong).
- Aim always at the head.
- Drop head when: freed, dead, outside leash, or corridor failed **and** outside `engage + hit_radius`.
- Do **not** drop solely because the navigator reports `GOAL_UNREACHABLE` while the body is still in swing range of a stamp wall.

Always `is_instance_valid` **before** casting a queue entry to `UndeadUnit`. `_prey_hit_radius_m` prunes first — a freed tower in the queue used to crash retarget.

### Pursuit memory

`HOT` → LOS/range loss → `INVESTIGATE` last-known point up to `INVESTIGATE_TIMEOUT_SEC` (5 s). Immobile towers skip Investigate.

Leash: `leash_m` if set; else `aggro_range_m × 1.25`; else mage pursue default × 1.25.

---

## Damage routing

### Amounts

`DamageSource.amount` — player attacks authored in script; monster attacks read `damage_vs_player` / `damage_vs_mob` from the combat table. Live hits multiply by attacker `damage_mult`. Armor on the victim divides via `armor_mult`.

### Player ← monster

`MonsterCombat._hurt_player` → `CityRoot.damage_player_scaled(source, damage_mult)`. Requires a PLAYER-target source and `_hostile_to_player()`.

### Mob ← monster

`_hurt_monster` → `DamageSource.for_monster_attack_mob(attack_id)` → `target.apply_damage_scaled(..., attacker_unit)`. Direct apply (no player score). Passes self so the victim can `promote_attacker`.

### Mob ← player / splash

`UndeadUnit.apply_damage_scaled`:

1. Reject non-CREATURE sources.
2. Reject player-vs-creature on `SIEGE_DEFENDER` structures (the player's own pads). A structure on any other side — a spawn spire — takes player fire like any body.
3. Apply scaled damage / armor.
4. On survive → hit react + `_promote_attacker_after_hit` (player node if attacker omitted on a player source).

### Pedestrians

Melee removes with `try_remove_ped_at` (one-shot). Orb convert is a separate projectile path.

---

## Goal tags and retarget

| Tag | Const | Use |
|-----|-------|-----|
| Hunt | `TAG_HUNT` | Living prey / Investigate LKP |
| Wander | `TAG_WANDER` | Bored roam |
| Push | `TAG_PUSH` | Beacon / stone objective ring |

### `next_goal` (SEEK_PED / STOMP)

- **FAR + mobile + no beacon** → wander (skip crowd query).
- **FAR + beacon** → still `_push_goal` (horde walks distant stones).
- **FAR + immobile tower** → still run prey query (must keep shooting).
- Else: living prey → hunt; else Investigate; else push; else idle.

Immobile idle must be `null`, not wander — a failed wander drops the target the body was holding.

### Push ring

Stand at `vuln_radius − PUSH_RING_INSET_M` (0.75 m). Inside vuln → `null` (“hold”). `objective_strike_aim()` returns the centre when inside the hold radius so the body can face/swing theatre.

### Retarget (every ~0.28 s)

| Current goal | Behaviour |
|--------------|-----------|
| `null` (engage-in-place) | Refresh prey; resume corridor if left stand-off |
| `TAG_PUSH` | `_turn_on_attacker` first (answering fire outranks the errand); else retarget if beacon changed |
| `TAG_HUNT` | Refresh prey; rebuild if drift > `RETARGET_SLACK_M`; else lost-prey memory |

---

## Siege path

### Towers (living, meshless)

1. Stamp voxels (`SiegeTowerCatalog.stamp_at`) — fractal shaft + `ORB` tip.
2. Spawn `UndeadUnit.setup_siege_tower` — explicit faction (`SIEGE_DEFENDER` for a bought pad), authored HP, explicit muzzle height, structure hit radius.
3. Host sits inside the stamp (`TOWER_HOST_LIFT_M`); muzzle must clear the tip or voxel LOS never acquires.
4. `hit_radius()` returns the stamp footprint (`structure_hit_radius_m`), not the invisible host capsule — hunt engage and melee gap use that volume the way stones use `vuln_radius_m`.
5. `VoxelWard.claim` while alive; release + demolish on death. HP is the only way the tower comes down.
6. Immobile (`speed_mult == 0`): engage-in-place, no wander on idle, FAR tier still acquires.

### Spawn spires (same structure, other side)

Crypt and castle-dungeon summoning stations stand under a `SpawnTower` (`scripts/city/spawn_tower.gd`): the same meshless structure stack on a **monster** faction, row `spawn/fractal_spire`, catalogue row `spawn_spire` with `buildable: false` (never listed on a siege pad). `MonsterRoster.spawn_faction_tower` marks it a spawn tower, which changes three things:

- the player may damage it (the friendly-fire gate is `SIEGE_DEFENDER`-only);
- a player kill calls `CityRoot.grant_spawn_tower_kill` — a **guaranteed** missing recipe instead of the gem haul (no-op with a full cookbook);
- death calls `stop_spawning()` on its station: no new waves, and **nothing already summoned is despawned**. Only district unload clears the room.

The station summons `SpawnTower.summon_world` (two cells aside) so bodies do not arrive inside the mass, and the anchor cell is probed downward from the pad because the crypt names its first air cell where a castle vault names the slab.

### Stones (not combat entities)

`SiegeController.StoneState`: HP + `vuln_radius_m`, no collider. Tick counts chewers inside the radius × DPS. Outer stones are beacons for `SIEGE_ATTACKER`; the centre registers only after the last outer falls.

### Repair channel

LMB (blaster bind) aimed at a **damaged** tower, outer stone, or Lodestone channels mend instead of shooting: `SiegeController.pick_repair_target` + `apply_repair`, `gamedata.siege.repair_*` rates (2 energy/s, 5 HP/s, ~18 m, LOS). Visual: thick green wobbling beam from the outstretched spell hand (`RepairBeamVfx` + `Spell_Simple_Idle`). Full-HP and dead targets leave the blaster alone.

### `strike_structure` (theatre)

When holding on an objective with no living prey: play melee cadence / SFX, **deal no stone damage**. Real drain is contact tick in the controller. No windup (would route into living melee execute).

### Caps

`MonsterRoster.MAX_ALIVE_UNITS` (80) counts walkers; `MAX_ALIVE_TOTAL` (220) includes towers. Towers are excluded from the walker cap.

---

## Invariants (do not break)

1. **Surface distance for melee** — gap = flat − prey `hit_radius`. Towers and fat bodies need this.
2. **Hunt aim past prey volume** — stand-off ring is `standoff + prey_r`, or corridors land inside solid stamps and fail forever.
3. **Aggro head sticky** — enqueue later hitters; never steal the head mid-approach.
4. **Corridor fail ≠ drop aggro in engage** — stamp walls often make stand-off unreachable while the body can still swing.
5. **Validate before cast** — prune / `is_instance_valid` before `as UndeadUnit` on queue entries.
6. **Engage-in-place is `null`** — never trivial `go_to(self)`.
7. **Immobile idle is `null`** — wander fails and clears prey.
8. **FAR towers still query prey** — mobile FAR may skip the crowd query; towers must not.
9. **`can_acquire` ≠ `is_hostile`** — towers are silent until they shoot.
10. **`strike_structure` deals no stone HP** — contact DPS is the mechanic.
11. **Push hold is `null`** — inside vuln radius, do not wander off the crystal.
12. **GCD vs `is_attack_ready`** — GCD blocks starts; per-attack ready ignores GCD for stand-off logic.
13. **Muzzle clears the tip cell** — host point inside the stamp is not the eye. `ORB` is a sphere mesh but a full solid voxel for LOS; the eye must sit in air above that cell, not in the mesh crown.
14. **Ward while alive** — stamp cells are uncarvable; demolish only on death/withdraw.
15. **Hard body `attacks`** — replaces behaviour-derived pool (siege towers rely on this).
16. **No building prey table** — hostility is faction-only; area attacks may still carve fabric.
17. **Friendly fire is a faction rule, not a structure rule** — only `SIEGE_DEFENDER` towers refuse player damage; a hostile spire that cannot be shot is an unkillable spawn tap.
18. **A dead spire keeps its summons** — killing the tower stops new waves only; the room does not empty.

---

## Primary tests

| Harness | What it pins |
|---------|----------------|
| `tools/test_monster_combat.gd` | Kit wiring, melee/ranged, faction damage, hunt stand-off vs engage |
| `tools/test_undead_nav.gd` | Aggro queue, hunt-fail keeps tower, freed tower in queue, far-tier retaliation |
| `tools/test_siege_towers.gd` | Catalog, stamp/ORB, structure hit radius, wall reach, ward, FAR hunt |
| `tools/test_siege_horde.gd` | Live wave chews stone; tower voxels stay warded |
| `tools/test_siege_repair.gd` | Repair channel pick/heal on stones and towers; gamedata rates |
| `tools/test_siege_faction.gd` | Vulnerability radius vs stand ring, defender rules |
| `tools/test_spawn_tower.gd` | Spire catalogue / kit, player damage, guaranteed recipe, summons outlive it |
| `tools/test_spawn_tower_live.gd` | Spire stamped and warded in a streamed crypt / dungeon (`--spawn-theme=graveyard\|castle`) |
| `tools/test_combat_table_sync.gd` | GDScript ↔ Python merge parity |
