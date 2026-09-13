G9 battle engine update for gen 1 and gen 2 (see "Games" below), gimmicks need fixing.

## Games

`manifest.json` declares `games: ["gen1", "gen2"]`, so the engine loads on Red /
Blue / Yellow as well as Gold / Silver / Crystal. This matters beyond the
engine's own modules: the loader's generation gate (`Loader:_gateGeneration`)
SKIPS a mod whose `games` does not cover the running game, and that skip is
contagious through dependencies (`Loader:_enforceDependencies`) -- a gen2-only
declaration here silently disabled every mod that depends on the engine on a
Gen 1 boot. The battle-scene mod depends on the engine unscoped, so a
`["gen2"]` engine left the scene's move menu without the round-100 move-validity
query on Gen 1 (the reported "changes only affect Gen 2" bug), and would have
left the round-98/99 Gen-1 held-item combat path dead too.

Both generations run the same `main.lua` boot path (every module boots through a
pcall-guarded `boot()`, none of them early-returns on generation); the Gen-1
behaviour is selected inside the modules -- see the Gen-1 accessor paths and the
per-generation notes below.

Round 14 status: ability library fully audited against national_dex + Pokémon Showdown — all 313 national_dex abilities accounted for (see ABILITIES.md / PROGRESS.md / list.md).

Scope:
-All up to date moves with working sub effects
-EV, IV, Natures implementation
-Battle effective Abilities
-Fields and Weather conditions
-All 934 moves up dated to generation 9
-Dynamax (Dynamax level, Gigantamax factor), Mega-evos, Z-moves, Tera type.
-Held Item expansion + combat effects
-Overworld encounters
-Followers

Future extensions:
-Overworld Alphamons, Hordes, Double Battle, gen5 phenomena encounter type, Dynamax Den, Tera Dens, Mega Dens, (Dynamax/Tera/Mega) Adventures.
-Tutor, TM extensions.
-EV/IV modification items.
-allow manual set of EVs over total limit, support 252 EV all stat.

## Public API for other mods

`mod.exports.registerTrainer(trainerId, party, options)` lets any external mod
replace a trainer's team. Each party entry tells the BASE engine the Pokemon's
species, level, gender and moves, and tells THIS engine the same plus the modern
stats (ability, nature, IVs, EVs, Tera Type, Dynamax Level, Gigantamax Factor) and
the held item. `options.combatType` is the trainer's battle mode -- `native`
(also `primitive`/`vanilla`/`single`), `doubles`, `triples`, or `bossFight`
(also `bossfight`/`boss`); doubles/triples/bossFight use the optional
g9-Battle-Scene mod's same-named layout preset when installed and fall back to the
ordinary battle when it is not. `bossFight` maps to that mod's own 4v1 boss-fight
layout, so register the boss itself (typically a single ace).

`options.maxHpMultiplier` (alias `hpMultiplier`/`maxHp`/`maxhp`) is the boss-fight
health control: 1x-5x, default 1x, applied to every Pokemon on that ONE trainer's
roster. Values outside 1-5 are clamped and a non-number falls back to 1x. It can
also be changed at runtime with `setTrainerMaxHpMultiplier(trainerId, multiplier)`.

`options.bossFight` is the boss-fight PROTECTION set: a table of `{ flag = true, ... }`
(an array of flag-name strings works too) naming which of `combat/boss_fight.lua`'s
protections apply to that one registered trainer's enemy side, applied at battle
start. The recognized names are that file's own exported `BOSS_FIGHT_FLAG_NAMES`:

| flag | effect |
|---|---|
| `sun` | The boss's own weather-set becomes permanent and beats even the player's primal weather; the player's side cannot set or override weather. |
| `mistyTerrain` | Same shape, for terrain. |
| `statsDrop` | The boss cannot have ANY stat lowered, hostile or self-inflicted. |
| `type` | The boss's type cannot be changed by an opponent-directed effect (its own self-activated kit, e.g. Protean, still works). |
| `ability` | The boss's ability cannot be changed (Skill Swap, Worry Seed, Entrainment, Gastro Acid, Trace, Mummy, ...). |
| `hardStatus` | The boss is immune to poison/burn/paralyze/sleep/freeze (Rest still works on itself). |
| `softStatus` | The boss is immune to confusion. |
| `antiDrain` | Draining a protected boss harms the attacker instead of healing them. |
| `dimensionLock` | All three room moves (Trick/Magic/Wonder Room) cannot be used for the rest of the fight. |
| `trickRoom` | The battle is permanently in Trick Room; the Trick Room move is banned so it cannot be toggled off. |
| `magicRoom` | The battle is permanently in Magic Room (held items suppressed); the move is banned. |
| `wonderRoom` | The battle is permanently in Wonder Room (Def/Sp. Def swapped); the move is banned. |
| `healblock` | Heal Block: the PLAYER's side cannot restore HP for the rest of the fight -- every heal (move, item, ability, drain, wish, leech seed, ...) restores 0 and is refused with the Gen-5 "was prevented from healing!" style message. Healing is BLOCKED, never converted to damage. See the Heal Block section below. |

Unknown flag names are dropped with a warning. Alias key spellings accepted on
`options`: `bossFightFlags`, `bossFightProtections`, `bossProtections`,
`protections`. The low-level primitives behind it are
`setBossFightProtections(battle, ...name)` (variadic) and
`setBossFightFlagTable(battle, flags)` (a set table) plus `bossFightHas(battle, name)`
to query a live battle, all in `combat/boss_fight.lua`.

Companion exports: `unregisterTrainer(trainerId)`, `getRegisteredTrainer(trainerId)`,
`hasRegisteredTrainer(classId, memberId)`, and `setTrainerMaxHpMultiplier(trainerId, multiplier)`.
Trainer ids are `"CLASS:MEMBERID"` (e.g. `"YOUNGSTER:JOEY1"`). Gen 2 (Gold/Silver/Crystal) only.

The full field-by-field reference is in `trainers/custom_trainer_registry.lua`'s
header, and a complete, working caller mod is the separate **g9-trainer-sample**
mod (its README.md is the modder-facing tutorial).

### Held-item storage API (`combat/modern_held_item_api.lua`, round 98)

Gen 1 has no native held-item mechanic, so the engine gives a mon nowhere to
store one. This mod owns that slot: a plain `mon.g9HeldItem` string field on the
mon table, persisted in the save exactly like every other mon field. Any mod can
build a "hold / switch / remove" tool on top of it.

| export | generation | effect |
|---|---|---|
| `setHeldItem(mon, itemId)` | 1 | Write the equipped-item slot (persists in the save). `nil` clears it; returns `false` for a non-table `mon` or a non-string/non-nil `itemId`. |
| `getHeldItem(mon)` | 1 | Read the equipped-item slot (`nil` if empty). |
| `clearHeldItem(mon)` | 1 | Remove the equipped item. |
| `effectiveHeldItemOf(mon, gen2)` | 1 & 2 | The item `mon` currently holds in the right slot: Gen 2 -> native `mon.item`; Gen 1 -> `g9HeldItem`. |
| `snapshotHeldItems(battle)` / `restoreHeldItems(battle)` | 1 & 2 | The manual form of the automatic post-battle restore below. |
| `HELD_ITEM_SAVED_FIELD` | 1 | The raw slot name (`"g9HeldItem"`), for callers that need to read/migrate the field directly. |

All accessors accept a raw mon table **or** a Gen-1 battler wrapper (`who.mon`).
Gen 2 keeps its own `mon.item` untouched by the Gen-1 accessors -- this mod never
invents a parallel Gen-2 field. (Round 99 wired the *combat* side: `itemOf`/
`setItemOf` in `combat/modern_items.lua` read and write this same slot, so every
held-item effect and every item-removal move now acts on a stored Gen-1 item --
see the round-99 section below.)

**Automatic post-battle restore (both generations, player's party only).** A
landed Fling/Knock Off/Incinerate/Bug Bite/Pluck, a Trick/Switcheroo/Bestow/
Thief, or a consumed berry deletes a battler's item outright; on Gen 2 that write
is not transient because `Battle.party IS save.party`, so the item is genuinely
lost from the save. `combat/modern_held_item_api.lua` snapshots every
item-holding member of the player's party at `battle.started` (priority 1000) and,
at `battle.ended` (priority -1000, the last ended handler), hands back only items
that were there before the battle and are now gone -- the
flinged/thieved/lost/consumed case. An item that survived, or one a mon gained
mid-battle (Bestow/Trick/Recycle), is never clobbered; this restores losses, it
does not rewind equipment. Gen 2 participation is restore-only. Enemy rosters are
deliberately out of scope (rebuilt per encounter, never saved).

### Move usability API (`combat/move_usability.lua`, round 100)

The engine already ENFORCES every "you may not pick that move" rule at
resolution time, but a custom battle scene builds its own move menu and could
not see any of them -- a Choice-locked mon was offered every move, an Assault
Vest holder was offered its Status moves, and Fake Out / Last Resort showed as
ordinary selectable moves. This file is the missing **engine -> scene query**:
one read-only call that answers "selectable, or blocked, and with what
player-facing text". It adds no second resolution path and no second menu --
enforcement stays exactly where it already was.

| export | effect |
|---|---|
| `moveUsability(battle, mon, moveId)` | `nil` if the rules would let it be chosen, else `{ reason = <string>, flag = "choice"|"banned"|"volatile"|"condition" }`. `reason` is the text to show the player. |
| `moveUsabilityReason(battle, mon, moveId)` | the `reason` alone (`nil` if selectable). |
| `moveUsabilityFlag(battle, mon, moveId)` | the `flag` alone (`nil` if selectable). |
| `registerMoveUsabilityGate(moveId, fn)` | a move's OWNER registers its condition answer: `fn(battle, mon, moveId, gen2) -> nil | {reason=, flag=}`. Keyed by move id, one `fn` per id. |
| `moveUsabilityGateOf(moveId)` | the registered `fn`, or `nil`. |
| `itemMoveBanned(battle, mon, moveId)` | the item-carried move-type ban alone (`nil | {flag, item, reason}`) -- also consumed by `Battle2:usableMoves`. |

`mon` may be a raw mon or a Gen-1 battler wrapper. PP is deliberately NOT
consulted (a 0-PP move is the caller's own concern); the one exception is the
Choice lock, which Showdown itself drops once the locked move runs out of PP.

The built-in gates, in order: **Choice** lock (`CHOICE_BAND`/`CHOICE_SPECS`/
`CHOICE_SCARF`, Magic-Room-aware, freed when the item is gone or the locked
move hits 0 PP); **item move-type ban** (Assault Vest bans Status moves, with
the real Me First exception -- one row per item in `ITEM_MOVE_BANS`, so any
future item is one more row); **Taunt/Torment** (Gen 2); then the move's own
registered condition gate. The Choice lock is set on `battle.move_used` (never
by a called move) and cleared on `battle.battler_switched`, writing the SAME
`mon.ggdChoiceLockedMove` field `modern_held_items_phase2.lua` owns, so the menu
and the resolution path can never disagree.

## Turn boundary in scene-driven battles

`battle.turn` counts the rounds of a battle. Native's own turn loop advances it
once per round, but a replacement battle scene (the optional **g9-Battle-Scene**
mod) drives its own loop and resolves through this engine's
`mod.exports.resolveTurnActions` instead of native `runTurn`. That function
therefore advances `battle.turn` itself, once per call (the scene calls it
exactly once per turn), so `battle.turn` means the same thing in a scene-driven
battle as in a native one. Native never calls `resolveTurnActions`, so its own
count is unaffected. Anything that keys off the turn *number* -- most visibly
`combat/modern_combat_protect.lua`'s shared Protect/Detect/Max Guard stall chain,
whose `consecutive` test is `protectChainTurn == battle.turn - 1` -- depends on
this being maintained by whichever loop is driving the battle.

## End-of-turn phase in scene-driven battles

The same `resolveTurnActions` call that advances `battle.turn` also runs the
end-of-turn phase native `runTurn` would have run, so a scene-driven battle is
not just missing the turn *number* but the whole residual sweep: weather
countdown/chip, per-mon status chip (including this engine's Poison Heal
replacement), Leech Seed/Curse, wrap/trap duration, held items (Leftovers,
berries, Black Sludge), Future Sight, Perish Song, screens, and the per-turn
counters (Protect/Endure/Flinch clear, Encore/Disable/taunt durations). Faints
are announced again (`"X fainted!"` plus the real `battle.fainted` runtime event
the ability engines listen to), and the round closes with `battle.turn_ended` --
so every `mod.events:on("battle.turn_ended", ...)` listener works in a scene
battle exactly as in a native one. Implementation: `combat/turn_residuals.lua`
(`runEndOfTurn` + `announceFaints`), called from `resolveTurnActions`; the roster
is the real N-way one (`mod.exports.allActiveBattlers`), so doubles/triples/
boss-fight battlers tick too, and a round ended by a forced switch (Roar/
Whirlwind) skips the residual pass but still emits `battle.turn_ended`, matching
native. Native itself never calls `resolveTurnActions`, so a native battle's own
phase is untouched -- no double tick.

## Move priority

national_dex owns every move's `priority` property; this engine only CONSUMES it.
`Battle:movePriority(moveId, caster)` (combat/turn_order.lua) reads a move's
priority straight from national_dex's own `moveById(moveId)` reply first, so
Protect/Detect (+4), Quick Attack (+1), Counter/Mirror Coat (-5), Trick Room (-7)
etc. order correctly even though the cart's own gen2 move records carry no
priority field and this engine repoints several of those moves' `effect` at its
own handlers. The live record's `priority` and the legacy `Battle.PRIORITY`
effect table are used only for moves national_dex has no record for (e.g.
engine-synthetic ids such as `BATTLE_FORMS_MAXGUARD`). Mods must NOT patch a
move's priority here -- set it in national_dex's own data instead.

## Force/drag switch-out (Dragon Tail, Circle Throw)

`combat/modern_force_switch.lua` implements the target-directed drag for the
two Gen 5 `forceSwitch` moves (`moves.ts` `dragontail`/`circlekthrow`,
num 525/509). Roar and Whirlwind are NOT handled there: both are native Gen 2
moves with a working `EFFECT_FORCE_SWITCH` handler (including the real Gen 2
"user must move second" restriction), and only Dragon Tail / Circle Throw --
which national_dex leaves at `EFFECT_NORMAL_HIT` -- need the modern rule
(drag whenever the hit lands). The drag follows Showdown's step-6
`BattleActions#forceSwitch` (battle-actions.ts:1353): a landed, non-zero
damaging hit on a living target whose side has a living bench mon, blocked by
Suction Cups / Guard Dog / Ingrain (the real `DragOut` no-op states), and
resolved on the enemy side by a random bench pick (the same shape as native
Gen 2) and on the player side by raising the real `battle.forcedSwitch`
request. A Substitute does not block the drag (no `onDragOut` on the
substitute condition). See `combat/MISSING_EFFECTS_PLAN.md` phase 1.

## Stat-stage and stat-source manipulation (Power Swap family, Topsy-Turvy, Power Shift, Strength Sap, Syrup Bomb)

`combat/modern_stat_manipulation.lua` (round 70, plan phase 2) wires the
moves whose real mechanic is not a signed stat delta: the stage **swaps**
(Power Swap, Guard Swap, Heart Swap — all seven boosts, native
speed/accuracy/evasion included), the raw-stat **swaps/splits** (Speed Swap,
Power Split, Guard Split), **Power Shift** (a toggleable self Atk ↔ Def raw
swap that reverts on switch-out/battle end), **Topsy-Turvy** (negates every
nonzero stage), **Acupressure** (a uniform-random eligible stat +2),
**Strength Sap** (heals the user by the target's stage-included Attack, then
drops it), and **Syrup Bomb** (a source-linked, exactly-three-tick Speed
drop). Swaps/splits/Topsy write stages through a raw `setBoost`-shaped
read/write pair (mod store for atk/def/spa/spd — `changeStage`'s own store —
native `battle.stages[side]`/`who.stages` for speed/accuracy/evasion), so
they never clamp, emit, or trigger Contrary/Defiant; every genuinely signed
change still goes through the exported `changeStage`, so Mist/Substitute,
the Clear Body family and the boss `statsDrop` guard all still apply. Raw
stat reads/writes use `storedStats` directly (not `rawStat`, which applies
Wonder Room's key swap). A protected boss refuses a direct write that would
worsen it, and a target-directed move without `bypasssub` is refused by a
Substitute. See `combat/MISSING_EFFECTS_PLAN.md` phase 2.

## Critical-hit overrides (always-crit moves, Laser Focus)

`combat/modern_crit_override.lua` (round 71, plan phase 3) wires the two
crit-related gaps. (1) The five Showdown `willCrit: true` moves — Wicked
Blow, Surging Strikes, Frost Breath, Storm Throw, Flower Trick — always
crit. national_dex encodes `willCrit` as the `critRate = 6` sentinel (0
ordinary, 1 the 25 real high-crit moves, 6 exactly those five), and
`main.lua`'s `wireMovepoolSubEffects` now patches `alwaysCrit = true` for
`critRate >= 6` (instead of `highCrit`). The override rides
`modern_combat.lua`'s existing crit **stage** modifier chain
(`registerCritStageModifier`, stage 3 = guaranteed): a stage-3 result has
`CRIT_STAGE_DENOM[3] = 1`, and `modernCritRoll` still consults Battle Armor
/ Shell Armor *before* the stage lookup, so the guaranteed crit is still
negated by a crit-immune holder — the same behaviour as Showdown's
`CriticalHit` event, which fires for `willCrit` moves too. (2) **Laser
Focus** is a duration-2 self volatile granting the same guaranteed crit
(crit-ratio 5 clamps to the top tier); it is a direct switch-scoped field
(`laserFocusTurns`, listed in `status_condition_cleanup.lua`'s
`SWITCH_SCOPED`) decremented by a `battle.turn_ended` listener. Flower
Trick's Showdown `accuracy: true` is a `sureHit` flag (a critRate-6 move
whose dex accuracy is 0) honoured by a `battle.accuracy` wrap — a no-op on
Gen 2 (which already treats a non-positive accuracy as never-miss) that
also fixes Gen 1. `modern_combat.lua` now threads the defender through the
crit ctx on both call shapes (`battle.crit` hook and direct), which also
closes a latent gap where the Battle Armor / Shell Armor check never saw
`ctx.target`. See `combat/MISSING_EFFECTS_PLAN.md` phase 3.

## Damage-stat source overrides (Foul Play, Body Press)

`combat/modern_damage_source.lua` (round 72, plan phase 4) wires the moves
that do not read their own category's stat pair, via a new
`modern_combat.lua` seam `registerDamageSourceOverride(id, fn)` applied in
`computeModernDamage`: **Body Press** attacks with the user's own Defense
(stat and stage; Showdown `overrideOffensiveStat: 'def'`), and **Foul Play**
reads the **target's** Attack (stat and stage) while still defending off the
target's Defense (`overrideOffensivePokemon: 'target'`). Psyshock /
Psystrike / Secret Sword (the defensive-side equivalents) were already
handled inline. Because the override moves the effective offensive mon, the
Unaware checks, the effective stat's stage, the user's burn (`not special`)
and the held-item category stat (Choice Band still boosts Body Press) all
follow it, matching Showdown's `getDamage`/`ModifyAtk` ordering. See
`combat/MISSING_EFFECTS_PLAN.md` phase 4.

## Action order and chosen-move visibility (Sucker Punch, Fake Out, Focus Punch, After You, Quash)

`combat/modern_action_order.lua` (round 73, plan phase 5) wires the moves
whose legality depends on what the *other* battler chose this turn.
`combat/turn_order.lua` now publishes `battle.__g9ChosenMoves[mon]` (from the
scene's `actingBattlers` contract, and from a `battle.turn_order` hook for the
native path) and exports `chosenMoveOf`; `actionGateReason` reads it so
**Sucker Punch**/**Thunderclap** fail unless the target is still queued with a
non-Status move, **Upper Hand** unless that move has positive base priority,
and **Fake Out**/`Focus Punch` off the existing first-action /
move-owned-damage flags. Failures announce, spend PP and `markMissed` by
substituting `Battle.moveEffectRecordFor` for one native call (the Part D
pattern). **After You**/**Quash** are real reorders through new
`prioritizeActor`/`deprioritizeActor` seams and a live order list the
resolution loop now walks by index. See `combat/MISSING_EFFECTS_PLAN.md`
phase 5.

## Party recovery and sacrifice (Aromatherapy, Heal Bell, Wish, Healing Wish, Memento, Destiny Bond, ...)

`combat/modern_party_support.lua` + `combat/modern_faint_sacrifice.lua`
(round 74, plan phase 6) wire the party-wide recovery moves and the
self-KO / faint-triggered sacrifices. The first file exports the shared
party vocabulary (`g9SidePartyOf`, `g9AlliesAndSelf`, `g9HealFraction`,
`g9HealAmount`, `g9CanSwitchOut`, ...): **Aromatherapy**/**Heal Bell**
cure every status on the user's side (party + active, via `requestAdjacency`),
**Jungle Healing** heals 25% and cures, **Refresh** cures except Sleep/Freeze,
**Take Heart** is +1 SpA/SpD plus a cure, **Wish** is a per-side slot
condition that heals the current occupant the following turn end, and
**Revival Blessing** revives the first fainted member to half max. The second
file handles the sacrifices: **Healing Wish**/**Lunar Dance** self-KO (or
fail when the side can't switch) and full-restore the incoming mon (Lunar
Dance also refills PP), **Memento** drops Atk/SpA -2 then faints the user,
**Destiny Bond**/**Grudge** arm a volatile and answer a `battle.fainted`
event using a `battle.damage_dealt`-recorded killer, and **Last Resort** rides
`modern_action_order.lua`'s reusable `registerFailGate` seam. See
`combat/MISSING_EFFECTS_PLAN.md` phase 6.

## Side conditions, screens and hazard manipulation (Court Change, Brick Break, Defog, Magic Coat, Snatch, Imprison)

`combat/modern_side_conditions.lua` (round 75, plan phase 7) wires the
side-condition family. **Court Change** swaps both sides' screens,
Spikes and the mod's hazards. **Brick Break**/**Psychic Fangs** shatter the
defender's screens *before* their own hit lands (an empty `kind="full"`
record keeps the damage; a `Battle:useMove` wrap clears
reflect/lightScreen first). **Defog** clears the target side's
screens+hazards, the user side's hazards, and the terrain, with an evasion
drop. **Magic Coat** and **Snatch** arm one-turn volatiles that the
`useMove` wrap reads to bounce a reflectable move back / steal a snatchable
self move (the single-turn, flag-gated twins of the Magic Bounce ability).
**Imprison** records the holder's moves and filters them out of the foe's
`Battle:usableMoves`. See `combat/MISSING_EFFECTS_PLAN.md` phase 7.

## Field effects (Gravity, Ion Deluge, Electrify, Mud/Water Sport, Nature Power, Powder, Tailwind, Aurora Veil, Lucky Chant, Fairy Lock, Tea Time)

`combat/modern_field_effects.lua` (round 76, plan phase 8) wires the remaining
whole-field effects (the three Rooms already shipped in `combat/trick_room.lua`
-- nothing was redone there). Whole-field state (`gravityTurns`,
`mudSportTurns`, `waterSportTurns`, `ionDelugeTurns`, `fairyLockTurns`) lives
on the battle object like `weather`/`trickRoomTurns`; the side-scoped
**Tailwind**/**Aurora Veil**/**Lucky Chant** ride the engine's own
`battle.screens[side]` table so Court Change/Defog/Brick Break see them.
**Gravity** grounds every active mon (`gravityGrounded`, read by the
Ground-immunity, hazard and terrain groundedness checks) and boosts accuracy
x5/3 through the `battle.accuracy` hook; **Ion Deluge**/**Electrify** and
**Powder** ride one `Battle:useMove` wrap that mutates-and-restores the move's
own type (or detonates a Fire move) for the synchronous native call;
**Mud/Water Sport** weaken Electric/Fire via `registerDamageModifier`;
**Lucky Chant** suppresses the `battle.crit` hook; **Tailwind** doubles
`Battle:effectiveSpeed`; **Fairy Lock** composes onto the existing
`Battle:switchLocked` trap wrap; **Nature Power** re-dispatches by terrain;
**Tea Time** makes every active mon eat its held Berry. See
`combat/MISSING_EFFECTS_PLAN.md` phase 8.

## Trapping moves (Mean Look, Block, Spider Web, Jaw Lock, Anchor Shot, Spirit Shackle, Octolock)

`combat/modern_trap_moves.lua` (round 77, plan phase 9) wires the NON-chip
trapping family. These deliberately do **not** reuse `GALAR_TRAP_EFFECT`: the
`trapped` volatile (Showdown `conditions.ts`) only pins -- no per-turn chip --
where `GALAR_TRAP_EFFECT` models the `partiallytrapped` Wrap/Bind family through
Gen 2's native `wrapCount`. So each of these writes Gen 2's own pin field
(`volatile(trapper).trapsTarget`, the exact field native `EFFECT_MEAN_LOOK` sets
and `Battle:switchLocked` / `breakTrapsOnSend` read), which makes the engine's
existing switch gates do all the work. **Mean Look**/**Block**/**Spider Web**
share one `kind="primary"` record; **Octolock** adds a real Def/SpD -1
`onResidual`-style end-of-turn drop while its source is active; **Jaw Lock**,
**Anchor Shot** and **Spirit Shackle** are damaging, so they carry an empty
`kind="full"` record and pin from a `battle.damage_dealt` listener (Jaw Lock
pins BOTH sides). Ghost-types are immune (the real Gen 6+ trapping immunity),
and the Octolock coat plus the Gen 1 `g9Trapped` marker are switch-scoped. Gen 1
has no switch gate at all, so its half records the marker only -- the same
honest partial GMAX.TERROR carries. See `combat/MISSING_EFFECTS_PLAN.md`
phase 9.

## Ability-manipulation moves (Role Play, Simple Beam, Doodle, Corrosive Gas)

`combat/modern_ability_change_moves.lua` (round 78, plan phase 10) closes the
remaining ability-manipulation moves alongside the existing Skill Swap / Worry
Seed / Entrainment / Gastro Acid. Every real change still routes through the one
`ability_dispatch.lua` `setAbility` primitive, so all of them are combat-only
(natural ability restored on switch-out / battle-end) and boss-immune.
**Role Play** copies the target's ability onto the user; **Simple Beam** makes
the target's ability Simple; **Doodle** copies the target's ability onto the
user's side; each reads the real per-move Showdown refusal flags
(`failroleplay` / `cantsuppress` / `failskillswap` / `noentrain`), enumerated for
the ability ids this engine actually builds. **Corrosive Gas** is NOT an ability
move -- Showdown destroys the target's held ITEM -- so it lives in
`combat/modern_items.lua` beside Knock Off (Sticky Hold / Mail-unremovable
checks reused). Phase 10 also fixed a real Gen 2 message bug: the pre-existing
handlers returned their strings, but Gen 2's dispatch discards a run handler's
return value, so they now emit through the shared `finish()` helper
(`modern_stat_manipulation.lua`'s Phase 2 convention). See
`combat/MISSING_EFFECTS_PLAN.md` phase 10.

## Ability gaps close-out (Corrosion, Poison Puppeteer, Klutz, Mold Breaker, the accuracy/evasion family, Magic Guard sand)

Round 79 (plan phase 11) closes the remaining documented ability gaps, most of
them by lifting each mechanic to a **shared primitive** in
`combat/modern_combat.lua` instead of scattering inline checks:

- `attackerIgnoresDefenderAbility(user)` -- the one **Mold Breaker** primitive
  (MOLDBREAKER / TERAVOLT / TURBOBLAZE). Now consulted by
  `abilities/engine/type_immunity.lua` AND `abilities/engine/damage_immunity.lua`
  (Wonder Guard, plus the Bulletproof / Soundproof / Wind Rider `FLAG_IMMUNITY`
  set), so a Mold Breaker attacker bypasses exactly what the real ability does.
- `statusTypeImmune(battle, mon, canonical)` -- **type-based status immunity**:
  Fire is never burned; Poison / Steel are never poisoned (badly or otherwise).
  Applied at both mod-owned infliction seams (`abilities/engine/inflict_status.lua`
  and `combat/modern_combat_protect.lua`'s contact-shield riders).
- `corrosionPiercesPoison(user)` -- **Corrosion**'s real pierce, keyed off the
  inflicting *source's* ability (Showdown `sim/pokemon.ts` `setStatus`) so it
  un-defers `abilities/data/corrosion_deferred.lua` into a live
  `abilities/data/corrosion.lua`. The same generic-secondary path also fires
  **Poison Puppeteer** (Pecharunt-only, target != user, confusion-immunity gated).
- **Klutz** is a real held-item suppression gate in `combat/modern_items.lua`'s
  existing `held_item.trigger` hook (the engine's one chokepoint for all eight
  trigger kinds). Honest partial: it suppresses trigger-driven effects, not an
  item's own passive stat read (`itemBoostPercent`, Phase 12).
- `abilities/engine/accuracy_multiplier.lua` gains the whole
  **accuracy/evasion family**: Sand Veil (x0.8 in sand), Snow Cloak (x0.8 in
  snow) and Tangled Feet (x0.5 while confused) as evasion-stat modifiers, plus
  the **ignore-evasion** half -- Keen Eye / Illuminate / Mind's Eye on the
  attacker and Unaware on the defender -- by temporarily zeroing the relevant
  Gen 2 stage around the native accuracy roll.
- `abilities/engine/damage_immunity.lua` replaces `Battle:tickWeather` (the
  native is delegated to for every non-sand weather) so **Magic Guard** (and
  Sand Force / Sand Rush / Sand Veil / Overcoat) is exempt from the Gen 2 sand
  chip, with the type gate and fraction still supplied by `Gen2Effects`.

SHEER FORCE was already complete on both halves (the +30 % damage half at
`abilities/engine/damage_multiplier.lua:567`, the secondary suppression at
`main.lua:298`) -- only stale comments were corrected. See
`combat/MISSING_EFFECTS_PLAN.md` phase 11.

## Terrain/type residue (Misty Terrain confusion, Dynamax type-change immunity)

Round 80 (plan phase 12) closes the two genuinely-open items of that phase
(its held-item and Toxic Spikes Levitate bullets were already closed by
earlier rounds -- see the plan):

- **Misty Terrain now blocks the generic confusion secondary.** `main.lua`'s
  generic secondary listener (and Poison Puppeteer's confusion) now route
  through `Battle:applyConfusion` instead of writing
  `volatile.confuseCount` directly, so `combat/modern_terrain.lua`'s Misty
  wrap -- which intercepts exactly that dotted entry point -- actually sees
  them. This also picks up the native Substitute / `HELD_PREVENT_CONFUSE` /
  already-confused guards and the real "became confused!" message.
- **`combat/type_override_primitives.lua`'s Dynamax type-change immunity is
  wired.** An opponent-directed type change (Soak, Magic Powder, ...) now
  fails on a Dynamaxed mon, reading the `mon.__g9Dynamaxed` marker this
  mod's own `gigantamax/dynamax_battle.lua` stamps on battle_forms'
  `dynamax_applied` / clears on `dynamax_reverted`. Self-directed changes
  stay allowed (the real asymmetry).

See `combat/MISSING_EFFECTS_PLAN.md` phase 12.

## Conditional / variable power (Phase 13)

Round 82 (plan phase 13) wires 29 conditional/variable-power moves in
`combat/modern_power_conditions.lua` (booted right after
`modern_movepool_counter`). Every one goes through the existing
`registerPowerOverride` seam -- a **base-power substitution** computed before
the formula, never a trailing `registerDamageModifier` (doubling finished
damage is a couple of HP off from doubling power, because of the formula's own
`+2` and inner floors). The families:

- **Pure substitution:** Eruption / Water Spout / Dragon Energy (scaled by the
  user's HP fraction), Return / Frustration (happiness), Rage Fist
  (times-attacked), Stored Power (positive stages), Last Respects (party
  fainted), Fury Cutter (consecutive uses, clamped to 160).
- **basePowerCallback:** Avalanche / Revenge (after being hit this turn),
  Payback (target already moved), Bolt Beak / Fishious Rend (user moves first),
  Hex (target statused/comatose), Smellingsalts (paralyzed), Wake-Up Slap
  (asleep), Rising Voltage (Electric Terrain + grounded), Collision Course /
  Electro Drift (super effective, `chainModify([5461,4096])`).
- **onBasePower:** Brine (≤50% HP), Facade (statused, non-sleep), Fickle Beam
  (30% gamble), Fusion Bolt / Flare (partner move last turn), Lashout (stat
  lowered this turn), Psyblade (Electric Terrain), Expanding Force (Psychic
  Terrain + grounded), Retaliate (ally fainted last turn).

STOMPINGTANTRUM, TEMPERFLARE, PURSUIT and COMEUPPANCE are explicitly deferred
(they need "previous move failed", switch interception, or a flat
`damageCallback` return, not a scaled power).

This round also closes a **real category-resolution bug**: national_dex writes
modern move categories lowercase (`"physical"`), but `MoveCategory.of` only
recognises the capitalized spelling and otherwise falls back to its
`power == 0 → "Status"` heuristic -- so a computed-power modern move (Return,
Frustration, Flail, Reversal) was misread as a status move and returned 0
damage before its override was ever consulted. `computeModernDamage` now lets a
record's own explicit lowercase category win whenever `MoveCategory.of` would
have said "Status".

See `combat/MISSING_EFFECTS_PLAN.md` phase 13.

## Type-modifying moves (Phase 14)

Round 83 (plan phase 14) wires 12 moves whose live type (and, for three,
category) depends on battle state at the moment of use, in
`combat/modern_type_modify_moves.lua` (booted right after `modern_items`).
The seam is the same one the Aerilate/Pixilate ability family already uses
(`type_override_moves.lua`): a `battle.damage` wrap (priority 150, inside the
ability seam's 200) mutates the shared `move.type` for exactly one synchronous
call and restores it. Because `computeModernDamage`'s STAB and effectiveness
read that same mutated type -- and gen2-Battle's "It doesn't affect" gate is
driven off the returned `info.effectiveness` -- the conversion is fully real,
not cosmetic. The moves:

- **Item-driven:** Judgment (`onPlate`), Multi-Attack (`onMemory`), Techno
  Blast (`onDrive`), Natural Gift (`naturalGift`). Item "facts" come from
  `national_dex.itemFlags`; Magic Room and Klutz suppress them.
- **Own-type:** Revelation Dance (the user's first live type), Hidden Power
  (this engine's DV-derived routine, else Showdown's Dark default).
- **Field/state:** Weather Ball (Fire/Water/Rock/Ice by weather), Terrain
  Pulse (Electric/Grass/Fairy/Psychic Terrain while grounded), Tera Blast /
  Tera Starstorm (the active Tera type; Stellar for Terapagos-Stellar), Raging
  Bull (the Paldean Tauros form).

Four also change base POWER via `registerPowerOverride`: Weather Ball 50→100
in any weather, Terrain Pulse 50→100 on any terrain while grounded, Tera Blast
100 for a Stellar Terastallization, Natural Gift from the berry's
`basePower`. Photon Geyser / Tera Blast / Tera Starstorm flip to **Physical**
when the user's raw Attack exceeds its raw SpA. Honest partials (documented
in-file, not faked): Natural Gift does not fail without a berry; Weather Ball
does not honour Air Lock / Cloud Nine; Raging Bull / Tera Starstorm match both
species-id spellings and otherwise keep the record's Normal.

See `combat/MISSING_EFFECTS_PLAN.md` phase 14.

## Stat-stage boosts (Phase 15)

Round 84 (plan phase 15) wires 19 moves in `combat/modern_movepool_stages.lua`
(no new file), repointed by `main.lua`'s `CUSTOM_EFFECT_PATCH`. national_dex
leaves every one at `statChance = 0`, so the generic secondary listener never
applied them; they now use the file's own `primary()`/`applyChange` helpers, so
attack/defense/spa/spd land in modern_combat's store (the one
`computeModernDamage` reads) and speed takes the native path. Four of them
(Baby-Doll Eyes, Feather Dance, Howl, Shelter) already had a native effect id,
but that wrote the engine's own stage table -- invisible to modern damage --
so repointing them is the real fix. The flat boosts: Quiver Dance, Victory
Dance, Tail Glow, Work Up, Autotomize, Defend Order, Shelter, Howl, and the
target-directed Tickle / Feather Dance / Baby-Doll Eyes. Seven have a second
mechanic handled bespoke: **Fillet Away** / **Belly Drum** cost half max HP
(and fail at low HP / max Attack), **Captivate** is gender-gated, **Gear Up** /
**Magnetic Flux** only reach Plus/Minus holders, **Tidy Up** also clears
Substitutes and hazards, **Geomancy** charges for a turn, and **Curse** is two
moves in one body (self boost for a non-Ghost, a curse volatile for a Ghost).
Honest partials: Autotomize's weight halving is not modelled; the Ghost Curse
residual is Gen 2 only; Gear Up / Magnetic Flux reach only the user in singles.

See `combat/MISSING_EFFECTS_PLAN.md` phase 15.

## Recovery moves (Phase 16)

Round 85 (plan phase 16) ships `combat/modern_recovery_moves.lua`, booted right
after `modern_movepool_damage`. It closes the heal family -- but only two of
the five plan moves actually needed code. **Heal Order / Milk Drink / Slack
Off** are a plain 50% self-heal, and national_dex already marks them
gen1Effect `HEAL_EFFECT` / gen2Effect `EFFECT_HEAL` with both `*Modeled` flags
true; this engine's own heal primitives split on move id and heal
`floor(maxHp/2)` for anything but Rest, so they were **already native** and
nothing is repointed for them (recorded in `combat/NATIVE_COVERAGE.md`
instead). **Roost**'s heal was likewise native; the move is repointed only so
its unmodelled second half resolves in the same handler -- the real
`duration: 1` condition that removes FLYING from the user's defensive typing
until end of turn. The drop is applied at `resolvedTypeMult`'s existing
`mod.exports.defensiveTypesOf` seam (wrapped, never replaced, so modern_tera's
Stellar override still runs first) and therefore holds on Gen 1 and Gen 2
alike. Showdown's own ordering is matched literally (`battle-actions.ts:1201`):
the `heal` block runs first and a full-HP Roost fails there, skipping the
`self` volatile -- so no HP, no type drop. A Terastallized user heals but
keeps Flying. **Aqua Ring** is the one genuinely missing move (no native
effect at all): a 1/16 end-of-turn self volatile with a switch-scoped flag.
Honest partials (in-file): Aqua Ring's "passed on by Baton Pass" half is
deferred (Baton Pass is phase 20); the Roost drop is defensive-only, which is
all it can matter for since the user cannot attack again before the turn ends.

See `combat/MISSING_EFFECTS_PLAN.md` phase 16.

## Charge and consecutive-use (Phase 17)

Round 86 (plan phase 17) ships `combat/modern_charge_moves.lua`, booted right
after `modern_recovery_moves`. It closes three related families.

**Charge moves.** Solar Blade, Meteor Beam and Sky Drop ride the engine's own
charge machinery -- a `move_effects` record carrying a `charge` table, plus a
matching Gen 2 `Effects.CHARGE` entry for the announce text, the exact shape
`modern_weather.lua`'s GALAR_SOLARBEAM_EFFECT already uses. Solar Blade's
sun-skip is added to `modern_weather.lua`'s own `SUN_SKIPS_CHARGE` table (the
Solar Beam mechanism, Gen 1 only -- the same documented Gen 2 limitation Solar
Beam already has). Its weak-weather power halving (rain/sand/snow, Showdown's
`weakWeathers`) is a `registerPowerOverride`, with the Mega Sol exemption
reusing the same personal-"as if sun" carve-out Synthesis heals use. Meteor
Beam's charge-turn Sp. Atk +1 rides the real `battle.charge_required` hook --
called on the charge turn only -- via the exported, unit-testable
`mod.exports.applyChargeTurnBonus`, keyed by both the move id and the
repointed effect string (Gen 1's payload carries the move arg, Gen 2's the
def). Gen 1's announce text is keyed by move id in BattleState's own
`CHARGE_TEXT`, which a mod cannot extend, so a modern charge move falls back
to the engine's generic line (cosmetic only).

**Consecutive-use ladders.** Ice Ball and Rollout are `30 * 2^(n-1)` capped at
five, doubled once more while Defense Curl's marker is up; Echoed Voice is
`40 * mult`, 1..5, field-wide. All three ride `registerPowerOverride`, fed by a
`battle.move_used` counter that mirrors `modern_power_conditions.lua`'s own
Fury Cutter volatile (reusing `battle.__g9TurnIndex` + a last-use turn). The
counters are set on the real event, never inside an override -- the AI also
runs overrides to preview a candidate move, the exact double-count trap Fury
Cutter's own comment names.

**Charge-turn reactions.** Shell Trap and Beak Blast arm from the
`battle.turn_started` payload's chosen actions and react on
`battle.damage_dealt`. Shell Trap's "fires only if hit by a physical move"
rides `modern_action_order.lua`'s reusable `registerFailGate` seam; Beak
Blast burns any mon that makes contact with the armed user, through the shared
`mod.exports.makesContact` so Long Reach is honoured. Both clear at turn end
and on switch.

Honest partials (in-file): Sky Drop's target-carry half is not modelled (the
engine's charge machinery is user-side only), so it plays as a one-mon Fly;
Ice Ball/Rollout's real 5-turn lock is not modelled (no generic lock seam, and
reusing the rampage lock would wrongly add Outrage's confusion); the Shell
Trap gate is Gen 2 (the charge and power halves work on both). Round and the
three Pledges are deliberately NOT repointed: their base damage is already
correct and their only missing half needs a partner's move, which is
unobservable in 1-vs-1 -- the structural exemptions' own reasoning.

See `combat/MISSING_EFFECTS_PLAN.md` phase 17.

## Guard / contact interaction (Phase 18)

Round 87 (plan phase 18) ships `combat/modern_guard_contact.lua`, booted right
after `modern_trap_moves` (which owns the last of its dependencies). It closes
the guard-ignoring, contact-reaction and prototype-legend families in one file,
plus small edits to four existing ones.

**Protect-breakers.** Phantom Force, Shadow Force and Hyperspace Hole join Feint
in `main.lua`'s `BYPASSES_PROTECT` table, which `wireMovepoolSubEffects` stamps
onto the live move record that `modern_combat_protect.lua`'s own `battle.damage`
hook already reads. The two Force moves are also charge moves, so they get their
own `GALAR_PHANTOMFORCE_EFFECT` / `GALAR_SHADOWFORCE_EFFECT` charge records (the
Sky Drop shape, `invulnerable = true`) via `CUSTOM_EFFECT_PATCH` and a matching
Gen 2 `Effects.CHARGE` entry.

**Ignore-defense / ignore-evasion.** Chip Away, Sacred Sword and Darkest Lariat
join `main.lua`'s `IGNORE_DEFENSIVE`/`IGNORE_EVASION` maps. `ignoreDefensive` is
implemented directly in `computeModernDamage`, zeroing the effective defender's
Def/SpD stage for the computation only -- the exact hole Unaware's attacker half
already plugs. `ignoreEvasion` rides `battle.accuracy` by zeroing the defender's
evasion stage for one roll and restoring it immediately after, the
zero-and-restore idiom `abilities/engine/accuracy_multiplier.lua` established for
Keen Eye/Unaware; it handles both Gen 2's `battle.stages[side].evasion` and Gen
1's wrapper `target.stages.evasion`.

**Ignore-ability.** Moongeist Beam and Sunsteel Strike join an `IGNORE_ABILITY`
map. A new `battle.damage` wrap sets a single module-local `ignoredAbilityMon`
inside `abilities/ability_dispatch.lua` -- the one choke point every ability check
funnels through, the same reasoning Neutralizing Gas's own comment gives for
living there -- for the duration of the computation, then clears it
error-or-not. That blinds Filter/Solid Rock/Wonder Guard/Sturdy/etc. to the
target exactly as Showdown's `move.ignoreAbility`.

**The three damage-formula moves live in `computeModernDamage`.** Flying Press
adds a second `TypeChart.rows("FLYING", targetTypes)` pass (folding it into the
same `mult`) on top of its Fighting pass; Synchronoise early-returns 0 unless the
target shares one of the user's current types (via `curTypesOf`); False Swipe
clamps the post-formula damage to `target.hp - 1` (returning 0 at 1 HP so the
engine's min-1 clamp can't faint it). Supercell Slam joins Reckless's crash list
in `abilities/engine/damage_multiplier.lua`'s `CRASH_DAMAGE_MOVES`, and
`modern_side_conditions.lua` exports its private `clearTerrain` for the on-hit
riders.

**The on-hit riders are one `battle.damage_dealt` listener keyed by move id:**
Ice Spinner and Steel Roller clear terrain (via the newly-exported `clearTerrain`),
Thousand Waves pins through `trapApplyPin`, Freezy Frost resets both the modern
and native stage stores, Ceaseless Edge lays Spikes and Stone Axe Stealth Rock
(via `hazardsFor`/the native `battle.spikes` store), and Fell Stinger's
KO-gated +3 Attack rides `changeStage`. Poltergeist and Steel Roller's fail
conditions ride `registerFailGate`, exported as the named, unit-testable
predicates `poltergeistGate`/`steelRollerGate`.

Honest partials (in-file): Hyperspace Hole's `bypasssub` Substitute-pierce is not
modelled (no hook on this engine's Substitute redirection, the same gap every
other bypasssub move carries); Order Up needs Commander/Tatsugiri form, neither of
which the mod models, so it deals plain damage; Supercell Slam's crash-on-miss
self-damage has no "the move missed" event to hang off (only its Reckless boost
half is wired); Ceaseless Edge's Spikes tick on Gen 2 only (Gen 1 has no
switch-in Spikes damage anywhere in this engine); the two fail gates are Gen 2
only (`registerFailGate` runs inside `Battle:useMove`).

See `combat/MISSING_EFFECTS_PLAN.md` phase 18.

## Item / held-item interaction (Phase 19)

Round 88 (plan phase 19) ships `combat/modern_item_moves.lua`, booted right
after `modern_guard_contact` (which is already after `modern_items`,
`modern_field_effects` and `modern_ability_change_moves`). It closes the
item-swap / item-give / item-steal / boost-steal / ability-suppression /
pseudo-weather families in one file, plus one export added to
`combat/modern_ability_change_moves.lua`.

**Item swap and give.** Trick and Switcheroo share one handler (Showdown's own
`onHit` bodies are byte-identical): take the target's item then the user's,
abort and restore BOTH when either take is refused or both are empty, else swap
them. Bestow moves the user's item to the target, failing when the target
already holds one or the user has none. The take/remove refusal mirrors
`Pokemon.takeItem` -- Sticky Hold (the real TakeItem refusal) plus
`modern_items`' own `isUnremovable` (the Mail exemption), the same two checks
Knock Off already applies.

**Thief** is Covet's twin (Showdown `onAfterHit`, user must hold nothing), wired
on `battle.damage_dealt` exactly as Covet already is.

**Spectral Thief** steals boosts through a pre-damage `battle.damage` wrap
(priority 100), the real `hitStepStealBoosts` position ahead of
`hitStepMoveHitLoop`, so the stolen Attack boosts the very hit that takes it.
It copies every positive stage in BOTH stores -- the mod's own `stagesFor`
bucket for atk/def/spa/spd and the native per-side/per-mon store for
speed/accuracy/evasion -- and zeroes them on the target. An immune hit never
steals (Showdown checks type immunity before the steal step), tested through the
mod's own `resolvedTypeMult`. Exported as `spectralThiefStealBoosts`.

**Core Enforcer** suppresses the target's ability by reusing Gastro Acid's own
`setAbility(..., nil)` call and `modern_ability_change_moves`' newly-exported
`CANNOT_SUPPRESS` set. Showdown's `newlySwitched || queue.willMove(target)` gate
reduces to "the target has already moved this turn" (a just-switched mon has
not, so the moved check subsumes the switched check), read off the same
`movedThisTurn` flag `modern_power_conditions` writes.

**Plasma Fists** sets `battle.ionDelugeTurns = 1` directly -- the plan's
`registerPseudoWeather` primitive does not exist; the field-effects phase wires
each pseudo-weather as a plain battle-scoped counter -- so the existing
`effectiveMoveType` turns every Normal move Electric for the rest of the turn,
and the existing `turn_ended` tick clears it.

**Flame Burst**'s 1/16 ally splash is real code that simply has no targets in a
1-vs-1 fight (a target side has no other active battler), so it runs, finds
nobody, and the move keeps its already-correct plain damage. It is exported
(`flameBurstSplash`) and unit-tested against a stubbed roster rather than
faked.

Honest partials (in-file): Core Enforcer and Flame Burst's real
`onAfterSubDamage` half is not modelled (this engine's `dealDamage` absorbs a
Substitute hit and returns before it emits `battle.damage_dealt`, the same gap
every bypasssub move here carries). The whole family acts on both generations as
of round 99 -- item reads/writes are gen-aware (`itemOf`/`setItemOf`, Gen 2's
native `mon.item` vs Gen 1's `g9HeldItem` save slot) and every move moves a
stored Gen-1 item for real; see the round-99 section below.

See `combat/MISSING_EFFECTS_PLAN.md` phase 19.

## Pivots & move-copying (Phase 20)

Round 89 (plan phase 20) ships `combat/modern_pivot_moves.lua`, booted right
after `modern_item_moves`, consuming `switch_primitives`' `requestSwitch` and
`modern_combat`/`field_duration`'s weather + stage exports. The eleven moves
split into four shapes:

**Pivots (Baton Pass, Shed Tail, Chilly Reception).** Baton Pass is NOT
re-registered -- the native Gen 2 `EFFECT_BATON_PASS` already moves the
volatile table, so the handler is read live from
`Battle.MOVE_EFFECT_RECORDS.EFFECT_BATON_PASS` and pcall-chained only to close
the one real gap: the mod's per-mon atk/def/spa/spd `stagesFor` bucket is left
behind because the native path never emits `battle.battler_switched` (the event
`modern_combat`'s stage-store lifecycle listens on). The bucket is copied
forward keyed on the PRE-switch side (`Battle:sideOf` is a plain
`mon == self.player` identity test) and `"lockOn"` is appended to the live
`Effects.BATON_PASS_DROPS` list (Showdown's `lockon` is `noCopy`). Shed Tail
pays `ceil(maxHp/2)` and stashes the quarter-max-HP substitute as a pending
stamp (`battle.__g9ShedTailSub`) that is re-applied on the real
`battle.battler_switched` event, because this engine's own switch path
`clearVolatile`s both the outgoing and incoming mon; only `substitute` copies
(never boosts), per `pokemon.ts:1248-1250`. Chilly Reception sets `SNOW` via
the field-duration weather path then requests a switch.

**Move-calling (Assist, Copycat, Instruct).** One nested-dispatch seam: a
`Battle:useMove` under `battle.copyDepth` (the same called-move guard
`modern_field_effects.lua`'s Nature Power uses). Assist samples another party
member's eligible moves (skipping `noassist`); Copycat repeats the battle's
previous move; Instruct makes the target repeat its last move immediately,
refused for `failinstruct`/charge/recharge/beakblast/focuspunch/shelltrap or
exhausted PP. Instruct is a synchronous nested dispatch, not queue
re-insertion (the engine's `runTurn` is an unexported closure) -- Showdown's
own `queue.prioritize` makes the instructed move resolve right after Instruct,
which this reproduces.

**Move-learning (Sketch).** Permanently rewrites the user's own Sketch slot to
the target's last move; `Battle.party` IS `save.party` on Gen 2, so the write
persists like the native learn paths.

**Self/status shuffles (Lock-On, Mind Reader, Psych Up, Psycho Shift).**
Lock-On / Mind Reader are a pure re-point at the native
`Battle.MOVE_EFFECTS.EFFECT_LOCK_ON` (target `lockOn` + the
`Battle:consumeLockOn` sure-hit arm), unreachable only because national_dex
registers both at `EFFECT_NORMAL_HIT`. Psych Up copies all 7 stage keys (mod
store atk/def/spa/spd; native store speed/accuracy/evasion) plus `focusEnergy`
and the mod's `laserFocusTurns`. Psycho Shift transfers the user's status and
cures it only when the transfer succeeds (a refused `trySetStatus` skips the
cure, `battle-actions.ts:1223-1229` + `:1317-1334`).

Honest notes (in-file): Copycat's tracker fires on `battle.move_used`, so a move
that then misses/fails is still copyable (Showdown skips failed moves only via
`clearActiveMove(true)`); `dragoncheer`/`gmaxchistrike` are not modelled by this
engine; every handler routes through `normalize()` so a Gen 1 caller cannot
crash, but the pivot primitives are Gen 2 machinery -- `isGen2Battle` gates
them rather than half-building a Gen 1 path.

See `combat/MISSING_EFFECTS_PLAN.md` phase 20.

## Status / volatile infliction residue (Phase 21)

Round 90 (plan phase 21) ships `combat/modern_status_moves.lua`, booted right
after `modern_pivot_moves` (plus the Magnet Rise arm in `modern_combat.lua`'s
`resolvedTypeMult` and two fields added to `status_condition_cleanup.lua`'s
`SWITCH_SCOPED` list). Of the nine plan moves, two needed no code and seven are
wired:

**No wiring needed (recorded honestly).** **Will-O-Wisp** is already native on
Gen 2 -- national_dex's `registry_gen2` gives it `effect = "EFFECT_BURN",
effectModeled = true`, and Gen 2's own EFFECT_BURN applies the burn. **Pollen
Puff**'s only effect beyond its plain 90-BP damage is an ALLY heal
(`moves.ts:13563-13586`); this engine's default format is 1-vs-1, where a target
is never an ally, so the heal has no reachable trigger -- the same structural
no-op class as Flame Burst's ally splash in phase 19.

**PP drain (Spite, Eerie Spell).** Both share Showdown's `Pokemon#deductPP`
(`pokemon.ts:888-900`): subtract up to N, clamp at 0, return the amount actually
removed (0 = the move fails). Spite is a repointed status handler (up to 4);
Eerie Spell is a `battle.damage_dealt` rider (up to 3), because its damage is
already native (`EFFECT_NORMAL_HIT`, `effectModeled=true`) and a repointed
record would pre-empt the damage.

**Burn-cure rider (Sparkling Aria).** A `battle.damage_dealt` rider: on a landed
hit, cure the target's burn. Showdown marks targets with a `sparklingaria`
volatile then cures a burned target in `onAfterMove` (the marker only exists so
Shield Dust / Sheer Force behave, `moves.ts:17358-17388`).

**Type addition (Forest's Curse, Trick-or-Treat).** A new `addMonType` appends
the type to the mon's live list -- Showdown's single `addedType` slot
(`pokemon.ts:2132-2138`), which `type_override_primitives.lua`'s own header
explicitly names as outside its whole-list-replacing scope. A second add
REPLACES the first (so Forest's Curse then Trick-or-Treat swaps Grass for Ghost
rather than stacking three types); the move fails when the target already has
the type; `mon.addedType` is switch-scoped; and the whole thing is gated through
the existing `canChangeType(..., { viaOpponent = true })` so Tera / Dynamax /
boss-type protections apply for free.

**Raw-stat swap (Power Trick).** Mirrors Power Shift: swaps the user's raw
`mon.stats.attack`/`.defense`, toggles off on a second use (Showdown's
`onRestart` -> `onEnd`), and reverts on switch-out and battle end via its own
`battler_switched` / `ended` listeners (deliberately NOT in `SWITCH_SCOPED`,
which could only nil a flag, never swap the stats back).

**Ground-immunity volatile (Magnet Rise).** Reuses Telekinesis's exact shape: a
mon-local `magnetRiseTurns` counter (5), decremented in a `turn_ended` listener,
with the Ground immunity resolved beside Telekinesis's own in `resolvedTypeMult`
(`return 0` while set and Gravity is not up). Recast refreshes; hard-cast fails
under ingrain / smackdown / Gravity.

See `combat/MISSING_EFFECTS_PLAN.md` phase 21.

## Field/side protection & delayed moves (Phase 22)

Round 91 (plan phase 22) ships `combat/modern_side_protection.lua`, booted right
after `modern_status_moves` (so its `Battle.useMove` wrap is the outermost of
the combat blockers), plus the new exported `armStallChain` in
`combat/modern_combat_protect.lua`. Ten of the plan's eleven moves are wired;
**HAIL is deliberately deferred** per the standing instruction recorded in
`combat/modern_weather.lua`'s header (Snow/Snowscape is Gen 9's replacement and
the only Ice weather this mod builds).

**Safeguard** was already fully native (`gen2/Battle.lua`'s `EFFECT_SAFEGUARD`
plus `Battle:safeguarded` and the `applyStatus` / `applyConfusion` gates);
national_dex simply shadowed the move at `EFFECT_NORMAL_HIT`. The new
`GALAR_SAFEGUARD_EFFECT` forwards to that native handler (with a direct fallback
that still sets `screens[side].safeguard`), and Court Change / Defog / Brick
Break keep reading the same field.

**The four guards** (Wide / Quick / Crafty Shield / Mat Block) are per-SIDE
`battle.g9Guards` flags created lazily and cleared at `battle.turn_ended`
(Showdown's duration-1 side conditions). Wide Guard blocks an
`all-other-pokemon` / `all-opponents` move carrying the `protect` flag; Quick
Guard blocks an effective priority > 0.1 (its Showdown comment explicitly counts
Prankster/Gale Wings, so the live `Battle:movePriority` is the right read);
Crafty Shield blocks any non-self status move with NO bypass check; Mat Block
blocks a non-status protect-flagged move and fails when `__g9MoveActions > 1`
(checked inside its `run`, after native `useMove` incremented the count --
literally Showdown's `activeMoveActions > 1`). Wide/Quick Guard arm the shared
Protect stall chain via `armStallChain`. A blocked move is nullified through the
same `moveEffectRecordFor` substitution seam Protect / the action-order fail gate
use, so PP is spent and "X used Y!" is still announced. `guardBlockReason` is
exported pure so every branch is harness-testable.

**Future Sight / Doom Desire** supersede the native 4-turn volatile with one
shared 2-turn side-slot scheduler (`resolveTurn = turn + 1`; Showdown's
`endingTurn = (turn - 1) + 2`): scheduled on the TARGET's side, one slot per
side, damage rolled once with the engine's own `Damage.calc` (plain-formula
fallback), landed on whoever is standing there at `battle.turn_ended`. The one
named difference from Showdown is that the fused damage is kept rather than
recomputed against a switched-in occupant.

**Present** rolls once per use on `battle.move_used` (cached on the user) so the
`registerPowerOverride` base power (0/40/80/120) and the 20% heal tier read the
same number; the heal half is a priority-45 `battle.damage` wrap. **Grassy
Glide** gets only a `registerPriorityModifier` (+1 on Grassy Terrain while
grounded) -- its damage is already native.

See `combat/MISSING_EFFECTS_PLAN.md` phase 22.

## Recharge / self-recoil / self-drop (Phase 23)

Round 92 (plan phase 23, the final phase) ships `combat/modern_self_effects.lua`,
booted right after `modern_side_protection` (so it is the last combat blocker and
its `Battle.useMove` wrap is the outermost of the chain). All fifteen planned ids
are wired.

**Recharge** spans both generations' own native flags -- but set by this file's
own real logic, because national_dex shadows all eight recharge moves at
`EFFECT_NORMAL_HIT`, making the native `EFFECT_HYPER_BEAM` auto-set unreachable.
Gen 2 sets `volatile(mon).recharge` (consumed by `checkTurn`, `gen2/Battle.lua`
:984) from a `battle.damage_dealt` listener; Gen 1 sets `mon.mustRecharge` (read
by `BattleState.lua`:2107) from `GALAR_RECHARGE_EFFECT.afterDamage`. Both fire on
a landed hit only, and deliberately have NO KO-skip clause (current Showdown
removed it; that skip was Gen 1-only, which is why the older Eternabeam record in
`modern_movepool_damage.lua` keeps it and this one does not).

**Mind Blown / Steel Beam** lose half MAX HP once the move resolves, hit OR miss
-- so a `damage_dealt` listener cannot see it. It rides the `Battle.useMove` wrap
(Gen 2) and the record's own `onMiss`/`afterDamage` (Gen 1). Magic Guard blocks it
(a real ability-id check); Rock Head deliberately does not. **Misty Explosion**'s
`selfdestruct: "always"` faint (the user drops when the move is USED, Protect /
miss / immunity notwithstanding) rides the same wrap, reproducing
`Battle:selfdestructUser`'s status/HP/Leach-Seed cleanup because the native one is
keyed on a different effect id; Gen 1 forwards to `BattleState:selfDestruct`. Its
own 1.5x on grounded Misty Terrain is a `registerDamageModifier` entry (Misty
Terrain itself does not boost Fairy moves in current Showdown).

**Glaive Rush**'s drawback volatile lives on the USER: while held, every move
aimed AT the holder always hits (a `battle.accuracy` wrap returning true) and
deals double damage (`registerDamageModifier("glaive_rush", 90)`). It is applied
on a landed hit and cleared at the holder's own next `battle.move_used`
(Showdown's `onBeforeMovePriority: 100`); `clearVolatile` (`gen2/Battle.lua`
:1112) already wipes it on a switch, matching `noCopy`. **Baddy Bad / Glitzy
Glow** set Reflect / Light Screen on the user's side (Light Clay 5 -> 8 through
the shared `resolveFieldDuration` primitive), and **Sparkly Swirl** cures the
user's whole side, reusing `status_cure.lua`'s `cureStatusOf` over
`g9SidePartyOf` plus the active mon. Those three are Gen-2-state halves (the
`screens` table and the volatile store), so Gen 1 keeps the moves' ordinary
damage -- not a regression; their four records are empty `kind="full"` markers so
Gen 2's own damage path is untouched.

See `combat/MISSING_EFFECTS_PLAN.md` phase 23.

## Coverage audit and structural exemptions (Phase 0)

Round 81 (plan phase 0) ran a full native-coverage audit and recorded it in
`combat/NATIVE_COVERAGE.md`. It classifies all 833 national_dex moves --
163 already native (`engineMove = true`), and of the 670 the mod owns, 268
referenced by id, 191 handled by the generic field listeners, 49 plain damage
handled by the pipeline, 6 structurally impossible in singles, and **156
genuine residual gaps** now mapped to phases 13-23 of the plan.

The six impossible-in-singles moves ship in `combat/structural_exemptions.lua`,
booted by `main.lua` as `structural_exemptions`:

- ALLYSWITCH, DRAGONCHEER, FOLLOWME, HELPINGHAND, RAGEPOWDER,
  SPOTLIGHT -- each needs a second **allied** battler.

`mod.exports.structuralExemptions` (id → reason) and
`mod.exports.isStructurallyExempt(id)` are published for other subsystems and
debug sessions. The harness round 81 check asserts the registry boots, names
the six ids, and stays disjoint from the mod's move-patch log. Deliberately
NOT exempt (they include the user, so they work in singles and are wired
later): Howl, Gear Up, Magnetic Flux, and the Wide/Quick/Crafty/Mat Guard
family.

## Item-effects audit (round 93)

`combat/ITEM_EFFECTS_AUDIT.md` is the item-level counterpart to
`combat/NATIVE_COVERAGE.md`: a report on what held-item behaviour is wired,
what is missing, and what is hardcoded (and why), measured against
national_dex's `itemFlags(id)` accessor (`data/items/generated/flags.lua`,
530 keys) and Pokemon Showdown's `data/items.ts`. Key findings: `itemFlags`
exposes FACTS only (never behaviour), so it can replace the hand-written
`ITEM_FLING_POWER` table (all 26 values match `fling.basePower` exactly, one
rename `BLACKBELT_I -> BLACKBELT`) and the ball classification
(`isPokeball` covers 12 of `BALL_ITEMS`'s 13 and exposes `LIGHT_BALL` as a
misclassification), but cannot supply behaviour. The API's id namespace is
Showdown's, not the ROM's (47 of 250 ROM ids match after normalization).
Critically, `flags.lua` omits all 13 Showdown `tags:["True Past"]` items --
which are exactly this ROM's Gen-2-exclusive berries, the two bows and
Berserk Gene -- so `KNOWN_BERRIES` is genuinely unreplaceable. Genuine
behavioural gaps: LUCKY_PUNCH, STICK, SPELL_TAG, BERRY_JUICE, the two bows,
and Fling's `fling.status`/`fling.volatileStatus` secondaries. Berserk Gene is
already native. No code changed in round 93; it is the audit the item wiring
phases are planned from.

## Item-effects wiring (round 94)

The audit's phases 24-30 shipped in round 94 -- the item counterpart to the
move/missing-effects pipeline. **`combat/modern_item_facts.lua`** (new) is
the foundation: the ROM-underscore -> Showdown id bridge (`norm` + the one
`BLACKBELTI -> BLACKBELT` rename) plus nil-tolerant `itemFlags` accessors
(`itemFact`, `itemFlingFacts`, `isBerryItem`, `isPokeballItem`,
`itemSpeciesMatch`) and a `TRUE_PAST_FACTS` override table for the thirteen
items `flags.lua` cannot describe (the ten Gen-2 berries, Pink/Polkadot Bow,
Berserk Gene). It boots before `modern_items`, and
`combat/modern_type_modify_moves.lua` now reads Judgment / Multi-Attack /
Techno Blast / Natural Gift facts through it -- which fixes the real bug
where raw underscore ids never resolved. On top of that:
`combat/modern_items.lua`'s hand-written `ITEM_FLING_POWER` and `BALL_ITEMS`
tables are gone in favour of the API's `fling.basePower` / `isPokeball`
(so `LIGHT_BALL` is flingable again, and 11 items the old table missed now
have real powers); Fling now applies its item's `fling.status` /
`fling.volatileStatus` secondaries (Poison Barb poisons, King's Rock
flinches, Light Ball paralyzes); Berry Juice is wired as its own
`battle.turn_ended` residual; `combat/modern_held_items_phase2.lua` gains
Spell Tag (Ghost) and the two 1.1x bows; and `combat/modern_held_items.lua`
gains Lucky Punch / Stick (+2 crit, species-gated through the API's
`itemUser`). Phase 30 also removed the redundant dead `items/` side-effect
loads from `main.lua` and fixed `items/item_dispatch.lua`'s wrong-field
`mon.heldItem` read (the audit's "all dead" claim was corrected -- the live
special-damage Life Orb file stays). Harness round 94 = 43 checks green;
143/143 subsystems, 0 failures.

## Missing effects -- phased plan

`combat/MISSING_EFFECTS_PLAN.md` is the roadmap for every remaining unwired
move/ability/field effect, grouped into phases by shared primitive
(force-switch, stat swaps/splits, crit overrides, damage-source overrides,
action order, party recovery/sacrifice, side/field conditions, trapping,
ability-manipulation moves, ability gaps, items/terrain residue, and the
structural exemptions). Phases share the `combat/SUBEFFECTS.md` wiring
procedure and each ships with its own harness round. Phases 1, 2, 3, 4, 5, 6, 7,
8, 9, 10, 11 and 12 are shipped (`combat/modern_force_switch.lua`,
`combat/modern_stat_manipulation.lua`, `combat/modern_crit_override.lua`,
`combat/modern_damage_source.lua`, `combat/modern_action_order.lua`,
`combat/modern_party_support.lua`, `combat/modern_faint_sacrifice.lua`,
`combat/modern_side_conditions.lua`, `combat/modern_field_effects.lua`,
`combat/modern_trap_moves.lua`, phase 10's additions to
`combat/modern_ability_change_moves.lua` + `combat/modern_items.lua`,
phase 11's shared ability primitives in `combat/modern_combat.lua`, and
phase 12's Misty-confusion routing in `main.lua` + the Dynamax type-change
gate in `combat/type_override_primitives.lua`). **Phase 0** shipped in round
81: the `combat/NATIVE_COVERAGE.md` audit and `combat/structural_exemptions.lua`.
**Phase 13** shipped in round 82: `combat/modern_power_conditions.lua` (29
conditional/variable-power moves) plus the lowercase-category fix in
`combat/modern_combat.lua`. **Phase 14** shipped in round 83:
`combat/modern_type_modify_moves.lua` (12 type-/category-/power-modifying
moves). **Phase 15** shipped in round 84: 19 stat-stage boosts added to
`combat/modern_movepool_stages.lua` + `main.lua`'s `CUSTOM_EFFECT_PATCH`.
**Phase 16** shipped in round 85: `combat/modern_recovery_moves.lua` (Roost's
Flying-type drop and Aqua Ring's residual; the three plain 50% heals were
already native). **Phase 17** shipped in round 86:
`combat/modern_charge_moves.lua` (Solar Blade / Meteor Beam / Sky Drop charge,
the Ice Ball / Rollout / Echoed Voice power ladders, and the Shell Trap /
Beak Blast charge-turn reactions; Round and the Pledges are already native).
**Phase 18** shipped in round 87: `combat/modern_guard_contact.lua` (the
protect-breaking Force moves + Hyperspace Hole, Chip Away / Sacred Sword /
Darkest Lariat's ignore-defense & ignore-evasion, Moongeist Beam / Sunsteel
Strike's ignore-ability, Flying Press / Synchronoise / False Swipe's damage
rules, and the Ice Spinner / Steel Roller / Thousand Waves / Freezy Frost /
Ceaseless Edge / Stone Axe / Fell Stinger on-hit riders).
**Phase 19** shipped in round 88: `combat/modern_item_moves.lua` (Trick /
Switcheroo / Bestow / Thief / Core Enforcer / Spectral Thief / Plasma Fists,
plus Flame Burst's real-but-targetless-in-singles ally splash).
**Phase 20** shipped in round 89: `combat/modern_pivot_moves.lua` (Baton Pass /
Shed Tail / Chilly Reception pivots, Assist / Copycat / Instruct move-calling,
Sketch learning, and Lock-On / Mind Reader / Psych Up / Psycho Shift).
**Phase 21** shipped in round 90: `combat/modern_status_moves.lua` (Spite /
Eerie Spell PP drain, Sparkling Aria's burn cure, Forest's Curse /
Trick-or-Treat type addition, Power Trick's stat swap, Magnet Rise's Ground
immunity; Will-O-Wisp already native, Pollen Puff ally-only).
**Phase 22** shipped in round 91: `combat/modern_side_protection.lua`
(Safeguard re-pointed at the native handler, Wide/Quick/Crafty Shield/Mat Block
per-side guards, Future Sight / Doom Desire's shared 2-turn scheduler, Present's
roll+heal, Grassy Glide's terrain priority; Hail deliberately deferred).
**Phase 23** shipped in round 92: `combat/modern_self_effects.lua` (the eight
recharge moves, Mind Blown / Steel Beam's half-max recoil, Misty Explosion's
selfdestruct + terrain boost, Glaive Rush's drawback volatile, Baddy Bad /
Glitzy Glow's screens, Sparkly Swirl's team cure). Round 92 also fixed an
off-by-one in `combat/modern_action_order.lua`'s Fake Out gate (`> 1` -> `> 0`):
the gate runs before `battle.move_used`, so `__g9MoveActions` counts COMPLETED
actions, and Showdown's `activeMoveActions > 1` is `completed > 0` (the test
First Impression already used).
The audit's residual gaps are now fully mapped and the phases 13-23 pipeline is
**complete** -- see `combat/NATIVE_COVERAGE.md` for the counts and each phase
section in the plan for its move list. The **item-effects** phases 24-30
(round 94) live in the same plan file under "Item effects -- phased wiring"
and are summarised under "Item-effects wiring (round 94)" above.

## Ability stat-multiplier damage fix (round 96)

A long-standing hole in the Phase-4 stat-multiplier family. The generated
damage path (`combat/modern_combat.lua`'s `computeModernDamage`) read
attack/special-attack/defense/special-defense through its own local `rawStat`
(direct `.stats` reads) and never called `Battle:battleStat` or
`statMultiplierFor`, so every attack/defense-shaped ability multiplier
(Orichalcum Pulse, Huge Power/Pure Power, Guts, Marvel Scale, Solar Power,
Flare/Toxic Boost, Defeatist, Hadron Engine, ...) computed a number that was
silently discarded. Only the Speed members (Chlorophyll, Swift Swim, Surge
Surfer, ...) worked, because turn order does read `battleStat`. The real Gen-2
path (`gen2-Battle.lua:1189-1215`, DoDamage/effectiveSpeed) does use
`battleStat`; the modern replacement had bypassed it.

Fixed by applying `statMultiplierFor` inside `computeModernDamage`, matching
Showdown's ordering: ModifyAtk/ModifySpA on the category stat for the original
`user`, ModifyDef/ModifySpD on whichever defense stat is read for `target`,
abilities before held items. Two related gaps closed in the same round:

- `abilities/data/stat_multiplier.lua` gained its missing `HADRONENGINE`
  entry (Electric Terrain, Sp. Atk). Orichalcum Pulse's twin had a wired
  terrain half but its Sp. Atk sub-effect was absent from the inclusion list
  entirely, so it did nothing at all.
- `abilities/engine/stat_multiplier.lua` gained a Showdown-truth
  `FACTOR_OVERRIDE`: national_dex carries ORICHALCUMPULSE at 1.5 and
  HADRONENGINE at 1.3, but both really use 4/3 (`chainModify([5461,4096])`,
  `abilities.ts:3088-3100` / `1782-1792`).

Verified with the fengari harness: boot 143/143, 0 failures. The full
round-95 sim batteries still pass with 0 mismatches (mod-vs-Showdown
1400/1400, weather 96/96), and targeted probes confirmed Orichalcum's Attack
boost reaches damage in sun (69 vs 52 baseline) and vanishes without sun, and
Hadron Engine end-to-end (terrain set on switch-in for 5 turns; Sp. Atk 4/3
only while Electric Terrain; not grounded-gated, matching Showdown; boost
cleared when the terrain expires).

## Cleanup: retired out-of-scope and dead files (round 97)

The mod is combat-only (moves / abilities / stats / gimmicks) and no longer
carries sprite or overworld asset handling, so its two sprite-extraction tools
and the data they produced were removed, along with the dead pre-existing
`items/` scaffolding the studio's own wiring gate already flagged.

Removed:
- `assets_extraction_tools/frontBackExtraction.py`,
  `assets_extraction_tools/overworldExtraction.py`,
  `shared_overworld_sprites.csv` -- sprite/overworld asset extraction and its
  output CSV; none is Lua and nothing references any of them.
- `packed_team.txt` -- a stray packed-team sample string, unreferenced.
- The dead `items/` subtree: `items/item_effects_combat.lua`,
  `items/item_effects_dispatch.lua`,
  `items/engine/{healing_items,damage_reduction,stat_modifiers,status_triggers,utility_effects}.lua`,
  `items/data/held_item_effects.lua`. These were exactly the side-effect-only
  loads Phase 30 dropped from `main.lua`; nothing requires them transitively.
  The three LIVE `items/` files stay -- `items/item_dispatch.lua`,
  `items/engine/damage_modifiers.lua` and `items/data/items_battle.lua` are
  what `combat/damage_pipeline.lua` actually needs.

Kept deliberately: `gigantamax/gimmick_dynamax.lua` (canonical-disabled -- the
sole remaining unreachable file), and `overworld/gym_trainer_teams.lua` +
`overworld/install_gym_trainer_teams.lua` (trainer TEAM data, not sprites; both
are loaded). `mod.card` was rewritten to drop the outdated sprite/overworld
wording and its stale "175 of 934 moves" coverage figure.

Verified: the fengari harness boot stays **143/143, 0 failures**; a read-trace
(the harness file map wrapped in a Proxy) shows every remaining `.lua` is read
at boot except `gimmick_dynamax`; the round-96 action-gates probe is unchanged
green. The studio wiring gate drops from 9 reachable-orphans to 1.

## Held-item storage + post-battle restore (round 98)

Gen 1 has no held-item mechanic, so there is no place in a Gen-1 save to put an
item a player is "holding". This round adds that place, a public cross-mod API
around it, and the battle-scoped restore both generations need.

**New file: `combat/modern_held_item_api.lua`** (see the "Held-item storage API"
section above for the exported surface). It adds a single namespaced Gen-1 save
slot, `mon.g9HeldItem`, and three accessors -- `setHeldItem` / `getHeldItem` /
`clearHeldItem` -- so any other mod can craft a hold/switch/remove held-item
tool. The slot round-trips through the save untouched:
`SaveSerializer.lua:12-51` writes every table key, and `SaveData.validate`'s
`scrubKnownMon` (`SaveData.lua:2324-2400`) only rewrites the fields it knows
(dvs / statExp / level / stats / moves) without enumerating unknown keys. Gen 2
needs no new field -- its `mon.item` (`battle/gen2/Mon.lua:458`) is that save's
own slot and already persists; per the round brief, Gen 2 participation here is
restore-only.

**Post-battle restore.** This mod's own item moves delete a battler's item
outright on a landed hit (`modern_items.lua` Knock Off / Fling / Incinerate /
Bug Bite / Pluck, `modern_item_moves.lua`'s `takeItem`, the end-of-turn berry
eaters). On Gen 2 that is a real save edit, because `Battle.party IS save.party`
(`battle/gen2/Battle.lua:463`). The new file snapshots the player's party
equipment at `battle.started` (priority 1000) and, at `battle.ended` (priority
-1000 -- the last ended handler, since `mods/Events.lua:11-22` sorts listeners
descending by priority), gives back every recorded item that is now missing. An
item that survived is left alone, and a mid-battle gain (Bestow / Trick /
Recycle) is never clobbered. Player scope is `battle.party` on Gen 2 and the real
save party (`battle.game.save.party`) plus the scoped `battle.playerParty`
(`BattleState.lua:765`) and the active battler on Gen 1, deduped. Enemy rosters
are out of scope.

Wired in `main.lua`: `boot("modern_held_item_api", ...)` immediately after the
`modern_items` boot. Verified with the fengari harness -- boot **144/144, 0
failures** -- plus a dedicated probe (`scratch/sim/probe_helditem.lua`): get/
set/clear round-trips, the raw `g9HeldItem` field, the battler-wrapper form,
non-mon / non-string rejection, Gen-1 accessors leaving Gen-2 `mon.item`
untouched, gen-aware `effectiveHeldItemOf`, and both restore paths (Gen 2:
flung item handed back, surviving item untouched, mid-battle gain kept; Gen 1:
cleared item restored, gain kept; no-snapshot no-op = 0). The round-95 sim
batteries still pass with 0 mismatches.

## Gen-1 held-item combat wiring (round 99)

Round 98 gave Gen 1 a held-item save slot (`mon.g9HeldItem`) and a get/set/clear
API, but nothing in the Gen-1 battle path ever READ that slot for a combat
effect: every held-item mechanic was either Gen-2-gated (`if not ctx.gen2 ...`)
or relied on a Gen-2-only choke point (`held_item.trigger`,
`Battle2:MOVE_EFFECTS`, `Battle:*` monkeypatches). A Gen-1 mon could hold an item
and it did exactly nothing. Round 99 wires it up.

**The gen-aware item read/write pair.** `combat/modern_items.lua` now exports
`itemOf(who, gen2)` (already gen-aware from round 98), a matching
`setItemOf(who, item, gen2)` writer, `itemLabel(battle, itemId)`, and
`heldAbilityIdOf(who)`. `setItemOf` writes Gen 2's native `mon.item` or Gen 1's
`g9HeldItem` save slot (via `HELD_ITEM_SAVED_FIELD`, with an inlined fallback);
`itemLabel` returns the engine's item def name on Gen 2 (`battle:itemDef`) and
the raw id on Gen 1 (whose `BattleState` has none); `heldAbilityIdOf` unwraps a
Gen-1 battler wrapper before calling `abilityIdOf`, because abilities live on the
raw mon (`stats/engine_modern_stats.lua` writes `mon.ability`), not the wrapper.

**One real pre-existing bug fixed at the source.** `computeModernDamage`
(`modern_combat.lua`) passed the engine's own `battle.damage` ctx to
`applyHeldItemStatMultiplier` without a `gen2` field, so the entire stat-
multiplier family (Choice Band/Specs/Scarf, Assault Vest, Eviolite, Light Ball,
Thick Club, Deep Sea Tooth/Scale, Metal Powder) was inert on BOTH generations.
The wrap now publishes `ctx.gen2`. The dual-gen gates on the damage/stat/crit/
accuracy families were lifted in `modern_held_items.lua` and
`modern_held_items_phase2.lua` (they only ever flowed through chains both
engines already drive); the Gen-2-only tail that stays Gen-2-only is the
`Battle2` battleStat speed patch, Light Clay's screen patches, the Choice lock,
Assault Vest's menu ban, and Lagging Tail's `registerPriorityModifier`.

**New file: `combat/modern_gen1_held_items.lua`** (booted right after
`modern_held_items_phase2`). It owns the mechanics Gen 1 has no native analogue
for: (1) item Speed (Choice Scarf / Quick Powder / Iron Ball) and fractional
priority (Quick Claw / Lagging Tail / Full Incense), folded in by replacing
`src/battle/TurnOrder`'s own `effectiveSpeed`/`firstMover` -- the one seam every
Gen-1 caller reaches; (2) Focus Sash / Focus Band survive-at-1 clamps on the
final `battle.damage` number (priority 501, above the 500 pipeline wrap);
(3) King's Rock's 10% flinch off `battle.damage_dealt`; (4) Leftovers/Berry
Juice residuals off `battle.turn_ended`. Header flags the deliberate deferrals:
the Choice move-lock / Assault Vest menu ban, Light Clay against the *native*
Gen-1 screens (permanent, no clock -- but see the field-duration paragraph
below), and berry auto-eat (Gen 1 has no berry taxonomy).

**Item moves now act on Gen 1.** In `combat/modern_items.lua` every remover
(Fling consume, Knock Off, Covet, Incinerate, Bug Bite/Pluck, Corrosive Gas's
`run()`, Recycle, Belch's fail gate) reads/writes through the gen-aware pair and
drops the `isGen2Battle` gate; Sticky Hold / Klutz checks unwrap the battler.
Bug Bite/Pluck also flags the eater's `ggdConsumedBerryThisBattle` on both
generations (Showdown's own `source.ateBerry = true`). In
`combat/modern_item_moves.lua` the local keepers (`itemIdOf`/`setItemOf`/
`takeItem`) route through the shared pair, the `if not n.gen2 then fail` gates
are gone, and the riders (Thief, Core Enforcer, Plasma Fists, Flame Burst) run
on both generations -- Core Enforcer unwraps to the raw mon that actually
carries `ability`. The Fling flinch rider follows the engine's own dual
convention (`battle:volatile` on Gen 2, the battler's own `flinched` field on
Gen 1) rather than testing for the volatile method's mere presence.

**Field-effect duration items now work on Gen 1.** `combat/field_duration.lua`'s
shared `resolveFieldDuration` reads the setter's item through a new `setterItem`
that checks the native `.item` first (Gen 2 byte-identical to before) and then
falls back to the Gen-1 saved slot via the API's `effectiveHeldItemOf`;
`combat/modern_weather.lua` now passes its setter on both generations instead of
nil-gating Gen 1. A Gen-1 Damp Rock / Heat Rock / Smooth Rock / Icy Rock really
does stretch SET weather 5 -> 8, and Terrain Extender stretches terrain the same
way; Light Clay extends the mod's own numeric-duration screens (Aurora Veil and
the LGPE Baddy Bad / Glitzy Glow screens) on Gen 1, while the native Gen-1
Reflect/Light Screen stay the permanent per-mon booleans they always were.

Verified with the fengari harness -- boot **145/145, 0 failures** -- plus two
probes: `scratch/sim/probe_gen1items.lua` (damage/stat/turn-order/Sash/Band/
King's Rock/Leftovers/Berry Juice and the field-duration items, both
generations) and
`scratch/sim/probe_gen1itemmoves.lua` (Knock Off / Covet / Thief / Fling /
Incinerate / Bug Bite / Corrosive Gas / Trick / Bestow / Recycle, the Mail and
Sticky Hold exemptions, the Fling/Incinerate/Belch pre-damage fail gates, and
Gen-2 regression on the same removals).

## Engine -> scene move validity (round 100)

Round 100 answers the user's "comms between engine and scene" brief: the scene
needs to know *before* a move is chosen whether the engine would let it be
chosen, so it can refuse the pick and tell the player why instead of watching
the move spend its PP and fizzle.

**New file: `combat/move_usability.lua`** (see the "Move usability API" section
above for the exported surface). It boots in `main.lua` immediately after
`modern_combat` -- early enough that the condition owners register their gates
before any battle -- and holds the three built-in rules the engine already
enforced at resolution:

- **Choice lock** (`combat/modern_held_items_phase2.lua`'s
  `mon.ggdChoiceLockedMove`). The scene asked for "only the first move selected
  can be used; switch in re-enables swapping moves". `choiceGate` reads the same
  field; the new `battle.move_used` listener SETS it on Gen 1 (and is idempotent
  on Gen 2, where the existing `Battle2:useMove` patch already does), skipping a
  called move (Metronome/Sleep Talk) and Magic Room, and the
  `battle.battler_switched` listener CLEARS it on both generations. A lock whose
  item is gone, or whose locked move has hit 0 PP, is dropped the way Showdown
  drops it.
- **Item move-type ban** via the exported `itemMoveBanned`: the user's example,
  "items that disable the use of status moves but buff a stat", is Assault Vest.
  One `ITEM_MOVE_BANS` row (`categories = {status=true}`, `exceptions =
  {MEFIRST=true}`) is the whole wiring, and the Status test is the exact one
  `modern_held_items_phase2.lua` already used, so the query and the enforcement
  cannot disagree. That file's own `Battle2:usableMoves` filter now delegates
  here (lazily, with its original fallback before this file boots).
- **Taunt / Torment** (Gen 2), read off the same volatiles
  `combat/modern_status_effects.lua` enforces.

**Condition gates.** The three moves whose own module already owns a
resolution-time fail gate register the matching selection-time answer through
`registerMoveUsabilityGate`, mirroring the existing `registerFailGate` pattern
so a move's rule has one owner:

- `combat/modern_action_order.lua` -- `FAKEOUT` ("only works on the user's
  first turn out"), off the shared `(attacker.__g9MoveActions or 0) > 0` test.
- `combat/modern_side_protection.lua` -- `FIRSTIMPRESSION`, same first-turn-out
  test (this file also gained the `require("src.core.Strings")` it was missing).
- `combat/modern_faint_sacrifice.lua` -- `LASTRESORT` ("only after the user has
  used all its other moves").

**Enforcement backstop.** `combat/turn_order.lua`'s `failAction` gained an
optional `failText`, and `resolveTurnActions` now asks `moveUsability` for each
queued action BEFORE acting: a `choice`- or `banned`-flagged block fails the
action with the engine's own message instead of running it. The condition gates
are deliberately NOT re-checked there -- their modules already refuse at
resolution with their own text; the backstop exists only for the two menu-level
locks a caller could bypass. A caller that ignores the query still gets the old
resolution-time behaviour.

Verified with the fengari harness -- boot **146/146, 0 failures** -- plus a
dedicated probe (`scratch/sim/probe_moveusability.lua`): the Choice lock
(set/free-on-0-PP/free-on-switch/free-on-item-loss/Magic-Room-suppressed/
not-set-by-a-called-move), Assault Vest's Status ban with the Me First exception
and other items unaffected, the Fake Out / First Impression / Last Resort
condition gates, Taunt/Torment, and the Gen-1 accessor path. The round-95..99
sim batteries still pass with 0 mismatches.

**Reaches Gen 1 -- and actually fires there (verified).** This query only reaches
a Gen 1 battle if the engine loads on Red/Blue/Yellow AND the three condition
owners actually boot. Two separate faults were found and fixed:

1. `manifest.json` declared `games: ["gen2"]`, so the loader's generation gate
   skipped the whole engine on Gen 1 and `mod:find("g9-battle-engine")`
   returned nil -- the scene's `Combat.usableMoves` annotation silently did
   nothing. The manifest is now `["gen1", "gen2"]` (see "Games" above).
2. With the engine loading, the round-100 gate owners were still dying: the
   sandbox refuses every `src.*.gen2.*` require on a Gen 1 game
   (`src/mods/Loader.lua` `crossGenerationDenial`), and three files required a
   Gen-2 class unguarded, so their pcall-guarded `boot()` marked them failed --
   and the registered gates died with them. Fixed with the same
   `pcall(require)` guard `modern_combat.lua` already uses:
   - `combat/turn_order.lua` (`src.battle.gen2.Damage` + `Battle`) -- the root:
     `modern_action_order` asserts its phase-5 exports, so turn_order failing
     cascaded through `modern_action_order` (FAKEOUT), `modern_side_protection`
     (FIRSTIMPRESSION) and `modern_faint_sacrifice` (LASTRESORT). On Gen 1 the
     Gen-2-only `Battle:movePriority` monkeypatch and the `Damage.applyStage` /
     `Battle.statusPenaltyFor` speed composition are now skipped (its own native
     `movePriority` / effective-speed stay authoritative); everything
     turn_order OWNS for the gates still installs.
   - `combat/modern_action_order.lua` and `combat/modern_side_protection.lua`
     (`src.battle.gen2.Battle`), each guarding its `Battle:useMove` wrap -- a
     Gen-1 move path (`BattleState:performMove`) that wrap never covered.

Verified with a Gen-1 boot mode in the fengari harness (`opts.gen === 1`, which
makes `engineRequire` throw on `src.*.gen2.*` and `GameVersion.generation()`
report 1): the engine boots **87/146** on Gen 1 (the remaining guarded failures
are the Gen-2-only simulation modules, which Gen-1 resolution never calls), the
three gates are registered, and a genuine Gen-1 `battle.move_used` emit whose
`user` is a native battler wrapper (`.mon`) blocks Fake Out and First Impression
after the user's first action and keeps Last Resort blocked until every other
move has been used -- on top of the Choice lock and Assault Vest ban. Gen 2 is
unchanged: boot **146/146, 0 failures**. The only deliberate Gen-2-only
restriction remains Taunt/Torment (`volatileGate`), whose volatiles Gen 1 does
not model here.

### Round-100 follow-ups: cross-battle scoping + the scene's switch event (2.7.2)

Two more real-play faults, both found by driving the *real* scene module against
the *real* engine rather than a hand-fired event:

3. **Cross-battle state leak (engine).** The scene's Gen-1 backend builds a real
   `BattleState` by hand (`native.lua` `N.buildBattle`) and never runs the
   native constructor's `battle.started`, so every per-mon, per-battle field the
   gates read -- `__g9MoveActions` (Fake Out / First Impression), the per-slot
   `__g9Used` marks (Last Resort), `ggdChoiceLockedMove`, `__g9LostFocus` --
   survived from one battle into the next on a party mon that persists. In play
   a Fake Out was wrongly refused on the **first** turn of a later battle, and a
   Choice lock / Last Resort flag leaked the same way. `moveUsability` now scopes
   that state to the battle itself: the first time the query sees a mon in a NEW
   battle (`mon.__g9UsabilityBattle ~= battle`) it clears exactly the fields the
   query reads. One table-identity compare per call, and it can never wipe state
   mid-battle (within a battle the marker already equals `battle`). This is
   deliberately done on the QUERY side rather than depending on a scene emitting
   an event it may never emit.

4. **A scene-driven switch announced nothing (scene side).** The engine clears
   the Choice lock and resets the first-turn-out counter from
   `battle.battler_switched` -- the event the NATIVE battle raises on every
   switch. The scene owns its own switch (`battle_screen.lua` `advanceResolving`'s
   `switchQueue`, and `advanceEnemyReplacement`) and never raised it, so the
   user's "switch in re-enables swapping moves" did not hold: a Choice-locked mon
   stayed locked after switching out, and a freshly switched-in mon was still
   refused Fake Out. Both switch paths now `Runtime.emit`
   `battle.battler_switched` with `previous` = the mon leaving and `battler` =
   the mon arriving, on the same shared bus the screen already raises
   `battle.turn_started` on.

Verified with `scratch/sim/probe_scene_integration.lua`, which loads the REAL
`g9-Battle-Scene/combat.lua` and drives `Combat.allMoves` with a realistic Gen-1
battler, raising every event through `Runtime.emit` (the native call) so the
shared-bus wiring is exercised, not just the listener body. All of A-J green:
the condition gates, the Choice lock within a battle, the Assault Vest ban, the
cross-battle resets (F/G/H), and the switch-in reset of both the Choice lock and
the Fake Out counter (I/J). Gen-1 boot stays 87/146 (all round-100 owners load);
Gen-2 boot stays 146/146, 0 failures.

## Gen-1 turn order is engine-owned (round 101)

The scene's Gen-1 backend has always probed for
`mod.exports.resolveTurnActionsForGen1` and called it first, but the engine only
OWED Gen 2 a turn resolver -- on Red/Blue/Yellow, Gen 1 fell back to the scene's
own native ordering, so any priority the engine computes (national_dex's move
priority, a `registerPriorityModifier` ability, a Gen-1 held-item bracket) was
ignored there. Round 101 makes the engine the turn-order owner on BOTH
generations.

`combat/turn_order.lua` now exports **`resolveTurnActionsForGen1(battle,
actingBattlers)`** -- the exact name the scene looks for. Priority is built by
`priorityWithModifiers`, the SAME local the Gen-2 `Battle:movePriority`
monkeypatch delegates to (`mod.exports.priorityWithModifiers`): national_dex's
`moveById(moveId).priority` first, then every `registerPriorityModifier` entry
(Prankster, Gale Wings, Triage, Stall, Quick Draw, Mycelium Might, ...) with the
raw MON passed to each modifier, and finally the Gen-1 item fractional bracket
(`gen1ItemFractionalPriority` -- Quick Claw +0.1, Lagging Tail / Full Incense
-0.1) owned by `combat/modern_gen1_held_items.lua`. The actions sort through the
shared `computeTurnOrder` with `trickRoom = battle.trickRoomActive == true` and a
tie roller drawn from `battle.rng`, then resolve through the native
`battle:useMove(mon, target, move)` (raw mon, as modifiers expect) with a
live-opponent fallback for a target that fainted mid-turn. The Gen-2
`Battle:movePriority` and this Gen-1 resolver are therefore provably ONE
algorithm, not two that can drift.

**A real Gen-1 boot bug fixed alongside it.** `combat/modern_items.lua` required
`src.battle.gen2.Battle` unguarded, so on a Gen 1 game the file tripped its own
pcall guard -- and took `modern_held_item_api`, `modern_gen1_held_items` and the
whole Gen-1 held-item path down with it. That meant the very module that supplies
the Gen-1 item priority bracket never loaded. The require is now `pcall`-guarded
(`okBattle2 and Battle2 or nil`) and its single use (`Battle2.HELD_STATUS_CURES`)
is nil-checked. Gen-1 boot rises **87/146 -> 92/146** (the remaining guarded
failures are the Gen-2-only simulation modules Gen-1 resolution never calls).

Verified with a dedicated fengari probe (`scratch/sim/probe_gen1_turnorder.lua`)
driving the real `resolveTurnActionsForGen1` on a fake Gen-1 battle: national_dex
priority (a slow PROTECT +4 moves before a fast TACKLE), the legacy record
fallback, a custom `registerPriorityModifier`, real PRANKSTER (status +1, damaging
0), real GALE WINGS (+1 Flying), real Choice Scarf (x1.5 Speed), real Quick Claw
(+0.1 proc and no-proc), real Lagging Tail (-0.1), Trick Room reversal, raw
`(mon, target, moveId)` delivery, and fainted-target redirect / fainted-actor
skip -- all pass on Gen 1. Gen 2 is unregressed: boot **146/146, 0 failures**,
and `Battle:movePriority` still reads PROTECT 4 / QUICK_ATTACK 1 / COUNTER -5 /
legacy effect fallback 3 / PRANKSTER status 1 (damaging 0). The scene needs no
change -- its `native.lua` already calls the hook.

## Heal Block is a real move now, and the boss `healblock` flag works (round 102)

Heal Block (the Gen-5+ move that stops the target from restoring HP for 5 turns)
previously did not exist in the engine, and the `healblock` boss-fight flag was
accepted and stored but wired to nothing. Worse, the one place the flag was
consulted flipped the semantics: it turned the blocked heal into DAMAGE on the
healing side instead of refusing the heal. Round 102 makes Heal Block a real
move and makes the flag do the correct thing.

**One gate, one write path.** `combat/heal_block.lua` owns the whole mechanic:

- `healBlocked(battle, who)` -- the predicate. It reads BOTH the volatile
  `who.heal_block` counter (set by the move) and the boss-fight `healblock` flag
  (which blocks the PLAYER's side for the whole fight). It accepts a battler
  wrapper OR a raw mon, so any call site can use it.
- `g9TryHeal(battle, who, amount)` -- the single write path for HP recovery. It
  returns the HP ACTUALLY restored, which is `0` when blocked. Callers that
  route through it never have to know the rule.
- `notifyHealBlocked(battle, who)` -- emits the refusal message once per
  mon-per-turn (so a multi-hit drain does not spam it).
- `healBlockMoveRefused(battle, mon, moveId)` -- moveUsability gate; uses
  national_dex's `moveById(moveId).flags.heal` so any move tagged as a heal move
  is refused while blocked.

The move itself is registered as `GALAR_HEALBLOCK_EFFECT` in
`combat/modern_status_volatiles.lua`, and it also sets the 5-turn volatile that
`healBlocked` reads. `combat/move_usability.lua` gained a `healBlockGate` (it
passes the ORIGINAL battler -- wrapper or raw mon -- through, which is what keeps
the gate correct at every call site), and `combat/turn_order.lua` has a
last-resort backstop so a heal cannot sneak through resolution.

**Every heal site routes through the gate.** All of these now call
`mod.exports.g9TryHeal` instead of touching HP directly:
`combat/modern_movepool_damage.lua`, `combat/modern_party_support.lua`,
`combat/modern_recovery_moves.lua`, `combat/modern_side_protection.lua`,
`combat/modern_stat_manipulation.lua`, `combat/modern_gen1_held_items.lua`,
`combat/modern_held_items_phase2.lua`, `combat/modern_items.lua`,
`combat/modern_terrain.lua`, `gigantamax/max_move_subeffects.lua`,
`abilities/engine/heal.lua`, `abilities/engine/type_immunity.lua`, and
`abilities/engine/damage_immunity.lua`. Native entry points are hijacked too:
Gen 1 wraps `MoveEffects.RECORDS.HEAL_EFFECT.run` (blocked heals return the
refusal message and do NOT put the mon to sleep the way Rest would), and Gen 2
wraps `Battle:heal`, `MOVE_EFFECT_RECORDS.EFFECT_HEAL` and
`Battle.MOVE_EFFECTS.EFFECT_HEAL`.

**The flag fix.** `combat/boss_fight.lua` owns the `healblock` flag (documented
in its `BOSS_FIGHT_FLAG_NAMES`); it marks the player's side, and
`healBlocked` returns true there. Crucially the block REFUSES the recovery -- it
does NOT deal damage (the `antiDrain` flag owns the self-harm shape). The state
resets correctly at battle end. The flag is player-side-only for boss fights, but
the move works for either side in an ordinary battle.

Verified with two dedicated fengari probes (`scratch/sim/probe_healblock.lua` on
Gen 1, `scratch/sim/probe_healblock_gen2.lua` on Gen 2) plus the full Gen-1 and
Gen-2 batteries: Gen-1 probe 0 failures, Gen-2 probe 0 failures, Gen-1 full sim
0 failures, Gen-2 full sim 147/147 booted, 0 failures -- and every damage /
type-chart number byte-identical to the round-100 baseline, so nothing regressed.

## Gen-1 full combat audit (round 102)

The whole engine was booted on a Gen 1 game and every ability / effect / item /
move / terrain / weather / contact / immunity / turn-order subsystem was
audited, with representative behaviour checks. Headline: **97 of 147 subsystems
boot on Gen 1; 50 do not -- and every single one of the 50 is a cross-generation
dependency, not a bug.** 40 fail directly on an unguarded `src.battle.gen2.*` /
`src.world.gen2.*` / `src.core.Game2` require, and 10 more fail as a cascade
(they stock-check a module that itself failed). Zero failures are "unknown".

What that means in practice, live on Gen 1:

- **Live**: the dual-gen core works unchanged. Modern damage pipeline
  (`combat/modern_combat.lua`, damage_calculator/pipeline), status
  (`modern_status_effects`, turn-loss volatiles), the Gen-1 held-item path
  (`modern_gen1_held_items`, `modern_held_item_api`), recovery moves, party
  support, side protection, stat manipulation, items (`modern_items`,
  `modern_held_items_phase2`), the immunity layer (damage_immunity,
  type_immunity, absorb, damage_multiplier abilities; status_immunity is
  Gen-2-only), contact (`contact_retaliation`, `long_reach`), and turn order
  (`turn_order` -> `resolveTurnActionsForGen1`, `modern_action_order`,
  `turn_residuals`). Gen-1 modern move-effect registrations total **264** live
  records. The new heal-block move + flag are live on Gen 1.
- **Gen-2-only on Gen 1** (these are the ones that need a Gen-2 game, by design):
  terrain, hazards (`modern_hazards`), field effects / field duration,
  type-override primitives, trapping, pivots / switch moves
  (`modern_switch_moves`), Trick/Magic/Wonder Room, tera and dynamax/gmax, gen2
  wide scene, and the ability engines that only exist to interoperate with Gen-2
  battle internals. `combat/modern_status_volatiles.lua` IS live on Gen 1 (it
  registers the Heal Block move record) even though its own Gen-2 useMove wrap
  is pcall-guarded.
- **Exports**: `registerTrainer` / `hasRegisteredTrainer` are absent on Gen 1
  because `trainers/custom_trainer_registry.lua` is Gen-2-only; the rest of the
  public API is present.
- **Boss flags**: all 13 are live on Gen 1 -- `sun`, `mistyTerrain`, `statsDrop`,
  `type`, `ability`, `hardStatus`, `softStatus`, `antiDrain`, `dimensionLock`,
  `trickRoom`, `magicRoom`, `wonderRoom`, and now `healblock` (was a no-op).

Batteries: `scratch/sim/sim_gen1_full.lua` (Gen-1 full audit + 19 behaviour
probes, 0 failures) and the Gen-2 `run-sim.js` driver (147/147 booted, 0
failures).

## Seamless Gen-1 / Gen-2 combat: the cross-generation barrier is gone (round 103)

Round 102 documented that 50 Gen-1 subsystems failed to boot -- every one of
them a cross-generation dependency, 40 on an unguarded
`require("src.battle.gen2.*")` / `src.world.gen2.*` / `src.ui.gen2.*` /
`src.core.Game2` and 10 as a dependency cascade. That meant combat genuinely
differed between generations: on a Gen 1 game 50 subsystems were simply absent,
even though almost all of them already carry a real, written Gen-1 path. Round
103 removes the barrier so the same combat code runs on both generations.

**Every cross-generation require is now pcall-guarded.** Across 42 files the
load-time `local X = require("src.battle.gen2.*")` became
`local okX, X = pcall(require, "..."); X = okX and X or nil`, and the
Gen-2-only patch block(s) it gated were wrapped in `if X then ... end`. The
dual-generation code in those files -- the Gen-1 branch that was already
written but never reached because the file died at its top-level require -- now
installs normally on Gen 1. The one-line `Effects.CHARGE.*` patches became
`do local ok,E = pcall(require,"src.battle.gen2.Effects"); if ok and E then
E.CHARGE.* = {...} end end`. Files touched: `abilities/engine/{aroma_veil,
dancer,form_combat_effects,good_as_gold,inflict_status,magic_bounce,
onmove_type_change,pressure,prevent_misc,prevent_priority_fail,priority_change,
stage_change_transform,stat_multiplier,status_immunity,switchin_primal_weather,
trap_abilities}.lua`, `combat/{gym_badge_buff,interaction_memory,
legacy_move_takeover,modern_charge_moves,modern_combat_protect,
modern_field_effects,modern_guard_contact,modern_hazards,
modern_held_items_phase2,modern_move_flags,modern_movepool_damage,
modern_pivot_moves,modern_self_effects,modern_side_conditions,
modern_status_turn_loss,modern_switch_moves,modern_terrain,modern_trap_moves,
modern_type_change_moves,modern_weather,move_targeting,switch_primitives,
switch_vanilla_bridge,trick_room,type_override_primitives}.lua`,
`trainers/custom_trainer_registry.lua`.

**Two subsystems stay Gen-2-only by design, and now skip gracefully.** Their
whole purpose is the Gen-2 scene/trainer layer, so on Gen 1 they log one line
and return early instead of erroring: `combat/switch_vanilla_bridge.lua` (the
Gen-2 scene switch event) and `trainers/custom_trainer_registry.lua` (the
`src.world.gen2.Trainers` registry). `custom_trainer_registry` additionally
publishes inert stubs for its public exports (`registerTrainer`,
`unregisterTrainer`, `getRegisteredTrainer`, `hasRegisteredTrainer`,
`setTrainerMaxHpMultiplier`) so a caller mod that calls them unconditionally on
Gen 1 gets a harmless `false`/`nil` rather than a nil-export crash.

**Result.** Gen-1 boot went from **97/147 (50 failed)** to **147/147 (0
failed)**. `status_immunity.lua` is no longer Gen-2-only -- it loads and its
dual-gen code installs on Gen 1 -- so the round-102 audit's "status_immunity is
Gen-2-only" line and its "registerTrainer absent" line are both superseded:
every public export is present on Gen 1, and the Gen-1 full-battery assertion
was updated (`status_immunity_gen2_only` -> `status_immunity_loads_gen1`).

**Gen-2 is byte-identical.** The Gen-2 full sim against the round-102 baseline
is unchanged: 147/147 booted, 0 failures, `mod_vs_showdown` 1400/1400,
type-chart applied mismatch 768 (the pre-existing FIGHTING-vs-FLYING/ROCK
rounding case, delta 1), identical `engine_vs_showdown` / `engine_vs_cart`
numbers, and 0 failures in every sub-suite. On Gen 2 `pcall(require, ...)`
succeeds and every `if X then` is true, so the guards are behaviour-neutral
there.

**Verified** with: Gen-1 full battery (`scratch/sim/round103-gen1-fullsim.json`,
147/147 booted, 0 check failures), Gen-1 turn-order probe
(`scratch/sim/round103-gen1-turnorder.json`, `failed_count` 0, resolver +
national_dex priority + item Speed/fractional-priority + Prankster/Gale
Wings/Scarf/Quick Claw/Lagging Tail/Trick Room all green), heal-block probes on
both generations (`round103-healblock-gen1.json`, `round103-healblock-gen2.json`,
0 failures each), and the Gen-2 regression check
(`scratch/sim/round103-gen2-verify.json`) against the round-102 baseline.
Manifest bumped to **2.9.0**.

## Removal cleanup: five option-gated extras deleted (round 104)

The user asked to remove and clean up five features. Each one was a Mod Manager
option that gated its own subsystem, and each had been folded in as a separate
optional add-on rather than core combat, so the whole feature -- option, boot
entry, module and dangling references -- could be removed cleanly:

- **Battle Forms Tera dev** (`bf_tera_dev`). `gigantamax/tera_state.lua`'s
  `ensureBattleFormsGate` used to expose an escape hatch that let battle_forms'
  Tera read be forced to a specific type. The gate now routes to `"auto"`
  unconditionally, so Tera type selection is always battle_forms' own unless a
  real Dynamax/Tera state says otherwise.
- **Gen 2 move-type readout** (`gen2_wide_layout`). The Gen-2 wide battle
  layout, whose only extra was the move-type readout, is gone; deleted
  `combat/gen2_wide_scene.lua`.
- **Custom menu screens** (`custom_menu_scene`). Deleted both scene
  replacements this single option gated: `ui/custom_menu_takeover.lua` and
  `ui/custom_party_scene.lua`.
- **Gigantamax size** (`gigantamax_size`) and **skip Gigantamax grow/shrink**
  (`gigantamax_skip_animation`). Both were Gen-1 draw-time behaviour driven by
  the same code path in `gigantamax/dynamax_battle.lua`, so the Gen-1 size-up
  (the `BattleState:drawBattlerPic` wrap that drew the larger sprite and eased
  the grow/shrink tween) was removed wholesale. The file keeps its real job:
  driving Dynamax Level and setting the `__g9Dynamaxed` marker.

**Orphaned shared theme also removed.** `ui/ui_theme.lua` was a drawing helper
consumed only by the two deleted custom screens, so it became dead code once
`custom_menu_scene` was gone; it and its boot entry were removed too.

**`options.lua` now exposes three options.** Only `show_hp_lost_messages`,
`gym_badge_buff` and `dev_tools` remain. `main.lua` drops the four boot
entries (`custom_party_scene`, `custom_menu_takeover`, `gen2_wide_scene`,
`ui_theme`), and `combat/modern_tera.lua`, `combat/battle_prompt.lua`,
`stats/engine_modern_stats.lua` and `stats/ev_yield_on_faint.lua` had their
dangling comment references to the removed files/options cleaned up.

**`gigantamax/gimmick_dynamax.lua` is untouched.** It is canonical-disabled
(never booted, unreachable), so it keeps its own size-up code and its now-stale
reads of the deleted options; it has no runtime effect and was deliberately left
alone rather than risk destabilising a large canonical file for zero gain. It
remains the one validator "unreachable" info.

**Verified** with the full batteries on both generations:
`scratch/sim/round104-gen1-fullsim.json` and
`scratch/sim/round104-gen2-verify.json` -- file count **218**, **143/143
subsystems booted, 0 failures**, and 0 failures in every Gen-2 sub-suite
(`probability/order/formats/turnstack/damagestack/genpaths/audit`). Boot count
fell from 147 to 143 along with the four removed subsystems + theme, exactly as
expected. Manifest bumped **2.9.0 -> 3.0.0** (a breaking removal of public
options and modules).

## Damage Numbers + Adv.Stats rename (round 105)

User brief: rename `show_hp_lost_messages` -> **Damage Numbers** and make it real
(red `-N` for damage taken, green `+N` for HP recovered), print those values in the
battle scene under each Pokemon's HP bar at HP-bar font size, fading out over one
second; rename `dev_tools` -> **Adv.Stats** (party submenu entry + options setting
name); both on Gen 1 and Gen 2; on Gen 1 the Adv.Stats window is 20% larger in both
axes.

**Options (`options.lua`).** The first row is now `key = "damage_numbers"`,
`label = "DAMAGE NUMBERS"`, default `false`, with a real description. The third row
is `key = "adv_stats"`, `label = "ADV.STATS"`. The old keys are gone from the
option table (only historical comments mention them).

**Engine -> scene accessor (`main.lua`).** A new export
`mod.exports.damageNumbersEnabled()` returns
`mod.options:get("damage_numbers") == "true"`. The scene calls it through
`self.g9dex.exports` so the toggle is read live.

**Damage numbers (scene, `g9-Battle-Scene/battle_screen.lua`).** No new
engine->scene *amount* plumbing was needed: the scene already receives a full
HP-vector snapshot on every event (`event.g9SceneHp`, stamped by
`Screen:installEventProbe`) and `Screen:armHpAnim` compares each snapshot against
`self.shownHp` for the bar chase -- that signed delta is the damage/heal value.
`armHpAnim` now calls `self:spawnDmgNumber(mon, hp - self.shownHp[mon])`; new
`spawnDmgNumber` / `stepDmgNumbers(dt)` / `drawDmgNumbers()` methods render a
`-N` (red `{0.85,0.13,0.13}`) or `+N` (green `{0.10,0.65,0.18}`) string under the
bar, using the same `drawScaledText` scale as the HP numeric readout, with alpha
`max(0, 1 - t/1.0)`. The HUD mark table now also stores `left`, `gs` and
`visible` so each number is anchored to its own bar. Gated on
`damageNumbersEnabled()`.

**Adv.Stats (`stats/dev_stats_screen.lua`).** Gated on `adv_stats`, the party
submenu entry is now `{id="ADVSTATS", label="Adv.Stats"}` and the screen titles
read `ADV.STATS`. Gen-1 detection uses
`GameVersion.generation(GameVersion.get()) == 1`; on Gen 1 the window is scaled
`S = 1.2` (160x144 -> 192x173) and every layout coordinate passes through
`SX(v)` (identity on Gen 2), so content scales with the window.

**Verified.** All four changed Lua files parse under Lua 5.1 (luaparse). Gen-1 full
battery `scratch/sim/round105-gen1-fullsim.json`: 218 files, **143/143 booted, 0
failures**. Gen-2 battery `scratch/sim/round105-gen2-verify.json`: 143/143, 0
failures, every sub-suite failCount 0 -- the only delta vs round 104 is
`exportsCount` 230 -> 231 (the new accessor). A targeted probe
(`scratch/sim/probe_advstats.lua`) confirms both renames, the accessor, the submenu
entry, and `uiSize()` 192x173 on Gen 1 / 160x144 on Gen 2. Manifest bumped
**3.0.0 -> 4.0.0** (breaking rename of two public option keys). The scene mod stays
**2.1.2** (its manifest is unchanged by the rename).

2026-09-10 round one-hundred-six — "flinch seems to not be wired for gen 1, fix, imperative, check other sub-effects, imperative. / show damage setting doesn't show numbers on battle scene right under (not overlapping/superposition pokemon's hp bar gui." — **every Gen-1 turn-eating volatile now actually eats the turn, and the floating damage numbers are moved clear of the readouts** (scene only; engine project untouched at 4.0.0).

**Root cause (flinch + the whole class of pre-move sub-effects).** The scene drives the native move EXECUTOR `BattleState:performMove` directly via `state:useMove`, and never ran `BattleState:executeAction` — the wrapper that owns the turn's non-damage halves. So on Gen 1 a battler's `flinched` flag (written by `main.lua`'s `damage_dealt` flinchChance block, King's Rock and `modern_items`) was set but NEVER READ: the pre-move status gauntlet (`BattleState:statusInterrupt` -> `Status.beforeMove`, `BattleState.lua:4143` / `Status.lua:290`) had no caller. The same was true of sleep/freeze/full-paralysis/confusion/disable/held-in-place, the Hyper Beam recharge arm, the trapping continuation and the per-move residual. Separately no Gen-1 end-of-turn ran at all (`combat/turn_residuals.lua`'s `runEndOfTurn` is Gen-2 only), so poison/burn/leech-seed ticks, the trapping-counter release, the `residualDone`/`skipMove` resets and `battle.turn_ended` were missing.

**Fix (`g9-Battle-Scene/native.lua`, `state:useMove` + Gen-1 turn arms).** `state:useMove` now reproduces `executeAction`'s own arm order: it refreshes `user.boundTurns` from the opponent's trapping counter, then (1) the recharge arm via `BattleState.preRechargeChecks` (sleep/freeze/flinch/held can eat the recharge turn WITHOUT consuming the flag — the native Hyper Beam glitch), (2) the trapping continuation (`statusInterrupt` first, then `continueTrapping` with the locked `trapMove`), (3) the ordinary pre-move `statusInterrupt` gauntlet (now handed the move id so a disabled move is caught), then (4) `performMove`, then (5) the Gen-1-timing per-move residual (`residualAfterMove` rulesets). New `N.applyGen1EndOfTurn(battle)` runs the non-presentation half of `BattleState:endOfTurn` once per turn from `N.resolveTurn`, whichever path resolved the moves. `N.resolveTurn` now also calls `BattleState.clearTurnFlinches` at the head of every turn, so a flinch a SLOWER attacker landed after its victim already moved cannot leak into the next turn.

**Damage numbers (`g9-Battle-Scene/battle_screen.lua`).** The old draw put the `-N`/`+N` at `top + 23*scale`, which sits ON the bar's bottom row (and on the player's numeric readout). `hudMark` now also records the readout box's own height (`h = GUI_BOX_H_ENEMY*8` / `GUI_BOX_H_PLAYER*8`), and `Screen:drawDmgNumbers` draws the label in the box's empty bottom band at `mark.top + (mark.h - 7) * eff`, still centred on the HP bar's 48px fill channel (`mark.left + 48*eff`). Enemy boxes (4 tiles) put the number directly under the bar; player boxes (6 tiles) put it under the numeric/exp rows — never overlapping the bar, the numeric current/max, the exp bar or the name row.

**Verified.** Scene probe `scratch/sim/probe_gen1_preturn.lua` loads the real `native.lua` against a faithful `BattleState` double and drives 9 cases — flinch/sleep/freeze/full-paralysis each `performMove==0` with the right status text, recharge `performMove==0` + "must recharge!", trapping `statusInterrupt==1` + `continueTrapping==1`, clean `performMove==1` + `residualFor==1`, end-of-turn fires, and a stale flinch is cleared at turn head (a recharging battler keeps theirs) — **all pass**. The probe also had to restore `BattleState.__index = BattleState` (the harness stub omits it; the real engine sets it at `BattleState.lua:47`). `luaparse` 5.1 clean on `native.lua` (49,281 B) and `battle_screen.lua` (344,024 B). `scratch/hud-final-mock.js` renders the new placement with the real pokecrystal tiles (enemy/player/statused/long-name); vision-checked — every number sits under its box content, none overlapping the bar, numeric, exp bar or border. `src/g9-Battle-Scene.zip` rebuilt with `scratch/build-scene-zip.js` (now includes the previously-omitted `native.lua`/`hp_bar.lua`; 15 files + 2 dirs = 17 entries, same order/names/headers as the shipped archive); every entry inflates byte-identical to source, manifest **kept at 2.1.2** (standing "don't bump the scene version" note).

**Version / live.** Engine project unchanged (**4.0.0**; no engine file touched this round). `src/g9-Battle-Scene.zip` rebuilt at **2.1.2**. Only `mods/g9-Battle-Scene` needs re-exporting this round.

2026-09-10 round one-hundred-seven — "flinch fix for gen 1 regressed flinch fix for gen 2, fix FUCKING BOTH STOP OVERENGINEERING. / flinch message, remove \"prompt \" word from any message sent to F box in battle scene" — **Gen 2's pre-action status gauntlet now runs in scene battles, and the F box no longer draws the `{PROMPT}` control token / the word "prompt"** (engine 4.0.0 → 4.0.1; scene kept at 2.1.2).

**Gen-2 flinch (and the whole turn-eating class).** A scene-driven Gen 2 battle calls `combat/turn_order.lua`'s `mod.exports.resolveTurnActions` instead of native `runTurn`, and that loop used to go straight from `moveUsability` to `battle:useMove` — it never called `Battle:canAct` (gen2/Battle.lua:1058 → `checkTurn`, :978). `canAct` is the ONLY thing that consumes a Gen 2 `vol.flinched`, a `vol.recharge`, the sleep/freeze arms, confusion's self-hit and attract, so in a scene battle a flinched/sleeping/recharging Gen 2 mon acted anyway. (The round-106 Gen-1 fix could not have caused this — it touched only `g9-Battle-Scene/native.lua`'s Gen-1 arm — but it was never wired on Gen 2 regardless.)

**Fix (`combat/turn_order.lua`).** A new local `actorCanAct(battle, mon, moveId)` calls `battle.canAct` under pcall (returns true when the engine has no `canAct`, so a trimmed engine is a no-op). `resolveTurnActions` now runs it ONCE per action, before `moveUsability`, and when it answers false the action is skipped entirely — `checkTurn` already emitted the "X flinched!"/"X must recharge!" line, and a spent turn neither announces a move nor spends PP. It is called once per ACTION, never per spread target: `checkTurn` consumes the flag, so a second call inside a spread move's target loop would have let the follow-up target through.

**F-box "prompt" (`g9-Battle-Scene/battle_screen.lua`).** Battle text from the engine/ROM keeps trailing `{PROMPT}`/`{DONE}` control tokens (`core/RomText.lua` preserves them; `render/TextBox.lua` strips them, but the scene draws through `Font` directly) and `Font` renders the token's letters literally — a flinched mon read "... flinched!{PROMPT}". `drawWrapped` (the single funnel for every F-box string: `currentMessage`, `message`, `overMessage`, `ask.text`, intro narration) now strips `{PROMPT}`/`{DONE}` in any case and any stray standalone "prompt" word before wrapping.

**Verified.** New Gen-2 probe `scratch/sim/probe_gen2_canact.lua` boots the real engine and calls `resolveTurnActions` against a mock battle: a flinched actor (`canAct` false) uses the move **0** times with `canAct` called once; an able actor uses it once; a spread move over two live targets uses it twice with `canAct` still called exactly **once** (the per-action rule) — all pass. The sanitizer cases pass too (`{PROMPT}`/`{prompt}`/bare "prompt" → gone; "prompting" and normal text untouched). The round-106 Gen-1 probe `scratch/sim/probe_gen1_preturn.lua` re-runs clean (**pass:true**, all 9 cases), so Gen 1 is untouched. `luaparse` 5.1 clean on both edited files (`turn_order.lua` 62,907 B, `battle_screen.lua` 344,746 B). Mod zips rebuilt: engine `scratch/deliver/g9-battle-engine-beta-4.0.1.zip` via `scratch/build-engine-zip.js` (232 entries, same order/headers as the 4.0.0 archive, every one of the 218 files inflates byte-identical, manifest 4.0.1); scene `src/g9-Battle-Scene.zip` via `scratch/build-scene-zip.js` (17 entries, every entry byte-identical, manifest kept at 2.1.2).

**Version / live.** Engine project **4.0.0 → 4.0.1**; scene **kept at 2.1.2** (standing "don't bump the scene version" note). Both `mods/g9-battle-engine-beta` and `mods/g9-Battle-Scene` need re-exporting.

2026-09-10 round one-hundred-eight — "perfect, all seems to be working, now preserve all so no regression happens. for gen 1, when player trainer and enemy trainer summon their pokemon, we are using a non native pokeball throw asset for gen 1 (gen 2 has proper gen 2 native animation and asset for it), we must have gen 1 also use the native asset for it instead too, gen 1's native, do not try to use gen 2's native." — **the Gen-1 summon/send-out ball is now Gen 1's OWN native ball** (scene only; engine project untouched at 4.0.1).

**What was wrong.** `Screen:drawBallThrow` (the intro send-out for player and enemy trainer mons alike) drew the screen's own bezier arc but fell back to `drawPokeball` — hand-drawn `love.graphics.arc`/`rectangle`/`circle` primitives — on Gen 1, because the native ball it draws on Gen 2 is Gen 2's own object (`BATTLE_ANIM_OBJ_POKE_BALL` inside `data.gen2BattleAnims`, read through `BattleAnimView`), which a stock R/B/Y boot has neither of. The Gen-2 path (round 25) was already native and is untouched.

**The fix (`g9-Battle-Scene/battle_screen.lua`).** New `drawGen1NativeBall(screen, cx, cy)` walks the ball out of the Gen-1 tables this file already drives through `src/battle/AnimPlayer.lua` — `N.gen1AnimData(data).moveAnims["TOSS_ANIM"].seq[1]` → `subanims[..].blocks[1].block` → `frameBlocks[..]` = `FRAMEBLOCK_03` (a 2x2 16x16 composite of tiles `$02` upper half / `$12` lower half out of anim tileset 0; `data/battle_anims/frame_blocks.asm` `FrameBlock03`, reached via `Subanim_0BallTossHigh`, which `data/moves/animations.asm` `BallTossAnim` points at) — and draws those tiles through the same `AnimPlayer:sheetImage`/`tileQuad` sheet path `Screen:drawGen1AnimSprites` uses, translated to the caller's throw position and scaled by the same `BALL_DRAW_SCALE` (0.6) the Gen-2 ball uses. `drawNativeBall` now branches on `N.isGen2` FIRST: Gen 1 → `drawGen1NativeBall`, Gen 2 → the existing object/frameset path unchanged. So Gen 1 reads Gen 1's own ROM art and never Gen 2's (the user's explicit rule), and `drawPokeball` stays the fallback only for a boot whose `battle_anims`/tilesheet is missing. Nothing native tumbles the ball (the GB walks a static graphic along base coords), so the flight is a pure translate along this screen's own bezier. A per-screen `AnimPlayer` (`screen.gen1BallPlayer`) is built once and reused for the sheet/quads.

**Verified.** New harness `scratch/sim/run-ball-gen1.js` (+ `ball_gen1_prelude.lua` / `ball_gen1_test.lua`) extracts the SHIPPED ball region out of `battle_screen.lua` and runs it under fengari against a synthetic `battle_anims` — **14/14 green**: the four native tiles land as a 16x16 box centred on the throw position (`$02` top, `$12` bottom, right column x-flipped), the block is walked from the data (a different subanim/block draws its own tiles and flips), a missing tilesheet / frame block / `TOSS_ANIM` / `AnimPlayer` each return false so the primitive remains, the per-screen player is created once, the Gen-1 `drawNativeBall` dispatch positions via translate ((10,20) → local box (-8,-8)), and Gen 2's object/frameset path is unchanged. Regression: the Gen-1 pre-turn battery (`scratch/sim/probe_gen1_preturn.lua`, run with `reportOnly`) re-runs clean (143/143 subsystems, 0 failures, `pass: true`, 15 keys) and the Gen-2 probe (`scratch/sim/probe_gen2_canact.lua`) is unchanged (flinch → 0 uses / 1 `canAct`; spread → 2 uses / 1 `canAct`; all sanitizer cases pass). `luaparse 5.1` clean on `battle_screen.lua` (348,617 B).

**Version / live.** Engine project unchanged (**4.0.1**; no engine file touched this round). `src/g9-Battle-Scene.zip` rebuilt via `scratch/build-scene-zip.js` — 17 entries, same names/order/methods/versions/attrs as the shipped 2.1.2 archive, every entry inflating byte-identical to source, manifest **kept at 2.1.2** (standing "don't bump the scene version" note). Only `mods/g9-Battle-Scene` needs re-exporting this round.

2026-09-10 round one-hundred-nine — user: rename the manifest id/name `g9-battle-engine-beta` -> `g9-battle-engine`, and make sure the change does not break the intercommunicated mod system (the shared battle-sprite mod and the battle-scene mod we are working on). — **the engine's mod ID and display name are now `g9-battle-engine`** (engine 4.0.1 -> 4.0.2).

**Why an id (not just a name) change is the risky part.** The engine's loader (`Loader.lua`) keys every mod and its exports by `manifest.id` (`self.mods[manifest.id]`, `self.exports[id]`); `mod.find(id)`/`mod:find(id)` resolve by id ONLY (name is display-only). A mod with a hard `dependencies` entry naming a missing id is failed at load (`_fail(mod,"blocked_dependency","missing dependency: "..dep)`) and never runs; `optional_dependencies` are order-only and tolerate a missing id. Duplicate ids: the second is ignored. So the rename had to update (a) the engine manifest, and (b) every hard dependency and every `mod.find`/`mod:find` call across the ecosystem.

**Edits.** Engine `manifest.json` id+name -> `g9-battle-engine`; version 4.0.1 -> 4.0.2; description reworded (the old "see g9-battle-engine for those" sibling reference removed). The old id appeared **187 times across 107 files**; every occurrence was replaced with `g9-battle-engine` — quoted tokens first (log prefixes `mod.log:*("g9-battle-engine: ...")`, the `loaded: N/N` boot line, and quoted doc/example references incl. 21 in `trainers/custom_trainer_registry.lua`), then the remaining unquoted PROSE comments (`main.lua:2` boot comment, `options.lua:1`/`:28`, `combat/showdown_primitives.lua:17`, `combat/turn_order.lua:699`, `gigantamax/tera_state.lua:22`/`:198`, `trainers/custom_trainer_registry.lua:536`, `combat/MULTI_BATTLE_HOOKS.md:310`). The only **6 survivors are in README.md's OWN changelog entries** (rounds 107/109), deliberately kept so the rename itself is recorded as history. Dependents updated: `g9-Battle-Scene` manifest `dependencies` + two functional `mod:find("g9-battle-engine")` (`combat.lua:38`, `battle_screen.lua` ~6611) + the error string; `g9-battle-sprites` manifest `optional_dependencies` (order-only, so the sprite mod was never at risk either way); `g9-trainer-sample` manifest `dependencies` + `ENGINE_ID`/find/warn; `Sample-Battle-Scene-G9` find + description; `battle_forms` manifest `optional_dependencies`; and the studio's own UI labels (`src/main-app.js`, 6 strings). The scene zip was rebuilt from `scratch/g9scene/` via `scratch/build-scene-zip.js`.

**Verified.** Fengari Gen-1 boot probe (`scratch/sim/run-probe.js` + `probe_gen1_preturn.lua`, `{gen:1, reportOnly:true}`) -> 143/143 subsystems, 0 failures, pass:true; the Gen-1 ball harness (`scratch/sim/run-ball-gen1.js`) -> 14/14. Console shows `g9-battle-engine: <subsystem> installed` and `g9-battle-engine loaded: 143/143`. Deliverable `scratch/deliver/g9-battle-engine-4.0.2.zip` built from `scratch/engine-extract/` with the top folder rewritten `g9-battle-engine-beta/` -> `g9-battle-engine/` (232 entries = 218 files + 14 dirs), every entry inflating byte-identical to source, manifest inside = new id/name/4.0.2. Scene zip (17 entries, v2.1.2), the shared sprite zip (2.0.0 source, only its optional dep + one README line changed), the trainer-sample zip, `src/Sample-Battle-Scene-G9.zip` and `src/battle_forms.zip` were all rebuilt and byte-verified.

**Version / live.** Engine **4.0.1 -> 4.0.2**. Scene kept at **2.1.2** (standing "don't bump the scene version" note); the sprite mod keeps its own version (only its optional-dependency string changed). The user must **DELETE the old `mods/g9-battle-engine-beta/` folder** when installing, then install `mods/g9-battle-engine/` (both ids loading at once would double-register), and re-export `mods/g9-Battle-Scene`.
