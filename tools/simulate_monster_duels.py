#!/usr/bin/env python3
"""Headless 1v1 monster combat simulator for balance / tier evaluation.

Open field: fighters start `--start-dist` metres apart, no obstacles, voxel LOS
always clear. Movement aims at the live hunt standoff distance (same rules as
MonsterCombat.hunt_standoff_m). Attack pick / windup / cooldown / blaster burst
mirror scripts/city/monster_combat.gd. Damage is
`damage_vs_mob * attacker.damage_mult / victim.armor_mult`.

HP uses CreatureHealth family bases × height curve × hp_mult (catalog heights
parsed from scripts/city/creature_catalog.gd).

Examples:
  python tools/simulate_monster_duels.py --fighter kaykit/Skeleton_Warrior --duels 10
  python tools/simulate_monster_duels.py --all-pairs --duels 10
  python tools/simulate_monster_duels.py --tiers --duels 10
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

_TOOLS = Path(__file__).resolve().parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

import combat_resolve as resolve_mod  # noqa: E402
import gamedata_io as gd  # noqa: E402

ROOT = _TOOLS.parent
CATALOG_PATH = ROOT / "scripts" / "city" / "creature_catalog.gd"

# CreatureHealth.gd
BASE_KAYKIT = 34.0
BASE_QUATERNIUS_BIG = 110.0
BASE_QUATERNIUS_BLOB = 45.0
BASE_QUATERNIUS_FLYING = 45.0
REF_KAYKIT = 2.166
REF_QUATERNIUS_BIG = 3.2
REF_QUATERNIUS_BLOB = 2.4
EXP_PROPORTIONAL = 1.0
EXP_DECORATED = 0.5
GIANT_SCALE_EXP = 0.85

# undead_unit.gd role walk bases (sim uses MINION unless body tags say caster)
MOVE_SPEED_MAGE = 1.05
MOVE_SPEED_MINION = 4.2

RANGED_ATTACKS = ("eye_laser", "blaster", "orb_convert", "charged_blast", "stomp")
ATTACK_SCORE = {
    "melee": 1000.0,
    "orb_convert": 800.0,
    "eye_laser": 700.0,
    "blaster": 650.0,
    "stomp": 600.0,
    "charged_blast": 550.0,
}

LETHAL_EPS = 1e-4


@dataclass(frozen=True)
class CatalogBody:
    monster_id: str
    family: str
    collider_height: float


@dataclass
class AttackRow:
    attack_id: str
    kind: str
    damage_vs_mob: float
    cooldown_s: float
    range_m: float
    windup_s: float
    radius_m: float
    speed_mps: float
    burst_count: int
    fire_interval_s: float


@dataclass
class FighterDef:
    monster_id: str
    templates: tuple[str, ...]
    tier: str
    hp_max: float
    damage_mult: float
    speed_mult: float
    armor_mult: float
    preferred_range_m: float
    move_mps: float
    attacks: tuple[str, ...]
    tags: tuple[str, ...]


@dataclass
class FighterState:
    defn: FighterDef
    x: float
    hp: float
    cooldown: dict[str, float] = field(default_factory=dict)
    windup_left: float = 0.0
    windup_attack: str = ""
    windup_aim_x: float = 0.0
    blaster_burst_left: int = 0
    blaster_fire_cd: float = 0.0
    pending_hits: list[tuple[float, str, float]] = field(default_factory=list)
    # pending: (time_left, attack_id, damage)

    @property
    def alive(self) -> bool:
        return self.hp > LETHAL_EPS


def _tier_from_templates(templates: list[str]) -> str:
    joined = " ".join(templates)
    if "boss" in joined:
        return "boss"
    if "minion" in templates and "brute" not in templates:
        return "minion"
    if "minion" in templates:
        return "minion_brute"
    if "brute" in templates:
        return "brute"
    return "other"


def parse_catalog_bodies(path: Path = CATALOG_PATH) -> dict[str, CatalogBody]:
    """Parse collider heights / families from creature_catalog.gd authoring tables."""
    text = path.read_text(encoding="utf-8")
    out: dict[str, CatalogBody] = {}

    # KayKit: collider is always REFERENCE_HEIGHT (2.166), not measured height.
    for name in re.findall(r'_kaykit\("([^"]+)"', text):
        out[f"kaykit/{name}"] = CatalogBody(f"kaykit/{name}", "kaykit", REF_KAYKIT)

    # for row: Array in [ … ]: … _quaternius("big"|"blob"|"flying", row[0], row[1], …)
    for match in re.finditer(
        r'for row: Array in \[([\s\S]*?)\]:\s*\n(?:\s*var blob := |\s*out\.append\(\s*\n\s*)'
        r'_quaternius\(\s*\n\s*"([^"]+)"',
        text,
    ):
        rows_blob, family_dir = match.group(1), match.group(2)
        for name, height in re.findall(r'\["([^"]+)"\s*,\s*([0-9.]+)', rows_blob):
            mid = f"{family_dir}/{name}"
            out[mid] = CatalogBody(mid, family_dir, float(height))

    # Direct one-off _quaternius("blob", "Wizard", 2.601, …) calls.
    for family_dir, name, height in re.findall(
        r'_quaternius\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*([0-9.]+)',
        text,
    ):
        mid = f"{family_dir}/{name}"
        out[mid] = CatalogBody(mid, family_dir, float(height))

    if len(out) < 40:
        raise RuntimeError(
            f"failed to parse catalog bodies from {path} (only {len(out)} entries)"
        )
    return out


def base_hp(body: CatalogBody, character_scale: float = 1.0) -> float:
    if body.family == "kaykit":
        family_base = BASE_KAYKIT
        ref = REF_KAYKIT
        exp = EXP_PROPORTIONAL
    elif body.family == "big":
        family_base = BASE_QUATERNIUS_BIG
        ref = REF_QUATERNIUS_BIG
        exp = EXP_PROPORTIONAL
    elif body.family == "blob":
        family_base = BASE_QUATERNIUS_BLOB
        ref = REF_QUATERNIUS_BLOB
        exp = EXP_DECORATED
    elif body.family == "flying":
        family_base = BASE_QUATERNIUS_FLYING
        ref = REF_QUATERNIUS_BLOB
        exp = EXP_DECORATED
    else:
        raise ValueError(f"unknown family {body.family}")
    entry = family_base * (body.collider_height / ref) ** exp
    return entry * (character_scale**GIANT_SCALE_EXP)


def attack_helpers(row: dict[str, Any], attack_id: str) -> AttackRow:
    def num(key: str, default: float = 0.0) -> float:
        raw = row.get(key, default)
        if raw is None:
            return default
        return float(raw)

    cd = num("monster_cooldown_s", num("cooldown_s"))
    reach = num("monster_range_m", num("range_m"))
    windup = num("monster_windup_s", num("windup_s"))
    burst = int(row.get("monster_burst_count", row.get("burst_count", 1)) or 1)
    interval = num("monster_fire_interval_s", num("fire_interval_s", 0.35))
    return AttackRow(
        attack_id=attack_id,
        kind=str(row.get("kind", "")),
        damage_vs_mob=num("damage_vs_mob"),
        cooldown_s=cd,
        range_m=reach,
        windup_s=windup,
        radius_m=num("radius_m"),
        speed_mps=num("speed_mps", 0.0),
        burst_count=burst,
        fire_interval_s=interval,
    )


def load_fighter_defs() -> tuple[dict[str, FighterDef], dict[str, AttackRow]]:
    root = gd.load_gamedata()
    attacks_doc = root["attacks"]
    behaviours = root["behaviours"]
    templates = root["templates"]
    monsters = root["monsters"]
    catalog = parse_catalog_bodies()
    attack_rows = {
        aid: attack_helpers(row, aid)
        for aid, row in attacks_doc.items()
        if isinstance(row, dict)
    }
    fighters: dict[str, FighterDef] = {}
    for mon in monsters:
        mid = str(mon["id"])
        if mid not in catalog:
            raise KeyError(f"monster '{mid}' missing from creature_catalog.gd parse")
        tids = list(mon["templates"])
        eff = resolve_mod.effective_monster_combat(tids, templates, mon, behaviours)
        scalars = eff["scalars"]
        tags = tuple(eff["lists"]["tags"])
        hp = base_hp(catalog[mid]) * float(scalars["hp_mult"])
        speed_mult = float(scalars["speed_mult"])
        caster = "caster" in tags or mid.endswith("Mage") or mid.endswith("Wizard")
        move = (MOVE_SPEED_MAGE if caster else MOVE_SPEED_MINION) * speed_mult
        fighters[mid] = FighterDef(
            monster_id=mid,
            templates=tuple(tids),
            tier=_tier_from_templates(tids),
            hp_max=hp,
            damage_mult=float(scalars["damage_mult"]),
            speed_mult=speed_mult,
            armor_mult=max(float(scalars["armor_mult"]), 0.001),
            preferred_range_m=float(scalars["preferred_range_m"]),
            move_mps=move,
            attacks=tuple(eff["attacks"]),
            tags=tags,
        )
    return fighters, attack_rows


def monster_attack_range(attack_rows: dict[str, AttackRow], attack_id: str) -> float:
    return attack_rows[attack_id].range_m


def hunt_standoff_m(fighter: FighterState, attack_rows: dict[str, AttackRow]) -> float:
    d = fighter.defn
    if "orb_convert" in d.attacks and fighter.cooldown.get("orb_convert", 0.0) <= 0.0:
        return monster_attack_range(attack_rows, "orb_convert") * 0.92
    for aid in RANGED_ATTACKS:
        if aid == "orb_convert" or aid == "stomp":
            continue
        if aid in d.attacks and fighter.cooldown.get(aid, 0.0) <= 0.0:
            return max(d.preferred_range_m, 1.5)
    if "melee" in d.attacks:
        return monster_attack_range(attack_rows, "melee") * 0.85
    return max(d.preferred_range_m, 1.5)


def pick_attack(
    fighter: FighterState, dist_m: float, attack_rows: dict[str, AttackRow]
) -> str:
    best = ""
    best_score = -1.0
    for aid in fighter.defn.attacks:
        if fighter.cooldown.get(aid, 0.0) > 0.0:
            continue
        reach = monster_attack_range(attack_rows, aid)
        if dist_m > reach:
            continue
        score = ATTACK_SCORE.get(aid, reach)
        if aid == "melee":
            score = 1000.0 - dist_m
        if score > best_score:
            best_score = score
            best = aid
    return best


def damage_of(
    attacker: FighterDef, attack_id: str, attack_rows: dict[str, AttackRow], victim: FighterDef
) -> float:
    row = attack_rows[attack_id]
    return row.damage_vs_mob * attacker.damage_mult / victim.armor_mult


@dataclass
class DuelResult:
    winner: str  # monster_id or "draw"
    loser: str
    winner_hp_frac: float
    duration_s: float
    a_id: str
    b_id: str


def simulate_duel(
    a_def: FighterDef,
    b_def: FighterDef,
    attack_rows: dict[str, AttackRow],
    *,
    start_dist: float = 20.0,
    dt: float = 1.0 / 30.0,
    max_time: float = 180.0,
    a_on_left: bool = True,
) -> DuelResult:
    left = FighterState(
        defn=a_def if a_on_left else b_def,
        x=0.0,
        hp=(a_def if a_on_left else b_def).hp_max,
        cooldown={aid: 0.0 for aid in (a_def if a_on_left else b_def).attacks},
    )
    right = FighterState(
        defn=b_def if a_on_left else a_def,
        x=start_dist,
        hp=(b_def if a_on_left else a_def).hp_max,
        cooldown={aid: 0.0 for aid in (b_def if a_on_left else a_def).attacks},
    )
    t = 0.0
    order = (left, right)

    def apply_pending(fighter: FighterState, foe: FighterState) -> None:
        kept: list[tuple[float, str, float]] = []
        for time_left, attack_id, dmg in fighter.pending_hits:
            time_left -= dt
            if time_left <= 0.0:
                if foe.alive:
                    foe.hp -= dmg
            else:
                kept.append((time_left, attack_id, dmg))
        fighter.pending_hits = kept

    def set_cooldown(fighter: FighterState, attack_id: str) -> None:
        fighter.cooldown[attack_id] = attack_rows[attack_id].cooldown_s

    def queue_or_land(
        attacker: FighterState, foe: FighterState, attack_id: str, dist: float
    ) -> None:
        dmg = damage_of(attacker.defn, attack_id, attack_rows, foe.defn)
        if dmg <= 0.0:
            return
        row = attack_rows[attack_id]
        if row.speed_mps > 0.0 and attack_id in ("eye_laser", "blaster"):
            travel = dist / row.speed_mps
            attacker.pending_hits.append((travel, attack_id, dmg))
        else:
            foe.hp -= dmg

    def fire_blaster_bolt(attacker: FighterState, foe: FighterState, dist: float) -> None:
        queue_or_land(attacker, foe, "blaster", dist)

    def execute(attacker: FighterState, foe: FighterState, attack_id: str, dist: float) -> None:
        row = attack_rows[attack_id]
        if attack_id == "melee":
            set_cooldown(attacker, attack_id)
            if dist <= row.range_m * 1.15:
                queue_or_land(attacker, foe, attack_id, dist)
            return
        if attack_id == "orb_convert":
            set_cooldown(attacker, attack_id)
            # 0 vs_mob — still spends the CD (matches live cast).
            return
        if attack_id == "eye_laser":
            set_cooldown(attacker, attack_id)
            queue_or_land(attacker, foe, attack_id, dist)
            return
        if attack_id == "blaster":
            set_cooldown(attacker, attack_id)
            burst = max(row.burst_count - 1, 0)
            attacker.blaster_burst_left = burst
            attacker.blaster_fire_cd = row.fire_interval_s if burst > 0 else 0.0
            fire_blaster_bolt(attacker, foe, dist)
            return
        if attack_id == "stomp":
            set_cooldown(attacker, attack_id)
            if dist <= max(row.range_m, row.radius_m) * 1.15:
                queue_or_land(attacker, foe, attack_id, dist)
            return
        if attack_id == "charged_blast":
            set_cooldown(attacker, attack_id)
            # Hit if foe is still near the aim point locked at windup start.
            aim_dist = abs(foe.x - attacker.windup_aim_x)
            if aim_dist <= row.radius_m + 1.2:
                queue_or_land(attacker, foe, attack_id, dist)
            return
        set_cooldown(attacker, attack_id)

    def try_begin(attacker: FighterState, foe: FighterState) -> None:
        if not attacker.alive or not foe.alive:
            return
        if attacker.windup_left > 0.0 or attacker.blaster_burst_left > 0:
            return
        dist = abs(foe.x - attacker.x)
        aid = pick_attack(attacker, dist, attack_rows)
        if not aid:
            return
        windup = attack_rows[aid].windup_s
        if windup > 0.0:
            attacker.windup_left = windup
            attacker.windup_attack = aid
            attacker.windup_aim_x = foe.x
            return
        execute(attacker, foe, aid, dist)

    def finish_windup(attacker: FighterState, foe: FighterState) -> None:
        aid = attacker.windup_attack
        attacker.windup_attack = ""
        if not aid or not foe.alive:
            return
        dist = abs(foe.x - attacker.x)
        reach = monster_attack_range(attack_rows, aid)
        if dist > reach * 1.15:
            return
        execute(attacker, foe, aid, dist)

    def move_fighter(fighter: FighterState, foe: FighterState) -> None:
        if not fighter.alive or not foe.alive:
            return
        # Hold still while winding up a charged blast (telegraph).
        if fighter.windup_left > 0.0 and fighter.windup_attack == "charged_blast":
            return
        dist = abs(foe.x - fighter.x)
        stand = hunt_standoff_m(fighter, attack_rows)
        if dist <= stand:
            return
        step = fighter.defn.move_mps * dt
        if fighter.x < foe.x:
            fighter.x = min(fighter.x + step, foe.x - stand)
        else:
            fighter.x = max(fighter.x - step, foe.x + stand)

    while t < max_time and left.alive and right.alive:
        for f in order:
            for aid in list(f.cooldown.keys()):
                f.cooldown[aid] = max(0.0, f.cooldown[aid] - dt)
        for f, foe in ((left, right), (right, left)):
            apply_pending(f, foe)
        if not left.alive or not right.alive:
            break
        for f, foe in ((left, right), (right, left)):
            if f.blaster_burst_left > 0:
                f.blaster_fire_cd -= dt
                if f.blaster_fire_cd <= 0.0:
                    dist = abs(foe.x - f.x)
                    fire_blaster_bolt(f, foe, dist)
                    f.blaster_burst_left -= 1
                    if f.blaster_burst_left > 0:
                        f.blaster_fire_cd = attack_rows["blaster"].fire_interval_s
            if f.windup_left > 0.0:
                f.windup_left = max(0.0, f.windup_left - dt)
                if f.windup_left <= 0.0:
                    finish_windup(f, foe)
        if not left.alive or not right.alive:
            break
        move_fighter(left, right)
        move_fighter(right, left)
        try_begin(left, right)
        try_begin(right, left)
        t += dt

    # Flush in-flight bolts instantly at end-of-fight cutoff only if someone still alive.
    if left.alive and right.alive:
        for f, foe in ((left, right), (right, left)):
            for _tl, _aid, dmg in f.pending_hits:
                foe.hp -= dmg
            f.pending_hits.clear()

    def side_id(f: FighterState) -> str:
        return f.defn.monster_id

    if left.alive and right.alive:
        return DuelResult("draw", "", 0.0, t, a_def.monster_id, b_def.monster_id)
    if left.alive:
        winner, loser, wstate = side_id(left), side_id(right), left
    else:
        winner, loser, wstate = side_id(right), side_id(left), right
    return DuelResult(
        winner=winner,
        loser=loser,
        winner_hp_frac=max(0.0, wstate.hp / wstate.defn.hp_max),
        duration_s=t,
        a_id=a_def.monster_id,
        b_id=b_def.monster_id,
    )


@dataclass
class MatchupStats:
    a: str
    b: str
    a_wins: int = 0
    b_wins: int = 0
    draws: int = 0
    a_hp_frac_sum: float = 0.0  # sum of winner hp% when A wins
    b_hp_frac_sum: float = 0.0
    duration_sum: float = 0.0

    @property
    def n(self) -> int:
        return self.a_wins + self.b_wins + self.draws

    def record(self, result: DuelResult) -> None:
        self.duration_sum += result.duration_s
        if result.winner == "draw":
            self.draws += 1
        elif result.winner == self.a:
            self.a_wins += 1
            self.a_hp_frac_sum += result.winner_hp_frac
        else:
            self.b_wins += 1
            self.b_hp_frac_sum += result.winner_hp_frac

    def a_win_rate(self) -> float:
        return self.a_wins / self.n if self.n else 0.0

    def a_avg_hp_when_win(self) -> float:
        return self.a_hp_frac_sum / self.a_wins if self.a_wins else 0.0

    def b_avg_hp_when_win(self) -> float:
        return self.b_hp_frac_sum / self.b_wins if self.b_wins else 0.0

    def a_score(self) -> float:
        """win_rate × mean remaining HP fraction when winning (0 if never wins)."""
        return self.a_win_rate() * self.a_avg_hp_when_win()

    def b_score(self) -> float:
        return (self.b_wins / self.n if self.n else 0.0) * self.b_avg_hp_when_win()


def run_matchup(
    a: FighterDef,
    b: FighterDef,
    attack_rows: dict[str, AttackRow],
    duels: int,
    start_dist: float,
    dt: float,
) -> MatchupStats:
    stats = MatchupStats(a=a.monster_id, b=b.monster_id)
    for i in range(duels):
        result = simulate_duel(
            a,
            b,
            attack_rows,
            start_dist=start_dist,
            dt=dt,
            a_on_left=(i % 2 == 0),
        )
        stats.record(result)
    return stats


def fmt_pct(x: float) -> str:
    return f"{100.0 * x:5.1f}%"


def print_fighter_report(
    fighter_id: str,
    fighters: dict[str, FighterDef],
    attack_rows: dict[str, AttackRow],
    duels: int,
    start_dist: float,
    dt: float,
) -> None:
    me = fighters[fighter_id]
    rows: list[MatchupStats] = []
    for oid in sorted(fighters):
        if oid == fighter_id:
            continue
        rows.append(run_matchup(me, fighters[oid], attack_rows, duels, start_dist, dt))
    rows.sort(key=lambda r: (-r.a_score(), -r.a_win_rate(), r.b))
    print(
        f"\n=== {fighter_id}  tier={me.tier}  hp={me.hp_max:.1f}  "
        f"dmg×{me.damage_mult:.2f}  spd×{me.speed_mult:.2f}  "
        f"armor×{me.armor_mult:.2f}  templates={list(me.templates)} ==="
    )
    print(
        f"{'opponent':40s} {'tier':10s} {'W-L-D':9s} {'win%':7s} "
        f"{'hp%|W':7s} {'score':7s} {'avg_s':6s}"
    )
    wins = losses = draws = 0
    score_sum = 0.0
    hp_sum = 0.0
    hp_n = 0
    for r in rows:
        wins += r.a_wins
        losses += r.b_wins
        draws += r.draws
        score_sum += r.a_score()
        if r.a_wins:
            hp_sum += r.a_avg_hp_when_win()
            hp_n += 1
        opp = fighters[r.b]
        print(
            f"{r.b:40s} {opp.tier:10s} "
            f"{r.a_wins:2d}-{r.b_wins:2d}-{r.draws:1d}  "
            f"{fmt_pct(r.a_win_rate())} {fmt_pct(r.a_avg_hp_when_win())} "
            f"{r.a_score():7.3f} {r.duration_sum / r.n:6.1f}"
        )
    n_opp = len(rows)
    total = wins + losses + draws
    print(
        f"\nAGGREGATE vs {n_opp} foes x {duels} duels: "
        f"W-L-D {wins}-{losses}-{draws}  "
        f"win%={fmt_pct(wins / total if total else 0)}  "
        f"mean_score={score_sum / n_opp if n_opp else 0:.3f}  "
        f"mean_hp%_when_win={fmt_pct(hp_sum / hp_n if hp_n else 0)}"
    )


def print_all_pairs(
    fighters: dict[str, FighterDef],
    attack_rows: dict[str, AttackRow],
    duels: int,
    start_dist: float,
    dt: float,
) -> list[MatchupStats]:
    ids = sorted(fighters)
    results: list[MatchupStats] = []
    total_pairs = len(ids) * (len(ids) - 1) // 2
    done = 0
    for i, a in enumerate(ids):
        for b in ids[i + 1 :]:
            results.append(
                run_matchup(fighters[a], fighters[b], attack_rows, duels, start_dist, dt)
            )
            done += 1
            if done % 50 == 0 or done == total_pairs:
                print(f"  ... {done}/{total_pairs} pairs", file=sys.stderr)
    results.sort(key=lambda r: (-abs(r.a_win_rate() - 0.5), r.a, r.b))
    print(
        f"\n=== ALL PAIRS  {len(ids)} monsters  {total_pairs} pairs x {duels} duels ==="
    )
    print(
        f"{'A':32s} {'B':32s} {'tier':15s} {'W-L-D':9s} "
        f"{'A_win%':7s} {'A_hp%|W':8s} {'A_score':7s} {'B_score':7s}"
    )
    for r in results:
        ta = fighters[r.a].tier
        tb = fighters[r.b].tier
        print(
            f"{r.a:32s} {r.b:32s} {ta[:6]+'/'+tb[:6]:15s} "
            f"{r.a_wins:2d}-{r.b_wins:2d}-{r.draws:1d}  "
            f"{fmt_pct(r.a_win_rate())} {fmt_pct(r.a_avg_hp_when_win())} "
            f"{r.a_score():7.3f} {r.b_score():7.3f}"
        )
    return results


def print_tier_summary(
    fighters: dict[str, FighterDef],
    pair_results: list[MatchupStats],
) -> None:
    # Per-monster mean score across all opponents in the pair matrix.
    score_sum: dict[str, float] = {mid: 0.0 for mid in fighters}
    score_n: dict[str, int] = {mid: 0 for mid in fighters}
    for r in pair_results:
        score_sum[r.a] += r.a_score()
        score_n[r.a] += 1
        score_sum[r.b] += r.b_score()
        score_n[r.b] += 1

    by_tier: dict[str, list[str]] = {}
    for mid, f in fighters.items():
        by_tier.setdefault(f.tier, []).append(mid)

    print("\n=== TIER SUMMARY (mean score = mean over opponents of win% * hp%|W) ===")
    for tier in sorted(by_tier):
        members = by_tier[tier]
        scores = [score_sum[m] / score_n[m] for m in members if score_n[m]]
        hps = [fighters[m].hp_max for m in members]
        print(
            f"{tier:12s}  n={len(members):2d}  "
            f"mean_score={sum(scores) / len(scores):.3f}  "
            f"score_range=[{min(scores):.3f}, {max(scores):.3f}]  "
            f"hp_range=[{min(hps):.0f}, {max(hps):.0f}]"
        )
        ranked = sorted(
            members, key=lambda m: -(score_sum[m] / score_n[m] if score_n[m] else 0)
        )
        for m in ranked[:5]:
            print(
                f"    {m:40s} score={score_sum[m] / score_n[m]:.3f}  "
                f"hp={fighters[m].hp_max:.1f}  templates={list(fighters[m].templates)}"
            )
        if len(ranked) > 5:
            print(f"    ... ({len(ranked) - 5} more)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fighter",
        help="evaluate this monster id against every other body",
    )
    parser.add_argument(
        "--all-pairs",
        action="store_true",
        help="simulate every unordered pair",
    )
    parser.add_argument(
        "--tiers",
        action="store_true",
        help="with --all-pairs, print tier aggregates (implied if only --tiers)",
    )
    parser.add_argument("--duels", type=int, default=10, help="duels per pairing")
    parser.add_argument("--start-dist", type=float, default=20.0)
    parser.add_argument("--dt", type=float, default=1.0 / 30.0)
    parser.add_argument(
        "--list",
        action="store_true",
        help="list monster ids / tiers / hp and exit",
    )
    args = parser.parse_args(argv)

    fighters, attack_rows = load_fighter_defs()

    if args.list:
        for mid in sorted(fighters):
            f = fighters[mid]
            print(
                f"{mid:40s}  {f.tier:12s}  hp={f.hp_max:7.1f}  "
                f"templates={list(f.templates)}  attacks={list(f.attacks)}"
            )
        return 0

    if args.fighter:
        if args.fighter not in fighters:
            print(f"unknown fighter {args.fighter!r}", file=sys.stderr)
            return 1
        print_fighter_report(
            args.fighter, fighters, attack_rows, args.duels, args.start_dist, args.dt
        )
        return 0

    if args.all_pairs or args.tiers:
        results = print_all_pairs(
            fighters, attack_rows, args.duels, args.start_dist, args.dt
        )
        print_tier_summary(fighters, results)
        return 0

    parser.print_help()
    print(
        "\nTip: python tools/simulate_monster_duels.py "
        "--fighter kaykit/Skeleton_Warrior --duels 10",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
