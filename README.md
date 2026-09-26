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

## The Pokecenter nurse heals to the modern max, skips the machine, and can shorten its chat (4.4.6)

**The spec.** "we need to take over healing by pokemon center ... make it so
healing in pokemon center full heals to our modern stats max hp of each pokemon
and makes player turn away from the NPC (face south after done talking) make
sure NPC still has pokerus report to player and all of its sequencing. lastly,
shorten healing chats to a single message ... route one just sends \"We restore
your tired Pokemon to full health.\" ... this shortening sequence is to be a
toggle on/off in g9-gui. dont play the pokeball placing in machine sequence
before healing."

**What was wrong.** Vanilla heals to `mon.stats.hp` and `mon.maxHp`, which are
this mod's MODERN figures only after `recalcAll` has rewritten the stat block.
`Pokemon.heal` (Gen 1) and `World:healParty` (Gen 2) read those fields directly,
so a mon that had never been through the modern layer healed to its legacy
(DV/stat-exp formula) max, not the Gen 3+ formula's. The machine also always
played, and the conversation is long.

**The new file.** `overworld/pokecenter_heal.lua`, booted from `main.lua` right
after the stats installs (`stats/egg_normalize.lua`). Unconditional on BOTH generations:

* **Modern-max full heal.** `modernMaxHp` runs the exact pair the TRAIN editor
  and `stats/ev_yield_on_faint.lua` use -- `ModernStats.ensure` (fill-only: a
  legacy mon's IVs/EVs derived once from its DVs/statExp) then
  `ModernStats.recalcAll` (all six stats from those + the modern base) -- and on
  Gold mirrors `specialAttack`/`specialDefense` and `mon.maxHp`. Gen 1 then
  calls the engine's own `Pokemon.heal` (hp = stats.hp, status cleared, PP
  restored with the PP-Up bonus); Gen 2 sets hp = maxHp, clears
  `status`/`statusTurns` and restores each move's `maxPp`. **Eggs are skipped
  outright** -- an egg is a fainted mon by rule (`stats/egg_normalize.lua` pins
  `hp = 0`), and a center heal is exactly what would resurrect one.
* **Player faces south.** `player.facing = "down"` once the conversation ends
  (the player faces up at the counter, so that is "turn away").
* **The machine never plays.** Gen 1's own `healAnim` is bypassed because this
  file owns the flow; Gen 2's `World:startHealMachineAnim` is wrapped to resume
  its `onDone` immediately, and `World:healParty` is wrapped so EVERY caller
  (the nurse script, a whiteout) gets the modern max.
* **Pokerus is preserved, with its sequencing.** Gen 2 reuses the ROM's own
  `NursePokerusText` (the LAST `writetext` in the std script body, read live
  from `world.scripts`/`world.text`), sets `ENGINE_CAUGHT_POKERUS` through
  `World:setEngineFlag`, and queues `SPECIALCALL_POKERUS` through
  `World:setSpecialCall` -- behind the cart's own two guards (`checkphonecall`
  via `World:specialCall()`, and the engine flag itself).

**The toggle.** g9-gui gains a `short_heal_chat` option (SHORT HEAL CHAT, ON by
default) and publishes it as `mod.exports.shortHealChatEnabled` -- the engine
mod cannot read another mod's `mod.options` bucket, so the export is the
supported cross-mod route, and it is set BEFORE g9-gui's own MODERN UI gate so
it answers even with that mod's screens off. The engine reads it LAZILY at the
moment a nurse is talked to; with g9-gui absent the shortening is still the
default. ON: player talks -> (pokerus report first, if pending) ->
"We restore your tired Pokemon to full health." -> done. OFF: the vanilla chat
is kept -- Gen 1's is reproduced from the same ROM strings
(`_PokemonCenterWelcomeText`, `_ShallWeHealYourPokemonText`,
`_NeedYourPokemonText`, `_PokemonFightingFitText`,
`_PokemonCenterFarewellText`) with the HEAL/CANCEL box, while Gen 2 lets the
cart's own extracted `PokecenterNurseScript` run through the VM untouched.

**Finding the nurse.** Gen 1's nurse is dispatched by the `entry.nurse`
TX_SCRIPT marker into `OverworldState:nurseHeal`, so that method is wrapped
directly. Gen 2's nurse is an ordinary map object (`SPRITE_NURSE` behind a
counter) whose script is a per-map stub that `jumpstd PokecenterNurseScript`
(confirmed against real maps, e.g. `maps/CherrygrovePokecenter1F.asm`); it is
recognised EITHER by sprite name
(`world.constants.spriteOrder[def.sprite] == "SPRITE_NURSE"`) OR by its
script's rows naming the std script, so a differing sprite order still matches.
The talk is taken over through the documented `OverworldController.talkTo`
facade seam (`Gen1Facade.talkToWrapper`, a `true` return suppresses the
built-in path). With the toggle OFF, the per-step `OverworldController.update`
seam (called from `World:step`'s tail by `Gen2Compat.worldTick`) turns the
player south once `World:busy()` is false.

**Verified.** `luaparse 5.1` clean on the new file and `main.lua`;
`manifest.json` valid JSON at 4.4.6. The fengari boot harness is **225 files,
151/151 subsystems, 0 guarded failures**, with `roundFails` unchanged from the
recorded baseline (only the pre-existing `round74 ldRestoresPp` and
`round78 r186SnapshotParty`/`r186ReSnapshot`). `scratch/sim/probe_pokecenter.lua`
(on the Gen 2 boot) checks the real export math against the harness's
national_dex stub: base 100 / L50 / IV 31 / EV 0 -> modern HP **175** on both
generations, Gen 2 mirrors `maxHp`/`maxPp`/special aliases, an egg stays at
**0 HP**, and all three nurse-recognition signals answer correctly. The Gen 1
branch was exercised through a standalone fengari test (the boot harness's
Gen 1 mode cannot boot this mod's full `main.lua`): toggle ON pushes exactly one
box reading "We restore your tired Pokemon to full health.", heals to 175, sets
`lastHeal`, clears status, does NOT call the vanilla nurse, turns the player
south and calls `onDone`; toggle OFF pushes the welcome box with the HEAL/CANCEL
choice and heals on accept. The Gen 2 branch was exercised the same way:
`healParty`/`startHealMachineAnim`/`talkTo`/`update` all install, the heal wrap
gives hp 175 / maxHp 175 / PP 35 without calling vanilla, the machine resumes
immediately, the short flow shows one line (or pokerus-then-line, with the flag
set and the call queued only after the pokerus page is dismissed), a non-nurse
is not claimed, and toggle OFF lets the native script run then faces the player
south exactly once.

**Version / live.** Engine project **4.4.5 -> 4.4.6**; `g9-gui` **2.8.6 ->
2.8.7** (its new option + export). `g9-Battle-Scene` (3.9.1) and
`g9-battle-sprites` (3.3.0) are unchanged. The user must re-export
`mods/g9-battle-engine` (4.4.6) and `mods/g9-gui` (2.8.7).

## A stale Dynamax marker can no longer ride into a save (4.4.5)

**The report.** "fakeout regression, it's not flinching, it is a 100% flinch
move." Fake Out carries `flinchChance = 100`, so a target that was immune to
flinch never flinched -- in that fight and every later one.

**Root cause: a battle-scoped marker whose battle-end exits never fired.**
`gigantamax/dynamax_battle.lua` stamps `mon.__g9Dynamaxed = true` when
battle_forms' own `dynamax_applied` fires, and clears it on
`dynamax_reverted`. But battle_forms does not emit a revert on every exit: its
`forget()` (src/dynamax.lua, bound to battle.started **and** battle.ended)
clears its internal state *silently*, its battle-end sweep (src/resolve.lua)
reverts **forms** without a `dynamax_reverted`, and `g9-Battle-Scene` never
raises `battle.fainted` at all (it emits `battle.ended` /
`battle.turn_started` / `battle.battler_switched` / `battle.ball_thrown` /
`battle.exp_gained` only), so battle_forms' own `onFainted` teardown never
runs there either. A Dynamaxed mon that fainted or was withdrawn when a scene
battle ended therefore kept the marker -- and the old `battle.ended` sweep
only walked `allActiveBattlers(battle)`, i.e. the mons **on the field**, so a
benched one was never touched. On Gen 2 a party mon IS its save record, so the
marker was written into the save and `isDynamaxed()` answered true forever:
`abilities/engine/hit_taken.lua`'s `setFlinched` and
`abilities/engine/status_immunity.lua`'s `hasStatusImmunity` both
early-return, making the mon permanently immune to flinch and every status. That
is the reported bug: a 100% flinch move stops flinching a Pokemon that
Dynamaxed in some earlier battle, and the marker rides on across saves.

**The fix: make `__g9Dynamaxed` strictly battle-scoped.** The marker is now
swept the same way the stat baseline (`combat/modern_stat_manipulation.lua`,
round 184) and the ability snapshot (`abilities/ability_dispatch.lua`, round
186) are: the WHOLE roster at `battle.started` (so a save already carrying a
stale marker self-heals the next time it fights), the leaving mon at
`battle.battler_switched`, the fainter at `battle.fainted`, and the whole
roster again at `battle.ended` (last, priority -1000). The roster walk covers
`allActiveBattlers` (N-way), the scene's `battlersByMon` cache,
`battle.party` / `playerParty` / `enemyParty`, and Gen 1's real
`battle.game.save.party`, deduped by raw mon; `mod.exports.clearDynamaxMarkerRoster`
is exported for direct testing. The `battle.started` sweep cannot clobber a
live Dynamax: battle_forms activates only mid-battle, through the overlay/EFFECT
path -- never inside the constructor's `battle.started`.

**Verified.** `scratch/sim/probe_dynamax_leak.lua` drives every exit against a
realistic battle (a benched Dynamaxed mon in `battle.party`): marked and
flinch-immune after apply (with a negative control proving a flinch is refused
while marked), clean after `battle.ended` with the mon benched AND on the
field, clean after a simulated poisoned save's `battle.started` (self-heal),
clean after `battle.battler_switched` and `battle.fainted`, and still marked
after a `battle.turn_started` (no over-clearing mid-fight); a real
`setFlinched` lands once the marker is gone. `scratch/sim/probe_fakeout.lua`
and `probe_fakeout_turn.lua` (Fake Out end to end: flinch message, enemy skip,
gate) still pass. `luaparse 5.1` clean; fengari harness 150/150, 0 guarded
failures.

## A spread that hits nothing fails loudly, and one action can fail alone (4.4.4)

**The silent spread.** `resolveTurnActions`' "used and failed" tail was guarded
by `if #live == 0 and failed then`. `resolveSingleTarget` sets `failed`, but the
**spread** branch (`resolveMoveTargets`) never does -- it just returns an empty
list when the caster has no adjacent opponent. So a spread move that expanded to
zero live targets resolved to **nothing at all**: no `move` event, no PP spent,
no "But it failed!" line. That is the reported "Surf and spread moves do nothing
after the first use; the mon just doesn't act". The guard is now `if #live == 0`,
so the spread case announces the move and prints "But it failed!", exactly like
the single-target no-recipient case.

**Per-action failure.** An `actingBattlers` entry may now carry `fail = true` --
the battle scene's own positional-adjacency refusal (a triple-battle wing whose
only live foes are non-adjacent, so the scene offered no target at all). Both
`resolveTurnActions` (Gen 2) and `resolveNextActionForGen1` (Gen 1 stepwise) see
the flag and run `failAction` for that one entry: the move is announced,
PP-spent and failed at its own place in the turn order, and **every other actor
this turn still resolves**. This is what lets one un-reaching slot fail without
skipping the rest of its team's turn -- the scene used to abandon the whole
selection instead. `failAction` is forward-declared near the top of
`combat/turn_order.lua` so the Gen-1 stepwise path (defined before it) can use
it; it was already generation-neutral (guarded `battle.moveDef` / `monName` /
`markMissed`, and the scene's Gen-1 model provides `emit`).

**Harness.** `scratch/sim/probe_spread.lua` (run through `scratch/sim/
run-probe.js`): a spread with zero live targets now emits a `move` event, a
"failed" `message`, and spends exactly 1 PP (was 0/0/0/0); a `fail`-flagged
action fails alone while two allies still call `useMove` (2 calls), and a
control with no flag resolves all three (3 calls). `scratch/sim/probe_stepturn.lua`
still passes (Gen-1 stepwise unchanged on the normal path).

## Eggs are real Pokemon (4.4.0)

**The gap.** A Gen 2 egg is an ordinary mon record whose species is hidden behind
`mon.isEgg = true` (`src/core/gen2/Breeding.lua`: the cart keeps the species and
only *prints* "EGG"). The engine already keeps eggs out of every battle path
(`Battle.new`/`BattleState` pick checks, `LinkBattle`/`TeamPick`/`Trade`
refusals, the party menu's own `PartyMenuCheckEgg` routines) and
`src/core/gen2/Boxes.lua` pins a boxed egg's HP back to 0 -- but nothing gave an
egg the **modern fields** every other mon in this engine carries:

* no `mon.nature` and no `mon.ability` at all;
* no IVs/EVs of its own -- `stats/save_scrub.lua` would derive a legacy egg's
  IVs from its DVs on a save load, but an egg created *during* play (day care,
  gift, ODD EGG) carried none, and an egg's `statExp` is zero;
* no shared **name**: the day-care egg's nickname is literally `EGG`, the ODD
  EGG names itself `ODD`, and Gold's party menu never reads an egg's nickname at
  all (`PartyMenu.rowFor` returns `Strings(EGG_LABEL)` outright).

**The rule.** Every egg, wherever it is found, is normalized once into a real
Pokemon record that happens to be unhatched: **nature generated, ability
generated, IVs generated, EVs initialized to 0, the name `egg`, and HP pinned to
0** -- an egg is a FAINTED Pokemon for every battle purpose and can never be
sent out. Its species is untouched (that is the hatchling's species).

**Where it looks.** New `stats/egg_normalize.lua`, booted right after
`stats/gen2_modern_stats.lua`:

| Trigger | What is swept |
|---|---|
| `save.loaded` | the save's party, every box, and the day-care slots (`Mon.eachSaveMon`'s exact set) |
| `game.ready` | the same walk (a new game, or a checkpoint restore that never emitted `save.loaded`) |
| `battle.started` | the live player party (and the enemy party), so a mid-session egg is real before the next battle |
| `Breeding.makeEgg` | the day-care egg, the moment the one builder returns it |
| `World:giveEgg` | the scripted gift egg (Togepi) |
| `Mon.stampOT` | the ODD EGG (and any other route that stamps OT on a record already marked `isEgg`) |
| `PartyMenu.rowFor` | Gold's party row, which otherwise hardcodes the cart's `EGG` label instead of reading the name |

The modern fields are idempotent by construction (`ModernStats.initialize`
keeps existing IVs; `generateNature`/`generateAbility` only fill a nil), so a
re-run can never re-roll anything the player has seen; only the name and the
zero HP are re-asserted every pass, which is what makes the rule absolute. A
`g9EggNormalized` stamp on the mon (persisted like every other modern field)
keeps the expensive half to one pass.

**Verified.** `luaparse` clean on the new file and `main.lua`. The full fengari
boot harness (all 223 project files) boots **149/149 subsystems, 0 guarded
failures** -- the same two pre-existing token-detector quirks in rounds 74/78,
nothing new. A dedicated probe (`scratch/sim/egg-normalize-harness.js`, the real
`engine_modern_stats.lua` + the real `egg_normalize.lua`, deterministic RNG,
stubbed engine modules) passes every check: a party/box/day-care egg all come out
with a real nature, a real non-hidden ability, six IVs in 0-31 and six zeroed
EVs, the name `egg`, `hp == 0`, coherent stats (`maxHp == stats.hp`,
`specialAttack == spa`); a second pass is byte-identical (idempotent); a swept
name/HP are re-asserted; `game.ready` and `battle.started` sweep too; all three
builders (`Breeding.makeEgg`, `World.giveEgg`, `Mon.stampOT`) are wrapped and
normalize a fresh egg; a non-egg mon is never touched; and the install logs no
warnings.

## No battle-scoped object ever rides into a save (4.3.6)

**Symptom.** Winning a trainer battle on Crystal and then saving killed the
game with `src/core/SaveSerializer.lua:13: stack overflow` -- the reported case
was a Bird Keeper fight with a six-mon party, right as the post-battle save was
written.

**Why it happens.** `SaveSerializer`'s writer walks tables recursively with no
cycle detection (the `MAX_DEPTH` guard is on the READER only). On Gen 2
`battle.party` IS `save.party`, and the battle also holds maps keyed by mon
tables (`combat/turn_order.lua`'s `battle.__g9ChosenMoves`), so any mon field
holding the battle -- or a battler, whose `.mon` points back at the mon -- closes
a mon -> battle -> mon cycle. The ability snapshot (round 186) stored the battle
object itself on every party mon (`mon.__g9AbilityBaselineBattle = battle`); a
Transform/Imposter snapshot (round 183) stored the live engine battler
(`pre.battler`). Both are normally swept at `battle.ended`, but a missed
boundary -- the same class the move-usability marker had -- leaves one behind and
the NEXT save dies. `g9-Battle-Scene` 3.8.8 ships a save-time sanitizer that
clears such a cycle, which stops the crash; this round removes the two remaining
SOURCES in the engine so the cycle is never created.

**Fix -- two scope markers, neither of them a table.** `abilities/ability_dispatch.lua`'s
baseline scope is now a plain number: a weak-keyed `battleIds` map (the exact
`combat/move_usability.lua` scheme, `__mode = "k"`) hands each battle a
monotonically-assigned id, `nil` maps to the fixed id 0 ("no battle scope"), and
`mon.__g9AbilityBaselineBattle` holds that number. A save from an older build
that still carries a table there reads as a different id and is simply
re-captured, so the change is self-healing. `combat/modern_transform.lua`'s
`snapshotTransform` now records only the boolean `hadBattler` (did the caller
hand in a wrapper) instead of the battler; `revertTransform` re-resolves the
battler from the battle (`who` when it is a battler, else `battlerFor` via
`battle.battlersByMon`) and touches the battler fields exactly when the original
snapshot had a wrapper -- a mon that never had one behaves precisely as before.

**Verified.** `luaparse 5.1` clean on both files and the whole tree (211/211
.lua). The full fengari boot harness (the real engine project, all 222 shipped
files) boots **148/148 subsystems, 0 guarded failures**. A new probe
(`scratch/sim/probe_savecycle.lua` + `run-save-cycle.js`) drives the REAL exported
primitives against the REAL `SaveSerializer` and passes **35/35**: the pre-276
shapes (`mon.__g9AbilityBaselineBattle = battle`, `pre.battler = battler`) do
overflow the writer, the post-276 shapes serialize, the ability snapshot
round-trips (capture -> change -> restore), the transform snapshot reaches
neither its mon nor its battle and reverts through a battler, a raw mon and a
missing battler, and a 6-mon Gen-2 save with both scopes live encodes cleanly.

## Frame-tick recursion brake (4.3.5)

**Symptom.** Fast-forwarding (GAME SPEED > 1X) through an NPC conversation --
the reported case is an NPC **trade** -- killed the game with the Lua
`stack overflow` screen whose traceback runs `love.update` -> `main.lua`'s
`PlatformHooks.update` -> `src/mods/Hooks.lua`'s `core.update` chain. The user's
read was exactly right: too many frame requests are allowed through, and at
speed they hoard until the stack dies.

**Why speed is the trigger.** `Game:update` feeds `dt * speed` into
`src/core/FixedStep.lua`, whose `while accum >= STEP` loop calls the step
callback once per whole step. At 1X a nested frame pass buys no step (the
nested accumulator never reaches 1/60), so an accidental re-entry is harmless.
At a high multiplier every nested pass buys at least one step, each of which can
nest again -- so a re-entrant frame request becomes unbounded recursion.

**Fix.** `core/tick_guard.lua`, a new subsystem booted first (so its
`core.update` link is in the chain from frame one) at **priority 100000**, which
makes it the outermost `core.update` link. Three fail-open brakes:

1. **`core.update` re-entrancy is coalesced, not recursed.** A frame request
   that arrives while the chain is already running is parked in a one-slot
   queue and returns immediately (debounce); the outermost call drains that
   slot iteratively after it unwinds. N nested requests cost one stack frame,
   not N -- the "decouple the trigger from the execution" half.
2. **`FixedStep:update` has an explicit recursion depth limit**
   (`MAX_STEP_DEPTH = 4`; the shared driver, so one wrap covers Gen 1, Gen 2 and
   Game 3). Past the limit the nested pass is refused rather than recursed. The
   same wrap throttles `self.maxAccum` back to the engine's own 0.25 s /
   15-step catch-up ceiling, so one call can never spend more logic debt than
   the engine intends.
3. **`StateStack:push` has a hard state ceiling** (`MAX_STACK_STATES = 256`), so
   a screen that re-opens itself cannot hoard an unbounded stack. Normal play
   never passes a couple of dozen states.

Every brake only skips work that is already redundant or already pathological,
logs a rate-limited line, and never changes a healthy frame.

**Exported primitive** -- `mod.exports.tickGuard.defer(fn, ...)` queues a task
to run at the start of the next frame tick instead of synchronously. This is the
general "asynchronous task queue" escape hatch for any trigger handler that must
not re-enter the frame loop (an NPC interaction, a menu callback that wants to
open another screen). The queue is bounded (256); a full queue drops with a
warning rather than growing. `tickGuard.active()` reports whether a tick is in
progress, and `tickGuard.stats()` exposes every brake's counters.

Verified by `scratch/sim/tick_guard_harness.lua` (29 checks, all green): nesting
past `MAX_STEP_DEPTH` is refused at exactly 4 engine passes; unbounded
re-entrant frame requests settle at 5 flat passes at depth 1 (the exact stack
that used to overflow); the defer queue runs once per tick, cannot be extended
by a self-re-deferring task, and stays bounded; a healthy frame runs exactly one
pass and logs nothing.

## Gen 2 id vocabulary -- the mod now speaks Gold's spelling (4.3.4)

Two id spaces this engine keys by their own cart's names, and a data source
(`national_dex`) that only writes the Gen-1 spelling of each:

| field | this mod / national_dex write | Gold registers |
|---|---|---|
| `growthRate` | `MEDIUM_FAST` | `GROWTH_MEDIUM_FAST` |
| `levelMoves[].move` | `METALCLAW` (cart-owned Gen 2 moves, no separators) | `METAL_CLAW` |

On a Gold boot each of those was a genuinely unresolved `f.id(...)` reference,
and the loader's `Schemas.crossValidate` reported every one. `species/gen2_vocab.lua`
is the single place this mod translates between them. Two mechanisms, both
checked against the LIVE registry so a resolution can only ever name an id that
actually exists:

- **Same word, different separators** (moves) -- `normalise()` strips
  everything but `[A-Z0-9]` and a reverse index over the live registry resolves
  `METALCLAW` -> `METAL_CLAW`. A normalised form two different live ids claim
  resolves to neither (never picked between) -- the same rule national_dex's own
  `src/moverepair.lua` applies.
- **Different word** (growth rates) -- Gold prefixes (`GROWTH_`), each candidate
  checked against the live registry.

An id neither mechanism can resolve is returned **unchanged** -- a genuine typo
stays a genuine, reported typo rather than being silently waved through. Every
method is a no-op on Gen 1 (the id already matches the registry exactly), so the
callers carry no generation branch of their own.

Consumers: `combat/learnset_ownership.lua`'s `registeredMoveId` resolves the
cart-owned move spellings (previously they dangled because national_dex does not
carry the cart's own moves, so its `strippedId` map has no entry for them); and a
sweep (`gen2_vocab.reapply()`) re-resolves every registered species record after
national_dex has registered -- national_dex ships all ~1238 of its records with
`growthRate = "MEDIUM_FAST"`.

Measured on a Gold boot by the engine's OWN `Schemas.crossValidate` (run over a
mock of the merged registries, `scratch/sim/gen2_schemas_audit.lua`): the
`growth_rates` **1238** and `moves` **1869** dangling references collapse to 0 --
every one of them a Gen 1 spelling this module now resolves. 42 unit and
integration checks are green across `scratch/sim/gen2_vocab_harness.lua`,
`gen2_wiring_harness.lua` and `gen2_crossvalidate_harness.lua`.

## Evolution is no longer this engine's job (4.5.0)

All evolution handling has been removed from this mod: the 1025-species
`species/species_evolutions.lua` data file (and its custom evolution items), the
`species/exotic_evolution_stubs.lua` method-stub file, the `HAPPINESS` method
registration + battle-friendship nudge, the `ItemEffects` evolution-item hook,
and the per-species `evolutions` field patch are all deleted. Evolution is a
separate mod's concern now (see `g9-evolutions`), which owns the `evolutions`
rows via `national_dex`; this engine neither patches that field nor registers any
evolution method. `national_dex` ships every species' `evolutions` field empty,
so with neither this mod nor an evolution mod installed nothing evolves -- by
design. The one battle-side reader left is Eviolite's NFE check in
`combat/modern_held_items_phase2.lua`, which asks `national_dex`'s own
`evolutionsOf` directly and is unaffected by this removal.

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
layout, so register the boss itself (typically a single ace). For
doubles/triples/bossFight, the player's side of the layout is filled from the first
N LIVING party mons in party order -- a fainted party member is skipped, never sent
out.

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
handled by the pipeline, 6 structurally impossible in singles (5 since 4.6.7,
below), and **156 genuine residual gaps** now mapped to phases 13-23 of the
plan.

The impossible-in-singles moves ship in `combat/structural_exemptions.lua`,
booted by `main.lua` as `structural_exemptions`:

- ALLYSWITCH, FOLLOWME, HELPINGHAND, RAGEPOWDER, SPOTLIGHT -- each needs a
  second **allied** battler (a slot a 1v1 fight never has).

**DRAGONCHEER was retired from the registry in 4.6.7**: it was exempt only
because `all-allies` excludes the user, so a singles battle has an empty target
set -- but a scene-driven multi-battler battle really does have adjacent allies
now, so it is implemented instead (`combat/modern_crit_override.lua`'s
`GALAR_DRAGONCHEER_EFFECT` puts the switch-scoped `dragoncheer` crit volatile on
the user's adjacent allies). The registry now holds five ids.

`mod.exports.structuralExemptions` (id → reason) and
`mod.exports.isStructurallyExempt(id)` are published for other subsystems and
debug sessions. The harness round 81 check asserts the registry boots, names
the remaining ids, and stays disjoint from the mod's move-patch log. Deliberately
NOT exempt (they include the user, so they work in singles and are wired
rather than listed): Howl, Gear Up, Magnetic Flux (Gear Up / Magnetic Flux
earlier, Howl in 4.6.7), and the Wide/Quick/Crafty/Mat Guard family.

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
sole remaining unreachable file). `mod.card` was rewritten to drop the outdated
sprite/overworld wording and its stale "175 of 934 moves" coverage figure.

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

2026-09-10 round one-hundred-ten — user: "in g9-battle-engine: turn it off by default, adv.stats is the only screen we need for modern stats display" — **the wide 256x144 modern stats screen is now opt-in, OFF by default, so the party menu's STATS action opens the game's native party summary screen; Adv.Stats (`adv_stats`) remains the mod's modern stats display** (engine 4.0.4 -> 4.1.0).

**What changed.** `stats/modern_stats_screen.lua` used to install unconditionally and wrap `ui.party.submenu`, replacing the STATS item's action with its own `GgdModernStats` screen (Gen 1 only — `isGen2Boot` already stopped it on Gen 2). It is now gated on a new Mod Manager row `key = "modern_stats_screen"`, `label = "MODERN STATS SCREEN"`, type `choice`, **default `false`**. The gate is read lazily INSIDE the wrap callback (`mod.options:get("modern_stats_screen") == "true"`), the same idiom `stats/dev_stats_screen.lua` uses for its own `adv_stats` entry, so it is correct even though the schema is only defined later in `main.lua`'s `debug_options` boot. With the row OFF the wrap returns the submenu untouched and STATS opens the native party summary (which `g9-battle-sprites` decorates); with the row ON the old behavior returns exactly as before.

**Options (`options.lua`).** Now four rows in order: `damage_numbers` (default false), `gym_badge_buff` (true), `modern_stats_screen` (false, new), `adv_stats` (false). `adv_stats` is untouched — Adv.Stats is the mod's modern stats display and is independent of this gate.

**Docs.** `options.lua` header comment (new round-106 block), `stats/modern_stats_screen.lua` header + install log line, and `main.lua`'s stats-screen boot comment all updated to describe the opt-in gate. `manifest.json` bumped **4.0.4 -> 4.1.0** — a new user-facing option, not a breaking change; old saved option settings are unaffected.

**Verified.** `luaparse 5.1` clean on `options.lua` (7,741 B), `stats/modern_stats_screen.lua` (15,848 B) and `main.lua` (114,068 B); `manifest.json` valid JSON, `version` = 4.1.0. Project written back to the studio kv (`project.v` 64 -> 65).

**Version / live.** Engine project **4.0.4 -> 4.1.0**. The user must re-export `mods/g9-battle-engine` (and, for the party-summary sprite work, `mods/g9-battle-sprites` at 2.6.0).

2026-09-17 round one-hundred-fifty-six — user: "battle sample mod ... water pokemon are still being randomized on grass encounters, caves have no encounters at all ... battle engine: trick room, wonder room, magic room arent setting their respective room effects that should be endless till battle ends at battle start, there's still one of the flags that prevents attacks from being done at all, all moves fail." — **the `dimensionLock` boss flag no longer fails every move, and a permanent boss room now announces itself the moment it is applied** (engine 4.1.0 -> 4.1.1).

**The "all moves fail" flag (the real engine bug).** `combat/trick_room.lua`'s `Battle:useMove` wrap read `if flags.dimensionLock or (ownFlag and flags[ownFlag])`, so `flags.dimensionLock` short-circuited for EVERY move regardless of which move it was -- a boss carrying `dimensionLock` printed "But it failed!" and returned before the native move ever ran, for BOTH sides, for the whole fight. The condition is now gated on the move actually being one of the three room moves first: `local ownFlag = ROOM_MOVE_FLAG[moveId]; if ownFlag and (flags.dimensionLock or flags[ownFlag])`. `dimensionLock` bans only Trick/Magic/Wonder Room; `trickRoom`/`magicRoom`/`wonderRoom` each ban only their own move; every ordinary attack flows to native untouched.

**The rooms at battle start (verified, plus a visible confirmation).** `combat/boss_fight.lua`'s `applyFlags` already wrote `battle.trickRoomActive`/`battle.magicRoomActive`/`battle.wonderRoomActive` and the matching `...Turns = math.huge` the moment the flag was set, so the three permanent rooms were already real and endless -- but SILENTLY, so a boss fight gave no sign they were up and read as "nothing happened". `applyFlags` now also emits the same flavor text casting the move would show ("The dimensions were twisted!" / the Magic Room and Wonder Room lines), guarded on `battle.emit`, so the room is visibly established at battle start.

**All 13 boss flags audited.** Every name in `BOSS_FIGHT_FLAG_NAMES` has a live enforcement site: `sun` (`modern_combat.lua:551/609`), `mistyTerrain` (`modern_terrain.lua:92`), `statsDrop` (`modern_combat.lua:1169`, `modern_movepool_stages.lua:359`, `modern_stat_manipulation.lua:294`), `type` (`type_override_primitives.lua:218`), `ability` (`ability_dispatch.lua:176`), `hardStatus`/`softStatus`/`antiDrain` (`boss_fight_status.lua:135/144/168/195`, plus `modern_movepool_status.lua:115` and `max_move_subeffects.lua:363`), `healblock` (`heal_block.lua:79`), and the four dimension flags (`trick_room.lua`). No flag is declared-but-dead.

**Verified.** Two fengari probes against the real booted engine (`scratch/sim/probe_bossflags.lua`, `scratch/sim/probe_bossflags_rooms.lua`): with all four dimension flags set, TACKLE/FLAMETHROWER reach `native-use-move` on BOTH sides while TRICKROOM/MAGICROOM/WONDERROOM still fail; the three rooms set `*Active=true` + `*Turns=math.huge` at apply time, survive 60x `battle.turn_ended`, keep normal moves flowing, re-apply Wonder Room's per-mon swap on a switch-in and clear it on `battle.ended`; Trick Room reverses turn order (enemy at speed 10 before player at speed 100); Magic Room's `heldEffect` returns nil while up. Boot 143/143, 0 guarded failures. `luaparse 5.1` clean on both edited files.

**Version / live.** Engine project **4.1.0 -> 4.1.1** (written back to the studio kv). The user must re-export `mods/g9-battle-engine`.


2026-09-17 round one-hundred-sixty-eight — user: "protect requires target pokemon in double + battles which is undesired (regression) ... dynamax/gigantamax can be flinched, should be immune to flinch and all form of status ... leech seed prior to dynamax stays and deals damage based on dynamax hp, but can't receive new leech seed after dynamaxed ... after that check thoroughly all setting moves/field states (entry hazards, terrains, weathers, the 3 rooms) — terrain was only affecting pokemon on field while it was casted, it should affect pokemon that enter field and be cleaned from pokemon that leave it." — **Protect-in-doubles no longer asks for a target, Dynamax/Gigantamax are now immune to flinch and every status, new Leech Seed can't root a Dynamaxed mon (an existing seed still drains), and the field-state audit found the one real per-mon gap (Mimicry/Forecast only reapplied to the lead pair) is now N-way** (engine 4.1.1 -> 4.1.2).

**1. Protect (and every self/ally/no-target move) in doubles.** `combat/move_targeting.lua` gained `mod.exports.needsTargetChoice(moveId)` — true only for the archetypes that actually need a picked opponent (`selected-pokemon`, `selected-pokemon-me-first`, `ally`, `user-or-ally`), false for `self`/`user`/`adjacent-ally`/`all`/no-target moves. `g9-Battle-Scene`'s `Screen:needsTargetChoice(picked)` prefers that export (falling back to `picked.def.target`), and `updateMoveSelect` now queues the move immediately (`aliveEnemies[1] or candidates[1]`) when it is false instead of opening the target cursor. This restores the prior guard behaviour for Protect/Detect/Endure/Kings Shield and similar.

**2. Dynamax/Gigantamax immunity.** New canonical `mod.exports.isDynamaxed(mon)` in `gigantamax/dynamax_battle.lua` (reads `mon.__g9Dynamaxed` then `mon.mon.__g9Dynamaxed`). `abilities/engine/status_immunity.lua`'s `hasStatusImmunity` early-returns true for a Dynamaxed mon (blocks every status, including ones that bypass type/ability immunity). `abilities/engine/hit_taken.lua`'s `setFlinched` early-returns for a Dynamaxed mon, so every flinch rider routes through the one gate: STENCH (`inflict_status.lua`), Fling (`combat/modern_items.lua`), King's Rock (`combat/modern_gen1_held_items.lua`).

**3. Leech Seed under Dynamax.** `combat/modern_status_volatiles.lua`'s `GALAR_LEECHSEED_EFFECT.run` bails (`return {}`) when `isDynamaxed(n.target)`, so a new seed can't be applied to a Dynamaxed mon. The residual tick is untouched, so a seed applied *before* Dynamaxing persists and keeps draining — and per `battle_forms/src/hpscale.lua` ("STATUS RESIDUALS ARE DELIBERATELY UNSCALED ... the same fraction lost"), the drain staying 1/8 of the base `stats.hp` is the intended relative-fraction behaviour.

**4. Field-state audit (thorough).** Grepped all 218 files. **Terrain is fully stateless/live** — `combat/modern_terrain.lua` computes each mon's effect on demand via `affectedByTerrain` (grounded from live `curTypesOf` + `gravityGrounded`, non-semi-invulnerable); there is NO per-mon terrain stamp anywhere, so terrain already affects mons that switch in and stops on mons that leave. **Entry hazards** (`modern_hazards.lua` `battle.battler_switched` on `ev.battler`, side via N-way `Battle:sideOf`), **weather** (global + `g9.weather_changed`), **Gravity** (`modern_field_effects.lua` switch handler + `applyGravityToActives`), and the **3 rooms** (`trick_room.lua`: Trick/Magic are battle flags; Wonder Room re-applies per-mon on switch-in and clears on `ev.previous`, all N-way) were already switch-in-aware. The one genuine per-mon gap was that **Mimicry** (`abilities/engine/mimicry_terrain.lua`) and **Forecast** (`abilities/engine/forecast_weather.lua`) only reapplied to the lead pair — their `reapplyBothSides` now iterates `allActiveBattlers` (N-way), which is exactly the "terrain only affected mons on field at cast" symptom.

**Verified.** New `scratch/sim/sim_fieldstates.lua` battery (~65 checks, 11 sections: needsTargetChoice, allActiveBattlers N-way, Misty/Grassy switch-in, Mimicry N-way + switch-in, Forecast N-way + switch-in, Stealth Rock switch-in, Gravity apply/clear, Wonder Room apply/clear, Trick/Magic flags, Dynamax no-flinch / all-status-immune / new-leech-blocked / pre-seed drains). Full harness: `ok:true, fileCount:218, loadedCount:143, failedCount:0, simError:null`, every battery `failCount:0`. `luaparse 5.1` + scope/globals clean on all 10 edited engine files and `battle_screen.lua`. `mods/g9-Battle-Scene` bumped 3.0.1 -> 3.0.2 and rezipped (237,088 B, 26 entries) via `scratch/build-scene-zip.js`.

**Version / live.** Engine project **4.1.1 -> 4.1.2** (written back to the studio kv). The user must re-export `mods/g9-battle-engine` and `mods/g9-Battle-Scene`.

2026-09-17 round one-hundred-sixty-nine — user: "before version update and remains after version update, error for gen 1 exclusively when player uses protect move" (crash screenshot: `mods/g9-battle-engine-beta/combat/modern_combat_protect.lua:122: attempt to index local 'user' (a nil value)`) — **the Protect family (Protect/Detect/Endure/Kings Shield, Max Guard) no longer crashes Gen 1: the effect handlers are now dual-engine (they normalize whichever calling convention the engine uses), and an incoming pure-status move is blocked against a protected target under Gen 1 the same way it already was under Gen 2** (engine 4.1.2 -> 4.1.3).

**Root cause.** `manifest.json` declares `"games": ["gen1","gen2"]`, but `combat/modern_combat_protect.lua`'s three `run` handlers were written for Gen 2's positional convention only: `run(battle, user, defender, def, moveId, sureHit)`. Gen 2's `Battle:useMove` calls a move effect as `record.run(battle, attacker, target, ...)` and the handler emits via `battle:emit`. Gen 1's `BattleState:performMove` (`:4350`) instead builds ONE ctx table (`EffectRegistry.makeCtx`, `:37`) and calls `record.run(ctx)`, then PRINTS the returned message array — so the handler's first parameter received the ctx table (bound to `battle`) and `user` was nil, and `rollStall`/`armStallChain` dereferenced `user.protectChainTurn` -> the nil index at line 122 on the very first Protect. Gen 2 never hit it because `defender` is passed positionally there.

**The fix (one normalizer, both engines).** New `local function ctxOf(a,b,c,d,e)`: if `a` is a table with `a.battle ~= nil` (the Gen 1 ctx shape) it returns `{battle=a.battle, user=a.user, target=a.target, gen2=false, ctx=a, moveId=a.moveInst and a.moveInst.id or a.move}`; otherwise `{battle=a, user=b, target=c, gen2=true, def=d, moveId=e}` (Gen 2 positional). All three handlers are now `run = function(a,b,c,d,e)` -> `ctxOf(...)`, so one body serves both engines. Supporting dual helpers: `nameOf`/`nameB` (Gen 2 `battle:monName` vs Gen 1 `mod.exports.displayNameFor`), `say`/`sayB` (Gen 1 appends to the returned array; Gen 2 `battle:emit`), `battleTurnOf` (`battle.turn` vs `battle.turnCount`), `rollOneIn` (`battle.roller` -> `battle:roller()(x) == 0`, else `battle.rng(1,x) == 1`). Success sets `user.protected` / `maxGuarded` / `protectShield = moveId`; the failure path returns the array with `failed = true` on Gen 1 ("But it failed!") and emits on Gen 2. ENDURE's native `n.battle:volatile(n.user).endure = true` is now Gen-2-only (Gen 1 has no such volatile — its own `BattleState` handles endure natively). `applyShieldRider` is gen-aware too: guarded `battle.changeStageAgainstMist`, `battle.applyStatus` (else `StatusRegistry.inflict(battle, attacker, rider.status, {source=shieldOwner})`), dual name/message helpers, and `battleTurnOf`.

**New Part D (Gen 1) — blocking an incoming pure-status move.** Gen 2's Part D (in `if Battle then`) swaps `Battle.moveEffectRecordFor` around one `Battle:useMove`; Gen 1 has neither `Battle:useMove` nor a class-level record lookup, so a symmetric wrap was added around `BattleState:performMove`. When `target ~= user`, the target is `protected` (or `maxGuarded`), the move is `power == 0` and not `bypassesProtect`, and the real record is a plain `kind == "primary"` with no `perform`/`callsMove`/`chooseDamage`/`charge`, it temporarily replaces the instance lookup (`self.effectRecord = function(bs, effect) if effect == move.effect then return standin end return nativeEffectRecord(bs, effect) end`, saving and restoring the previous `rawget(self,"effectRecord")` around a `pcall` of the captured native) with a stand-in whose `run` fires the shield's contact rider via `applyShieldRider` and returns `Strings("It doesn't affect\n%s!", nameB(self,target))` with `failed = true`. PP decrement, the "X used Y!" announcement and charge/accuracy handling are all left to the untouched native.

**Verified.** NEW `scratch/sim/probe_protect_partd.lua` drives the REAL wrapper chain (the harness stubs `src.battle.BattleState`, so `interaction_memory.lua`'s own performMove wrap captured a nil native; the probe repairs that one upvalue to a minimal in-Lua native, then calls through every installed layer): a protected target gets the "It doesn't affect\nDefender!" stand-in with the real effect NOT run; `maxGuarded` likewise; an unprotected target and a `bypassesProtect` move both reach the real effect; and a blocked call followed by an unprotected call through the SAME instance runs the real effect the second time, proving the lookup is restored. `scratch/sim/probe_protect_gen1.lua` (handlers) — all pass: Gen 1 Protect returns a table, sets `protected`, prints "User protected itself!" and starts the chain; a consecutive Protect fails and clears the chain; a turn gap resets it; Gen 1 Endure and Max Guard return without crashing; Part B blocks a Gen 1 damaging move (dmg 0, typeMult 0); a self-target is not blocked; the Gen 2 handlers are unchanged. Full harness `ok:true`, 143/143 subsystems, `failedCount:0`, and all 11 batteries (253 checks) pass. `luaparse 5.1` + scope/globals clean on `combat/modern_combat_protect.lua` (44,803 B). Harness scaffold: `scratch/harness.js`'s `src.battle.BattleState` stub gained an inert `effectRecord` (the real Gen-1 `BattleState` has `:2687 effectRecord`; without it the new Gen-1 wrap silently never installs in-harness — exactly the blind spot the crash lived in).

**Version / live.** Engine project **4.1.2 -> 4.1.3** (written back to the studio kv). The user must re-export `mods/g9-battle-engine`; the scene build is unchanged this round.


2026-09-18 round one-hundred-seventy-six — user: "did you update battle engine for move screen changes? THIS IS where the TRAIN and its move window should MUST live. DO NOT CHANGE IT AGAIN." — **the TRAIN party-submenu editor now lives IN THE ENGINE (moved out of g9-battle-sample), gated behind a new TRAIN SCREEN Mod Manager row (default ON)** (engine 4.1.3 -> 4.2.0).

**What moved.** The whole TRAIN screen -- stats page one (IV / EV / Nature / gender with per-point fees, APPLY) and screen two (the MOVES editor: Egg / Relearn / Tutor moves at 5000 each, forget-slot prompt, HM refusal) -- was installed by g9-battle-sample's main.lua since 2026-09-14. It is now `stats/train_screen.lua` in the engine, booted by main.lua right after adv.stats, and g9-battle-sample no longer installs it. The engine is genuinely its home: it edits this mod's OWN modern stats through `ModernStats.recalcAll` (the same function `stats/ev_yield_on_faint.lua` uses), filters moves through this mod's own `mod.exports.isMoveUsable`, and both generations' party submenu is already hooked by `stats/dev_stats_screen.lua` with the identical {id,label,onSelect} descriptor shape.

**The row.** New `options.lua` row `key = "train_screen"`, label **TRAIN SCREEN**, type `choice`, **default `"true"`**. The gate is read lazily inside the `ui.party.submenu` wrap (`mod.options:get("train_screen") == "true"`), the same idiom adv.stats uses, so it is correct even though the schema is defined later in main.lua's `debug_options` boot. OFF returns the submenu untouched.

**Adaptations.** The moved file drops the cross-mod lookup (`mod.find("g9-battle-engine")`) and reads `mod.exports.ModernStats` directly; it derives the generation itself from `GameVersion.generation(GameVersion.get())` (was passed in by the sample's arm chooser); and the round-175 per-frame "clip guard" (`Renderer:setUISize` + `love.graphics.setCanvas` inside `Screen:draw`) is REMOVED. That guard is the silent-crash hazard `stats/dev_stats_screen.lua`'s own header documents -- a state must only ever answer `Screen:uiSize()` and let `Game:draw` size the surface, exactly as adv.stats and modern_stats_screen do. MOVES keeps its enlarged 240x216 window; STATS keeps its proven 192x173 (Gen 1) / 160x144 (Gen 2) window.

**Verified.** luaparse 5.1 clean on `stats/train_screen.lua` (45,979 B), `main.lua`, and `options.lua`; manifest valid JSON at 4.2.0. Project written back to the studio kv (`project.v` 68 -> 69). The user must re-export `mods/g9-battle-engine` (4.2.0) and `mods/g9-battle-sample` (0.9.8, which no longer carries TRAIN).


2026-09-18 round one-hundred-seventy-seven — user: "gender was fixed, but you are NOT respecting my instructions, you broke screen size for MOVE screen and blacklist... you need to respect screen 960x540 resolution 16:9. reduce font size and redesign the GUI frames and other assets in it to fit neatly the proper screens." — **the TRAIN screen's MOVES page is now a 320x180 (16:9) window that works on Gold again, with a two-column move list and a category header that names the list it shows** (engine 4.2.0 -> 4.3.0).

**Why the MOVES page broke on Gold.** `src/core/Game2.lua` composes the window itself and NEVER reads a state's `uiSize()` and never calls `Renderer:setUISize` -- only Gen 1's `Game:draw` does that (`src/core/Game.lua:654-662`). A screen larger than 160x144 on Gen 2 must instead publish that generation's own contract. The round-176 MOVES page answered only `uiSize()`, so on Gold it was clipped to the classic 160x144: the list cut mid-name, the money/hints off the edges, and nothing appeared selectable.

**The window.** MOVES is now **320x180** -- `960/320` and `540/180` are both exactly 3, so the game's native **960x540** window is an integer **3x** with no letterbox and every 8px frame and glyph on the grid. A new tiled `drawBorder(w,h)` helper draws the native window ring from `Font.BORDER` codes, because `Font.drawBox` takes whole TILE counts and would put its bottom row at y=168 and leave a 4px gap down a 22.5-tile height. The MOVES page layout was re-flowed into two columns of nine rows (18 move names of 16 glyphs each) -- the classic 160-wide window could not fit even one 11-glyph name in its eight rows.

**The Gen 2 seam.** `Screen:drawsWidescreen()` + `Screen:drawWidescreen(winW,winH)` + `Screen:panelSize()` + `Screen:battlePanelScale()` + `Screen:panelScale()` + `Screen.letterboxWhite` -- the same contract `src/ui/gen2/BattleState.lua`, `PartyMenu` and `WideBattle.draw` use (letterbox paper, `Chrome.fitOriginFor`, push/translate/scale, draw). Gen 1's `uiSize()`/`isWideBattleLayout` path is unchanged; both seams answer from the SAME sizes, so one layout serves both generations.

**The header bug.** `MOVE_FIELD_LABELS` read `{ EGG, RELEARN, TUTOR }` while `buildMoveList` reads category 1 = relearn/level-up, 2 = egg, 3 = tutor -- so the header said EGG over a list of level-up moves. It now reads `{ RELEARN, EGG, TUTOR }`.

**On "reduce font size".** The engine's tile font is a fixed 8px grid (the PlainPixel TTF is 15px, i.e. larger -- there is no smaller font to switch to). The much larger canvas is what makes the text far smaller relative to the screen, which is the visual result that was asked for; no font was actually changed.

**Coordinate scale.** The MOVES page draws in its own raw pixels (S = 1 there); the STATS page keeps its per-generation window and its design scale untouched.

**Verified.** `luaparse 5.1` clean on `stats/train_screen.lua` (52,127 B, 1,261 lines). The fengari harness boots the real engine **144/144 on BOTH generations**, 0 guarded failures.

**Version / live.** Engine project **4.2.0 -> 4.3.0** (written back to the studio kv). The user must re-export `mods/g9-battle-engine` (4.3.0); the BLACKLIST's matching fix ships with `g9-battle-sample` 0.9.9.


2026-09-18 round one-hundred-seventy-eight — user: "moves list screen in train (battle engine) STILL SHOWS NO SELECTION ARROW to indicate on which move the player cursor is at." — **the TRAIN MOVES page now draws the engine's own cursor TILE, so the selected move finally shows a visible arrow** (engine 4.3.0 -> 4.3.1).

**Why there was no arrow.** The cursor was `cell(">", x, y)` -- the ASCII `>` character. The engine's charmap has NO `>` entry, and `Font.split` hands a single character the charmap misses to the TTF the renderer substitutes for tile glyphs (the bundled Plain Pixel), which has no `>` either -- so `Font.encode` fell through to a space and the page drew a blank cell exactly where the cursor should be. The row/column arithmetic was never wrong; the glyph was.

**The fix.** A `cursor(x, y)` helper draws code **`0xED`** through `Font.drawCode` -- charmap.asm $ED, the filled right arrow BOTH generations' tile sheets carry, and the same code the engine's own cursors use (`src/ui/Theme.lua` `cursor`, `src/ui/gen2/Chrome.lua` `CURSOR`, `src/ui/MoveSelectMenu.lua` / `MoveLearnMenu.lua`, `WideBattle.lua`). Both the two-column move-list cursor and the forget-a-slot prompt's cursor now use it. Drawn by CODE deliberately, so it resolves to the tile page whatever a font/charmap replacement does to the ASCII range.

**Verified.** The fengari geometry harness (`scratch/sim/run-train-render.js`, now also reporting arrow tiles) records every draw primitive: the main list paints a code-237 tile at the cursor's own cell (164,48 for the two-column layout) and the forget prompt at (74,82), and NO `>` text primitive is drawn anywhere. The rendered page was read back with vision: a black right-pointing triangle sits immediately left of the cursor row, no grey unrendered tiles, nothing clipped. Bounds: 153 / 162 / 140 primitives (list / forget / price), all inside the 320x180 surface and the 8px ring. `luaparse`-free plain Lua; the module still compiles and the harness drives its navigation.

**Version / live.** Engine project **4.3.0 -> 4.3.1** (written back to the studio kv, `project.v` 71 -> 72). The user must re-export `mods/g9-battle-engine` (4.3.1); the BLACKLIST's matching LEFT/RIGHT navigation ships with `g9-battle-sample` 0.9.10.


2026-09-17 round one-hundred-seventy-nine — user: "battle engine issues, transform in gen and subsequently (risk by similarity of mechanics) imposter ability and illusion ability might not work in gen 1 exactly as they should: transform passes in gen 1 but doesn't change's pokemon's sprite into target's sprite (must). illusion differential: illusion transforms into last pokemon of team's placement and doesn't copy stats, by pokemon showdown, when wild illusion holder pokemon enters battle, box E announces it as the pokemon comes disguised as any other pokemon valid for the area's spawn table (never itself). transform and imposter copy real final stats (modern stats = BST with EV IV and nature effects + any stat stage change, use pokemon showdown reference to re-verify this). player encountered this error and suspects it's linked to transform move (see attachment) but it seems odd as it doesn't list any of our mods to what I can tell." — **Gen-1 Transform now truly becomes the target (its sprite and its real modern stats plus both stat-stage stores), Illusion disguises exactly as Pokémon Showdown does (last party member, or a wild area's spawn-table species that is never itself, with no stat copy and box E announcing the disguise), Imposter transforms on switch-in, and the reported crash is proven NOT to be Transform but a mod-side move-effect handler returning nil** (engine 4.3.1 -> 4.4.0).

**Two new files, booted last (Phase G in main.lua).** `combat/modern_transform.lua` owns Transform / Imposter / Illusion. `combat/modern_effect_guard.lua` boots immediately after it and makes the engine's move-effect dispatch crash-proof for EVERY record. Order is load-bearing: modern_transform patches `BattleState:effectRecord` for `TRANSFORM_EFFECT`; the guard then captures that patched lookup as its native and wraps it once more, so the transformed record's `run` gets the guard's nil/error normalization as the outermost layer and every other record gets it directly.

**(A) Transform now changes the sprite.** `setDisplay` records `__g9DisplaySpecies` and bakes that species' frames into `battler.sprite`. Because g9-battle-sprites rebuilds `battler.sprite` from `mon.species` every frame, that alone would be clobbered; the fix is a runtime-installed OUTERMOST `BattleState.drawPicsLayer` wrapper (installed lazily on the first display use, i.e. after every mod has booted) that temporarily points `self.player.mon.species` / `self.enemy.mon.species` at `__g9DisplaySpecies` for the length of the inner layer, then restores them in a `pcall`.

**(C) Transform + Imposter copy the real final stats.** `applyTransform` copies every key of `target.curStats` except `hp` (which stays the user's own max), the target's types, BOTH stat-stage stores (the native `battler.stages` bucket and `modern_combat`'s per-mon stage bucket), and `curMoves` (`pp=5, mimic=true`); it sets `transformed` on both the battler and `mon`. This is the Showdown `transformInto` behaviour re-checked against `scratch/showdown/pokemon.ts:1270`.

**(B) Illusion per Showdown.** `setupIllusion` disguises as the LAST non-fainted party member AFTER the holder (player and trainer-enemy sides) or, for a WILD holder, as a random species drawn from the current map's `data.encounters[...]` grass+water slots, deduped and never the holder's own species (no pool => no illusion). It sets the display species/name/sprite and the `__g9IllusionActive` flag and copies NO stats. `runSwitchInAbilities` is Illusion-else-Imposter; the `newWild`/`newTrainer` wraps also rebuild `introText`, so box E announces the disguise. Illusion breaks on an actual HP drop (a `runDamaging` wrap), on switch-out, on faint, and is cleared at battle end.

**(D) The crash is not Transform.** The attachment's error is `BattleState:...ipairs(msgs)` receiving nil from a mod move-effect handler that returned nothing. `modern_effect_guard.lua` `protectMoveEffectRecord` `pcall`-wraps and normalizes every record's `run` (nil/non-table -> `{}`, an error -> `{failed=true}`, warn-once per id). It also installs three Gen-1-only shims, each only if missing: `BattleState:emit`, `BattleState:monName`, `BattleState:volatile`. This is the universal fix for the whole family of "mod effect handler returns nil" crashes on Gen 1. `abilities/data/form_change_scope.lua` prose corrected (ILLUSION/IMPOSTER are wired here, not by battle_forms).

**Verified.** `scratch/sim/probe_effectrun.lua` goes from 127 T / 44 NIL / 21 ERR to **192 T / 0 NIL / 0 ERR**. NEW `scratch/sim/probe_transforms.lua` asserts the draw-time species swap, the full-stat copy (attack 200 / spa 180 / spd 170 / speed 190 copied, hp kept, no aliasing), both stage stores, the gates, the record path, and all Illusion cases (party last-member, all-fainted, last-member-none, wild spawn-table, never-self, only-self). The fengari harness boots **146/146, 0 guarded failures** (144 -> 146). `luaparse` 5.1 clean on all edited/new files. Two harness self-checks (`foulPlayReadsTargetAtk`/`foulPlayTargetStage` in round72 and `ldRestoresPp` in round74) fail identically with Phase G stripped, i.e. pre-existing and unrelated.

**Version / live.** Engine project **4.3.1 -> 4.4.0** (written back to the studio kv). The user must re-export `mods/g9-battle-engine` (4.4.0).

2026-09-18 round one-hundred-eighty — user: "foulplay doesn't work? yes no answer" — **Foul Play (and every other modern PHYSICAL move whose type is Special-by-default in Gen 2/3) was computing damage from the wrong stat pair; the move's own damage-source override was fine, the category resolution underneath it was not** (engine 4.4.0 -> 4.4.1).

**Root cause.** `combat/engine_move_category.lua`'s `MoveCategory.of` accepted only the Capitalised category spellings ("Physical"/"Special"/"Status"). national_dex's generated registry (and `gigantamax/gmax_moves.lua`) spells the field lower-case ("physical"/"special"/"status"), so EVERY lower-case record fell through to the Gen 2/3 type-based split in `src/battle/TypeChart.lua` -- where DARK, FIRE, WATER, GRASS, ELECTRIC, PSYCHIC, ICE and DRAGON are all Special. Any modern physical move of those types (Foul Play, Crunch, Bite, Knock Off, Sucker Punch, Fire Fang, Waterfall, Leaf Blade, Wild Charge, Zen Headbutt, Ice Punch, Dragon Claw, ...) therefore ran with Sp. Atk vs Sp. Def instead of Attack vs Defense; Foul Play additionally read the TARGET's Sp. Atk. Foul Play was the visible symptom, not the cause: its `ctx.target` damage-source override really was applied -- the stat pair it was fed was wrong. SummaryMenu's displayed category for those moves was wrong too.

**The fix.** `MoveCategory.of` now reads `moveDef.category` with a fallback to `moveDef.damageClass`, lower-cases the value, and returns "Physical"/"Special"/"Status" for "physical"/"special"/"status" BEFORE the type-split fallback -- so a move carrying its own category is always authoritative and both spellings (and either field name) are accepted. Native Gen 1 moves, which carry no category field at all, still resolve via type/power exactly as before. The round-83 `category == "Status"` note in `combat/modern_combat.lua` was rewritten to describe that path as a belt-and-braces fallback rather than the primary resolver (comment only, no behaviour change).

**Verified.** The fengari harness `__runAll()` boots `ok:true`, `loadedCount:146`, `failedCount:0`; the round-72 self-checks now read `foulPlayReadsTargetAtk=ok foulPlayTargetStage=ok foulPlayIgnoresUserStage=ok foulPlayNotUserAtk=ok` (2 of those were FAILs before this round). The full `scratch/sim` battery suite runs with `simError:null` and no real failures. NEW probe `scratch/sim/probe_foulplay.lua` reports `foulPlay=85, control=85, userAtk=22, bodyPress=72`, proving the target-Attack override and the corrected stat read both land (the wrong stat pair produced a different number). `luaparse 5.1` clean on both edited files. The only remaining self-check failure is the pre-existing, unrelated `round74 ldRestoresPp=FAIL`.

**Version / live.** Engine project **4.4.0 -> 4.4.1** (written back to the studio kv, `project.v` 73 -> 74). The user must re-export `mods/g9-battle-engine` (4.4.1).

2026-09-19 round one-hundred-eighty-one — user: "sprite and name replacement of transform is still failing for gen 1, review if battle sprite or battle scene needs awareness of it" — **the mod that needed awareness was the battle SCENE, not the sprite pack: `g9-Battle-Scene` resolves every battle pic and HUD name from the MON and never calls `drawPicsLayer`, so the round-179 display override (held on the engine battler) could not reach it** (engine 4.4.1 -> 4.4.2 + `g9-Battle-Scene` 3.0.4 -> 3.0.5).

**Why it was still failing on Gen 1.** Round 179 fixed the native path: `combat/modern_transform.lua` records `__g9DisplaySpecies` on the engine BATTLE and installs an outermost `BattleState:drawPicsLayer` wrapper that points `mon.species` at it for the length of one draw. That works for the game's own screen. But `g9-Battle-Scene` never draws through `drawPicsLayer` — its `Screen` builds its OWN battler wrappers (`combat.lua`'s `newBattler` returns `{ mon = mon, side = ... }`, keeping only the shared `mon`) and `resolveSprite` resolves the file from `data.pokemon[mon.species]` plus the `pokemon.sprite` / `battle.mon_pic` seams, while `displayName(mon)` reads `mon.nickname or mon.name or mon.species`. So it read the REAL species and the REAL name: the engine's override was on a battler object the scene had never seen, and both the Transform sprite and its name stayed invisible.

**The fix — two files, two halves.**
- **Engine (`combat/modern_transform.lua`).** `setDisplay` now mirrors the override onto the MON as well (`mon.__g9DisplaySpecies`, and `mon.__g9DisplayName` when a display name is given); `clearDisplay` clears both mon fields alongside the battler ones; `applyTransform` now passes the target's name (`monNameOf(target)`) into `setDisplay`, so Transform records a NAME too. Real Gen 1 does not rename on Transform (`transform.asm` copies species/types/moves/DVs/stats, never the nickname) and native `TRANSFORM_EFFECT` swaps only the pic — this is a deliberate departure to satisfy the user's literal ask ("sprite and name replacement"), noted in the file header.
- **Scene (`src/g9-Battle-Scene/battle_screen.lua`).** `displayName(mon)` now prefers `mon.__g9DisplayName`, so the HUD name and every scene message (intro, "sent out", switch, faint reasons) follow the override. `resolveSprite` now computes `shown = battler.__g9DisplaySpecies or mon.__g9DisplaySpecies or mon.species`, uses it for `data.pokemon[shown]` and for BOTH seam ctxs' `species`, and raises those seams with `mon.species` temporarily set to `shown` (a new `withShownSpecies` pcall guard restores the real species immediately, error or not) — because the sprite pack keys its sheet off `mon.species` (`monStem` -> `resolveStem(mon.species)`). `g9-battle-sprites` therefore needs NO change: the scene hands it the display species.

**Verified.** `luaparse 5.1` clean on the edited engine, scene and probe files. The fengari harness boots **146/146, 0 guarded failures**. `scratch/sim/probe_transforms.lua` gains round-181 assertions — all green: after Transform `mon.__g9DisplaySpecies == "MEWTWO"` and `mon.__g9DisplayName == "Mewtwo"` (the scene's own two expressions, `displayName` and `resolveSprite`'s `shown`, evaluated verbatim against a scene-shaped `{ mon = ... }` wrapper), the real species/name are intact after `clearBattlerDisplay`, and Illusion mirrors `mon.__g9DisplaySpecies`/`mon.__g9DisplayName` and clears them. Every round-179 check still passes (draw-time swap, full stat copy, gates, record path, all Illusion cases).

**Version / live.** Engine project **4.4.1 -> 4.4.2** and `g9-Battle-Scene` **3.0.4 -> 3.0.5** (engine written back to the studio kv, `project.v` 74 -> 75). The user must re-export `mods/g9-battle-engine` (4.4.2) AND `mods/g9-Battle-Scene` (3.0.5); `g9-battle-sprites` is unchanged.

2026-09-20 round one-hundred-eighty-two — user: "transform is happening quicker than priority moves despite transformation message showing correctly after the priority move, in resolve order, the actual sprite and stat replacement should happen after the priority, not before. also make sure pokemon isn't copying target's hp, HP should always be of transformation's / imposter ability's user" — **the Gen-1 turn was being resolved in ONE synchronous pass, so the Transform's sprite/stat exchange was committed at t=0 — before any actor's events had been displayed — even though the message order was already right; the scene now resolves one action per pass and displays that action before resolving the next, and a Transform/Imposter mon can no longer pick up the target's HP** (engine 4.4.2 -> 4.4.3 + `g9-Battle-Scene` 3.0.5 -> 3.0.6).

**Root cause.** In a scene-driven Gen 1 battle the SCENE called `self.combat.resolveTurn(...)` once for the whole turn, and that ran every actor's `battle:useMove` back to back. `modern_transform.lua`'s `TRANSFORM_EFFECT` therefore fired during the FIRST action's resolution -- long before the scene displayed anything -- so the sprite/stat replacement was already committed when the higher-priority move's animation played. The event LOG order was correct; the STATE was applied up front.

**The fix -- Gen-1 stepwise turn resolution.**
- `combat/turn_order.lua`: the Gen-1 path is split into `beginTurnActionsForGen1(battle, actingBattlers)` (builds the same `computeTurnOrder` list, stores `battle.__g9Gen1Order` + `battle.__g9Gen1OrderCursor = 1`), `resolveNextActionForGen1(battle)` (advances the cursor, skips dead actors, falls back to `gen1AliveOpponent`, runs `battle:useMove`, returns true; returns false and clears both fields when exhausted), and the original `resolveTurnActionsForGen1` is now a thin batch wrapper over the two -- so every existing caller and algorithm stays byte-equivalent.
- `src/g9-Battle-Scene/combat.lua` + `native.lua` + `battle_screen.lua`: `Combat.beginTurn`/`Combat.resolveNextAction` and `N.beginTurn`/`N.resolveNextAction` were added (Gen-1 arm only), and `Screen:advanceResolving` now resolves ONE action per pass, queues that action's events, displays them, and recurses until the cursor is exhausted before awarding faint EXP and ending the turn. `Screen:awardFaintExp` factors out the former inline EXP block so both paths share it. Gen 2 never gets `N.beginTurn`, so `Combat.beginTurn` returns false and the original whole-turn batch path is used, unchanged.

**(b) HP ownership.** `applyTransform`'s stat copy now reads only `user.mon.stats.hp` (then `mon.maxHp`/`mon.hp`) for the user's own max, filters `hp`/`maxHp`/`hpMax` out of the copied target `curStats` table, and re-stamps `dst.hp = maxHp` after the copy. Target HP was already never copied, but the HP key aliases are now explicitly excluded and the user's current `mon.hp` is never touched, so a Transform/Imposter mon always keeps its own HP.

**Verified.** `luaparse 5.1` clean on all five changed files. The fengari harness boots **146/146, 0 guarded failures**. NEW `scratch/sim/probe_stepturn.lua` asserts the interleaving (`QUICK_ATTACK` alone after step 1 with the transform not yet applied; `QUICK_ATTACK,TRANSFORM` after step 2 with it applied; the cursor cleared on exhaustion; the batch wrapper identical; a KO'd actor skipped without stalling) and the HP block (`hp_current_unchanged`, `hp_curstats_is_user_max`, `hp_attack_copied`, `hp_user_stats_untouched`, `hp_no_hp_alias_keys`). `scratch/sim/probe_gen1_preturn.lua` (which loads the real scene `native.lua`) gains round-182 sections: begin/step/skip-dead/end-of-turn all correct, and the no-begin fallback clears flinches exactly once. `scratch/sim/probe_transforms.lua` still passes with every round-179/181 check green.

**Version / live.** Engine project **4.4.2 -> 4.4.3** and `g9-Battle-Scene` **3.0.5 -> 3.0.6** (engine written back to the studio kv, `project.v` 75 -> 76). The user must re-export BOTH `mods/g9-battle-engine` (4.4.3) AND `mods/g9-Battle-Scene` (3.0.6); `g9-battle-sprites` is unchanged.

2026-09-20 round one-hundred-eighty-three — user: "transform is changing name of pokemon/nickname of pokemon, it shouldn't, also, make sure that we only use the copied stats for the current battle and the pokemon recovers its own stats (base stats, sprite, nature, IV, EVs, etc) after battle or another pokemon replaces them 'switched out' (aka another pokemon switches in into their spot in battle), or they faint. reminder that this is for both transform and imposter ability" — **Transform no longer renames (the round-181 rename is reverted; only the sprite follows), and a Transform/Imposter's copied stats/types/moves/stages are now snapshotted pre-transform and fully restored on switch-out, faint and battle end, for both Transform and Imposter** (engine 4.4.3 -> 4.4.4; scene unchanged at 3.0.6).

**(a) No name change.** Round 181 passed `monNameOf(target)` into `setDisplay`, so `applyTransform` set `battler.name` and `mon.__g9DisplayName` to the target's name — a deliberate departure to satisfy the earlier "sprite and name replacement" ask. The user reports it as a defect and it should not happen: `applyTransform` now calls `setDisplay(battle, user, shown, nil, { gray = true })`, so `battler.name`, `mon.__g9DisplayName` and the real nickname are all left alone. Native Gen 1 agrees (transform.asm copies no nickname and native swaps only the pic). An Illusion still announces its disguise by name — a different mechanic, and `setDisplay`'s `displayName ~= nil` branch is exactly what `setupIllusion` uses.

**(b) Battle-scoped copy + revert — the real bug.** `curStats`/`curTypes`/`curMoves`/`stages` were copied at transform time and never put back. A NATIVE battle reverts by itself: its switch/faint path builds a FRESH battler through `BattleState.makeBattler`, which rebuilds `curStats` from `mon.stats`, `curTypes` from `def.types` and `curMoves` from `mon.moves`. But `g9-Battle-Scene` does not — its `native.lua` caches ONE engine battler per mon in `state.battlersByMon` and reuses it whenever that mon is on the field again, so a mon that switched out and came back kept the copied stat table, types, moves and stages (and the gray sprite). `applyTransform` now snapshots the mon's own pre-transform fields the FIRST time it transforms and `revertTransform` restores them.

- **Snapshot.** `snapshotTransform(battle, user)` records `{ battler, curStats, curTypes, curMoves, stages, stagesModern }` on `mon.__g9TransformPre` (idempotent: a re-transform before switching out keeps the ORIGINAL pre-state). `stagesModern` is a COPY of `mod.exports.stagesFor(battle, user)`'s persistent bucket, which `applyTransform` mutates in place.
- **Ordering.** On the move-record path the native `TRANSFORM_EFFECT.run` reassigns `user.curStats`/`curTypes`/`curMoves`/`stages` itself, so `patchedTransformRecord` snapshots BEFORE `nativeRun` (then `applyTransform`'s own snapshot is a no-op). The Imposter path (no native record) is covered by the snapshot at the top of `applyTransform`.
- **Revert.** `revertTransform(battle, who)` restores `curStats`/`curTypes`/`curMoves`/`stages`, clears `transformed` (battler + mon), `__g9TransformPre`, the display (`clearDisplay`) and the modern stage bucket, then drops the snapshot. `who` may be a battler or a raw mon.
- **All exits.** `battle.battler_switched` reverts BOTH the outgoing mon (`ev.previous`) and the incoming one (`ev.battler`) — the incoming revert is what makes the reused `battlersByMon` battler start clean; `battle.fainted` reverts too; `battle.ended` reverts the whole roster (actives, both/all party lists, and the scene's `battlersByMon` cache). All three handlers were factored into exported functions (`handleBattlerSwitched`, `handleFainted`, `revertAllMonState`) so they are directly testable. A `battle.started` sweep was deliberately NOT added: `newWild`/`newTrainer` fire Imposter before `battle.started`, so a start-time sweep would wrongly undo it — `battle.ended` is the cross-battle cleanup.
- **Scene payloads are raw mons.** `battle_screen.lua` raises `battle.battler_switched` with the RAW mon (`previous = outgoing.mon`, `battler = action.mon`), and sets `battle.enemy = mon` on an enemy replacement. `clearDisplay`, `clearIllusion` and `runSwitchInAbilities` now normalise through a new `battlerFor(battle, who)` (scene `battlersByMon` -> native pair -> `allActiveBattlers`), and `runSwitchInAbilities` derives the opposing active internally via `opposingOf` when none is passed. This also FIXES a latent gap: Imposter previously never fired on a scene switch-in because the raw mon payload made the old `battler.mon` guard return early.

**Verified.** `luaparse 5.1` clean on the edited engine and probe files. The fengari harness boots **146/146, 0 guarded failures** on BOTH Gen 1 (`reportOnly`) and Gen 2, with every battery clean. NEW `scratch/sim/probe_transform_revert.lua` (all green): no name change but species follows; revert restores stats (identity), types, moves, both stage stores, flags, display; a re-transform keeps the ORIGINAL snapshot; a scene-shaped `battlersByMon` battle restores the reused engine battler on a raw-mon `battler_switched`; Imposter fires through a raw-mon switch-in and reverts; faint and `revertAllMonState` revert; `clearBattlerDisplay` accepts a raw mon; snapshot is idempotent. `scratch/sim/probe_transforms.lua`'s round-181 name assertions are replaced by round-183 ones (Transform leaves the mon's own name/nickname; Illusion still names) with every round-179/181 check still passing. `probe_stepturn.lua`, `probe_gen1_preturn.lua` and `probe_foulplay.lua` all still pass.

**Version / live.** Engine project **4.4.3 -> 4.4.4** (written back to the studio kv, `project.v` 76 -> 77). `g9-Battle-Scene` is **unchanged at 3.0.6** (no scene file touched this round). The user must re-export `mods/g9-battle-engine` (4.4.4); `g9-Battle-Scene` and `g9-battle-sprites` are unchanged.

2026-09-20 round one-hundred-eighty-four — user: "make sure that power and guard split moves effect only stays for battle as they average user's with target's stats" — **Power Split and Guard Split now revert to each mon's own stats on switch-out, faint and battle end; the averaged value lives only while the split is on the field** (engine 4.4.4 -> 4.4.5; scene and sprites unchanged).

**Root cause.** `splitStats` averages the two mons' stored stats IN PLACE (Showdown `powersplit` 13760-13782 / `guardsplit` 7950-7972 both write `Pokemon#storedStats` directly) and never put them back. A native battle would not notice -- its switch/faint path rebuilds a fresh battler from `mon.stats` -- but the write lands on the PARTY MON's own stat table (`curStats` IS `mon.stats` on Gen 1), so the averaged number survived the fight and rode into the save. `g9-Battle-Scene` additionally caches one engine battler per mon, so even a switch-out did not clear it.

**The fix -- a battle-scoped per-key baseline.** `combat/modern_stat_manipulation.lua` gains `captureStatBaseline(m, who, keys, gen2)`, `revertStatBaseline(who, gen2)` (exported) and `revertScopedStats(battle, who)`. The baseline is `m.__g9StatBaseline` -- a plain table ON THE MON, deliberately NOT `mon.volatile`, for the same reason Power Shift's fields are: Gen 2's own switch path clears volatiles BEFORE emitting `battle.battler_switched`, so a volatile-held baseline would already be gone when the restore listener ran. `captureStatBaseline` is idempotent per key (writes only when `base[k] == nil`), so the FIRST battle-scoped effect to touch a key owns the true pre-battle value: a Power Shift followed by a Power Split on one mon still reverts to the mon's real numbers, not to the shift's snapshot. `splitStats` captures each mutation's `{mon, stat}` before its write; the Power Shift handler captures `{attack, defense}` before its swap. `revertStatBaseline` restores every recorded key, clears `__g9StatBaseline`, and also clears `powerShiftActive`/`powerShiftPre` (so a mon that leaves with a shift active cannot later mistake a fresh Power Shift for a toggle-off).

**All three exits, raw-mon payloads.** The old `battle.battler_switched`/`battle.ended` listeners were replaced by three: `battle.battler_switched` reverts BOTH `ev.previous` and `ev.battler` (the scene emits raw mons and reuses one engine battler per mon, so the incoming revert is what makes the reused battler start clean); a NEW `battle.fainted` listener reverts `ev.battler or ev.mon or ev.target or ev.pokemon`; `battle.ended` sweeps `battle.player`/`enemy`, `allActiveBattlers`, the scene's `battlersByMon` cache, and `battle.party`/`enemyParty`/`playerParty`, deduped by mon. `revertScopedStats` normalises through `monOf` (battler or raw mon) and reads the generation from `isGen2Battle(battle)`. `monOf` now falls back to `who.mon or who` on Gen 1 so a raw mon resolves.

**Verified.** `luaparse 5.1` clean on `combat/modern_stat_manipulation.lua` (39,446 B, 841 lines; +112/-7 over the 4.4.4 file, 13 hunks). The fengari harness boots **146/146, 0 guarded failures** on Gen 2 and on a genuine Gen 1 game (`reportOnly`), with ten NEW round-70 checks all green -- `splitScopedBefore`, `splitRevertSwitch`, `splitRevertFaint`, `splitScopedGuardBefore`, `splitRevertEnd`, `splitRebaselineLive`, `splitRebaselineOriginal`, `splitInterleaveLive`, `splitInterleaveRevert` -- beside every pre-existing round-70 check. NEW `scratch/sim/probe_splits.lua` drives the Gen-1 path (wrapper battlers `{mon, curStats}`, raw-mon switch payloads, a non-Gen2 mock battle) and is all green: the average is live (atk/spa and def/spd), a switch-out restores only the leaving mon while the other stays split, a faint restores the other, `battle.ended` restores the roster, a re-split keeps the ORIGINAL baseline, Power Shift -> Power Split reverts both on one leave, and a Substitute still refuses the whole split. The only remaining harness failure is the pre-existing, unrelated `round74 ldRestoresPp=FAIL` (present with the 4.4.4 file too).

**Version / live.** Engine project **4.4.4 -> 4.4.5** (written back to the studio kv, `project.v` 77 -> 78). `g9-Battle-Scene` (3.0.6) and `g9-battle-sprites` are unchanged. The user must re-export `mods/g9-battle-engine` (4.4.5).

2026-09-20 round one-hundred-eighty-five — user: "yes" (in reply to: "Speed Swap does the same raw swap ... if you want it scoped too, say the word") — **Speed Swap joins Power Split / Guard Split / Power Shift on the battle-scoped baseline: it now hands each mon its own Speed back on switch-out, faint and battle end** (engine 4.4.5 -> 4.4.6; scene and sprites unchanged).

**Same class of write.** `GALAR_SPEEDSWAP_EFFECT` swaps the two mons' stored `speed` IN PLACE (Showdown `speedswap` 13784-13806 writes `Pokemon#storedStats` directly) and never reverted. A native battle reverts by rebuilding its battler from `mon.stats`, but that write lands on the party mon's own table (`curStats` IS `mon.stats` on Gen 1), and `g9-Battle-Scene` reuses ONE engine battler per mon -- so the swapped Speed survived the fight and rode into the save, exactly like the splits.

**The fix.** The Speed Swap handler now captures the round-184 per-key baseline for both mons before its swap (`captureStatBaseline(monOf(mu.who, n.gen2), mu.who, { mu.stat }, n.gen2)` for each of the two `speed` mutations) -- strictly before the two `setStoredStat` writes. No new listeners or state: the existing `battle.battler_switched` / `battle.fainted` / `battle.ended` sweep (and the exported `revertStatBaseline`) already covers every baseline key, so a Speed Swap "just works" the moment its key is captured. Because capture is idempotent per key, a second Speed Swap (or a Syrup Bomb Speed drop) never re-baselines: the key still reverts to the mon's true pre-battle Speed.

**Verified.** `luaparse 5.1` clean on `combat/modern_stat_manipulation.lua` (40,253 B, 855 lines; +126/-7 over the 4.4.4 file) and on `scratch/sim/probe_splits.lua`. The fengari harness boots **146/146, 0 guarded failures** on both Gen 2 and a genuine Gen 1 game (`reportOnly`), with six NEW round-70 checks all green -- `speedSwapScopedBefore`, `speedSwapRevertSwitch`, `speedSwapRevertFaint`, `speedSwapScopedEndBefore`, `speedSwapRevertEnd`, `speedSwapTwiceLive`, `speedSwapTwiceRevert` -- beside every pre-existing check. `scratch/sim/probe_splits.lua` gains a Gen-1 Speed Swap section (all green: swap live, baselines taken, switch-out restores the leaver while the other keeps the swapped value, battle end restores it). The only remaining harness failure is the pre-existing, unrelated `round74 ldRestoresPp=FAIL`.

**Version / live.** Engine project **4.4.5 -> 4.4.6** (written back to the studio kv, `project.v` 78 -> 79). `g9-Battle-Scene` (3.0.6) and `g9-battle-sprites` are unchanged. The user must re-export `mods/g9-battle-engine` (4.4.6).

2026-09-20 round one-hundred-eighty-six — user: "for all ability changing moves and abilities, let's add a routine to snapshot at battle start all party abilities and return them at switch-out/faint/battle ends" — **the ability slot gets the same explicit battle-scoped lifecycle round 184 gave raw stats** (engine 4.4.6 -> 4.4.7; scene and sprites unchanged).

**The gap.** Every ability-changing move (Skill Swap, Worry Seed, Entrainment, Gastro Acid, Role Play, Simple Beam, Doodle) and ability (Trace, Mummy, Lingering Aroma, Wandering Spirit, Receiver, Power of Alchemy; Core Enforcer's suppression) writes through `abilities/ability_dispatch.lua`'s `setAbility`, which was combat-only — but the pre-186 restore captured a mon's original ability LAZILY, the first time that mon was changed, and only on `battle.battler_switched` and `battle.ended`. `battle.ended` restored only the two ACTIVE battlers, so a benched mon that had been changed and then withdrawn before the fight ended could keep the changed ability into the save — and a mon the fight never touched carried no baseline at all.

**The routine.** `setAbility` still writes the RAW mon behind a Gen-1 battler wrapper (new local `rawMon`; the boss-immunity check now runs on the original `who` before unwrapping), but the per-mon record is now an explicit battle-scoped snapshot: `mon.__g9AbilityBaseline` (the original ability), `__g9AbilityBaselineSet` (a separate guard, so a mon whose genuine original is nil still restores to nil), and `__g9AbilityBaselineBattle` (scopes the snapshot to one battle, so a stale baseline from an abandoned fight is refreshed by the next `battle.started`). A new `snapshotAbilities(battle)` sweeps every party mon on BOTH sides — actives, the scene's `battlersByMon`, `battle.party`/`playerParty`/`enemyParty` and `battle.game.save.party`, deduped by raw mon — at `battle.started` **priority 1000**, ahead of every switch-in ability and ahead of gen2_modern_stats' own ability generation at priority 0. Only a mon that ALREADY has an ability is snapshotted (a nil baseline would blank out an ability generated later); a nil-ability mon is captured lazily by `setAbility` instead. Restore now runs at priority 10 on `battle.battler_switched` (outgoing AND incoming, ahead of the default-priority switch-in abilities so a leading Trace gets its true natural ability back before its own effect runs), at `-1000` on `battle.fainted` (last, so a default-priority faint handler such as Receiver observes the ability as it was at faint), and at `-1000` on `battle.ended` over the WHOLE roster. `captureAbilityBaseline`/`snapshotAbilities`/`restoreNaturalAbility` are exported (the historical name kept). `abilityIdOf` deliberately still does NOT unwrap Gen-1 wrappers (that would open a large untested Gen-1 ability-behavior surface); Gen-1 ability-change MOVES therefore still fail early on the wrapper, unchanged — the routine still covers the Gen-1 raw-mon path (Core Enforcer's suppression) and every Gen-2 path.

**Verified.** `luaparse 5.1` clean on `abilities/ability_dispatch.lua`. The fengari harness boots **146/146, 0 guarded failures** on both Gen 2 and a genuine Gen 1 game (`reportOnly`), with 14 NEW round-78 checks all green (`r186Exports`, `r186SnapshotParty`, `r186SnapshotSkipsNil`, `r186LazyCaptureNil`, `r186NoRebaseline`, `r186SwitchRevert`, `r186FaintChanged`, `r186FaintRevert`, `r186EndWholeParty`, `r186CycleRestored`, `r186ReSnapshot`, `r186WrapperRestore`, `r186BossImmune`). NEW `scratch/sim/probe_abilities.lua` drives the Gen-1 path (wrapper battlers `{mon, curStats}`, raw-mon payloads, a non-Gen2 mock battle; all 15 checks green: party snapshot, wrapper write, switch/faint/end restore, whole-party sweep, nil-ability lazy capture + nil restore, direct wrapper unwrap). The only remaining harness failure is the pre-existing, unrelated `round74 ldRestoresPp=FAIL`.

**Version / live.** Engine project **4.4.6 -> 4.4.7** (written back to the studio kv, `project.v` 79 -> 80). `g9-Battle-Scene` (3.0.6) and `g9-battle-sprites` are unchanged. The user must re-export `mods/g9-battle-engine` (4.4.7).

2026-09-20 round one-hundred-eighty-seven — user: "how are we assigning IV stat? review its whole generation, there are undesirable oddities, I've detected that all existing pokemon in modern stat have the same stat for Sp.A as their respective Sp.D. review and make sure that adv.stat is linked to our preserved IV and base stat (of national dex). you are also to check what happen to this 2 stats when a pokemon is generated for wild encounter then when they are caught. also report an example case like eternatus, what sp.a and sp.d it would have at lvl 5, its base stats through using national dex api." — **the Advanced-Stats Sp. Atk/Sp. Def collapse is fixed: `.ensure` now resolves the real national_dex split base instead of reusing the single collapsed Gen-1 `special` for both halves, and every save written before this round self-heals once on load** (engine 4.4.7 -> 4.4.8; scene and sprites unchanged).

**(a) The bug.** `stats/engine_modern_stats.lua`'s `.ensure` computed both special stats from `speciesDef.baseStats.special` (its inline `local b = speciesDef.baseStats; local baseSpa = b.spAttack or b.specialAttack or b.special`). In the live game `game.data.pokemon[species]` is the RAW record national_dex registers: `.baseStats` carries only the single collapsed Gen-1 `special`, while the real Gen 6 split rides at the SPECIES level as `.spAttack`/`.spDefense`. So `baseSpa` and `baseSpd` both fell through to `special` and every mon that went through `.ensure` (the Adv. Stats screen's own path, and the loaded-save path `save_scrub.lua` drives) showed Sp. Atk == Sp. Def. `.resolveBase`/`.recalcAll`/wild/trainer paths were already correct because they read the species-level split or a `resolveBase`-merged `.baseStats`; only `.ensure` collapsed.

**(b) The fix.** New `ModernStats.resolveBaseStats(speciesDef)` normalizes all three real record layouts -- a `resolveBase` reply (split already in `.baseStats`), a raw engine record (split at the species level), a native Gen-2 record (`specialAttack`/`specialDefense` in `.baseStats`, no `special`), and a bare base table -- into `{hp,attack,defense,speed,special,spAttack,spDefense}`, with the collapsed `special` used for BOTH halves only as the last-resort fallback when no real split data exists. `.ensure` and `.recalcAll` both call it now.

**(c) Self-heal.** A new `MODERN_STAT_REVISION = 2` (`ModernStats.MODERN_STAT_REVISION`) is stamped on every mon whose spa/spd `.ensure`/`.recalcAll` computes. A mon stamped below revision 2 (any save written before this round) has its spa/spd recomputed ONCE from its PRESERVED `mon.ivs`/`mon.evs` plus the real split base, then re-stamped -- guarded off while `mon.__g9StatBaseline ~= nil` (a Power/Guard Split is in flight). `.ensure` still fills a genuinely nil spa/spd regardless, so a first-time mon always gets numbers.

**(d) IV assignment, all three paths.** `.initialize` (wild encounters -- `stats/wild_modern_ivs.lua` wraps `BattleState.newWild` -> `.initialize`) rolls an INDEPENDENT `love.math.random(0,31)` per stat, zeroes evs, and discards whatever `Pokemon.new` rolled into `mon.dvs`. `.ensure` (legacy / loaded save, no provider) DERIVES IVs from the existing Gen-1 DVs, with `dvs.special` seeding BOTH `ivs.spa` and `ivs.spd` (Gen 1 has exactly one Special DV -- faithful, and NOT the collapse cause). `.applySpec` (trainer provider API, `stats/trainer_modern_stats.lua`) takes the provider's explicit iv/ev per stat verbatim. All three set `modernStatsInitialized`. The Adv. Stats screen's page-1 numbers are `mon.stats.spa`/`.spd`, written by `.ensure`/`.recalcAll` from `mon.ivs`/`mon.evs` + the split base, so adv.stat stays linked to the preserved IVs and the national-dex base stat, not to `stats.special`.

**(e) Wild -> caught lifecycle.** On a wild encounter, `.initialize` gives independent ivs/evs, then ability/nature/gender are generated, `resolveBase` splits the base, and `recalcAll` writes spa/spd and stamps revision 2. On catch, `BattleState:storeCaughtMon` (`src/battle/BattleState.lua:5410`) calls `Party.add(game.save.party, self.enemy.mon)` (`src/pokemon/Party.lua:7`, `table.insert`) or `Boxes.deposit(game.save, self.enemy.mon)` (`src/pokemon/Boxes.lua:33`, `table.insert`) -- the SAME table reference, no copy; `stampOT`/`restoreMimicked`/nickname touch neither ivs/evs/stats. On the next load `save_scrub.lua` calls `.ensure`, which sees revision 2 + non-nil spa/spd and is a no-op. So a caught mon's Sp. Atk/Sp. Def persist exactly as generated; an OLD caught mon self-heals once via the revision bump.

**(f) Eternatus (national_dex data).** Record `.baseStats` `{hp=140,attack=85,defense=95,speed=130,special=145}`, species-level `spAttack=145`, `spDefense=95`; `statsBySpecies` total 680; ability Pressure (slot 1, no hidden); evYield hp=3; genderRate -1 (genderless). At L5, EVs 0, neutral nature: Sp. Atk base 145 -> **19** (IV 0-9) / **21** (IV 10-31); Sp. Def base 95 -> **14** (IV 0-9) / **16** (IV 10-31). The legacy special-DV -> IV31 conversion gives **Sp. Atk 21 / Sp. Def 16** (previously the buggy `.ensure` gave **21/21**). Eternamax form: `spAttack=125`, `spDefense=250`.

**(g) Verification.** `luaparse 5.1` clean on `stats/engine_modern_stats.lua`. The fengari harness boots **146/146, 0 guarded failures** on Gen 1 (`reportOnly`) and Gen 2. `scratch/sim/probe_stats.lua` gains sections (7)-(10): `resolveBaseStats` splits correctly on all three layouts (`rbs_raw`/`rbs_merged`/`rbs_gen2` = 145/95); a raw-record `.ensure` now gives `ensure_spa=21 ensure_spd=16 ensure_equal=false` (was 21/21) and a L50 mon 165/115 (was 165/165); the self-heal recomputes from preserved IVs (`heal_ivs_preserved=true heal_spa=21 heal_spd=14 heal_revision=2`); a 50/50 base (Pikachu) still yields equal halves (correct); `recalcAll` stamps revision 2 (`recalc_spa=21 recalc_spd=14`). Wild (`19/14`) and `resolveBase` paths unchanged; all sim batteries `failCount 0`. The only remaining harness failure is the pre-existing, unrelated `round74 ldRestoresPp=FAIL`.

**Version / live.** Engine project **4.4.7 -> 4.4.8** (written back to the studio kv, `project.v` 80 -> 81). `g9-Battle-Scene` (3.0.6) and `g9-battle-sprites` are unchanged. The user must re-export `mods/g9-battle-engine` (4.4.8).

2026-09-20 round one-hundred-eighty-eight — user: "I want battle scene manifest to point its dependency to battle engine's repo so gen1recomp can install it from gen1recomp client mod update by dependency pull. show how." — **the engine's launcher repo hint was a dead field (`repo` is ignored at the manifest top level; only `github` is read), now `github`; and `g9-Battle-Scene`'s manifest gained a `dependency_sources` pointer at the engine's repo, so the launcher's one-click dependency Pull can fetch the engine** (engine 4.4.8 -> 4.4.9; `g9-Battle-Scene` 3.0.6 -> 3.0.7).

**The dead field.** `manifest.json` declared the repo as a top-level `"repo"`, but the engine never reads that key at the top level: `src/mods/Manifest.lua`'s `Manifest.validate` (line ~319) sets `github = Manifest.parseGithub(raw.github)` — from `raw.github` only — and `repo` is accepted as an alias exclusively *inside* a dependency entry (`parseSpecs`: `ghHint = entry.github or entry.repo`) or as a value in the top-level `dependency_sources` map. So the engine shipped with `resolved.github == nil` and `LauncherMods.resolveDependencyRepo`/`ModUpdate` had no source to self-update from.

**The fix.** Top-level `"repo"` -> `"github": "https://github.com/tectorifter/Gen9Dex"`.

**Verified against the real loader.** Loaded `src/mods/Manifest.lua` under fengari with its five requires stubbed and called the actual functions: `Manifest.parseGithub("https://github.com/tectorifter/Gen9Dex")` -> `tectorifter/Gen9Dex` (also accepts a bare `owner/repo` and a `.git` URL; `""` -> nil), and `Manifest.validate(<manifest>)` -> `{ version = "4.4.9", github = "tectorifter/Gen9Dex" }`.

**Scene side.** `g9-Battle-Scene` is a separate mod shipped from `src/g9-Battle-Scene/`; its `manifest.json` now carries `"dependency_sources": { "g9-battle-engine": "https://github.com/tectorifter/Gen9Dex" }` at version 3.0.7, so its required dep resolves to that repo (`parseSpecs` -> `spec.github = "tectorifter/Gen9Dex"`), `LauncherMods.checkDependencies` exposes `dep.github`, and `LauncherView` shows the Pull button -> `RomImporter:_startDepPull` installs the newest Gen9Dex release asset matching `g9-battle-engine-<version>.zip` (`ModUpdate.pickZipAsset`).

**Version / live.** Engine project **4.4.8 -> 4.4.9**; `g9-Battle-Scene` **3.0.6 -> 3.0.7**. NOTE: the round-187 kv publish did not persist (the live studio kv was still round-186 content, `4.4.7`, `project.v` 80), so this write lands 4.4.8 + 4.4.9 together and advances `project.v` **80 -> 82**. The user must re-export `mods/g9-battle-engine` (4.4.9) and `mods/g9-Battle-Scene` (3.0.7); for the launcher's Pull to serve the CURRENT engine, a Gen9Dex release tagged `v4.4.9` carrying asset `g9-battle-engine-4.4.9.zip` must exist (the repo's newest release is currently `v4.1.5`).

2026-09-21 round one-hundred-ninety-one — user: "we need to repair gen 1 summary screen, it shows out of boundary. For that, we will make a new mod, and remove summary screen alteration from gen 1 in battle engine. as we use for TRAIN and MOVE screens the increased screen and canvas size with higher pixel density, let us do the same for summary screen of gen 1." — **the engine's Gen 1 party-menu STATS takeover is gone, so STATS opens the game's native party summary again, and the summary screen itself is now owned by the new `g9-gui` ("modern UI & stats") mod** (engine 4.2.0 -> 4.3.0; scene, sprites and sample unchanged).

**What left.** `stats/modern_stats_screen.lua` (the wide 256x144 two-column party STATS screen, added round 106) is deleted, its `boot("modern_stats_screen", ...)` line is gone from `main.lua`, and its option row plus the matching header paragraph are gone from `options.lua`. The file wrapped `ui.party.submenu` and rewrote the party menu's STATS entry (`item.action == "stats"` / `item.label == "STATS"`, setting `item.onSelect` to push its own 256x144 screen), so it both shadowed the game's native party summary and left a mod that replaces the summary nothing to hook. Nothing else in the engine named it except four historical comments in `stats/dev_stats_screen.lua` explaining why ITS own wide-canvas technique was dropped (left as-is; that history is still true). `stats/dev_stats_screen.lua` (Adv.Stats — a separate `Adv.Stats` submenu entry, default OFF, window 192x173 on Gen 1) and `stats/train_screen.lua` are untouched.

**What replaces it.** The summary now belongs to the new **`g9-gui`** mod (`modern UI & stats`, Gen 1 only, `optional_dependencies` = g9-battle-engine): a full-screen START takeover in the FF12 / Zodiac-Age shape (the vanilla word list in a left column, a live party roster on the right carrying portrait cards, name, level, money, HP gauge and EXP bar), a POKéMON-screen takeover with a detail card and a modern options popup, and a **240x135 "ADV.STATS" panel — exactly 75% of the 320x180 UI surface on both axes — floated over the still-visible POKéMON screen** so the menu shows around all four sides. It renders with the TRAIN / MOVE screens' own technique (answers `:uiSize()` with 320x180 and never calls `Renderer:setUISize` or `setCanvas`), registers `src.ui.SummaryMenu`, and is therefore the one and only summary screen on a Gen 1 boot. Its modern fields (split special stats, ability, nature, Tera type, Dynamax level) come from this engine's exported `ModernStats` / `MoveCategory` when it is installed; every read is pcall-guarded, so the panel still opens with a correct vanilla stat block and blank modern rows without it.

**Verified.** `luaparse 5.1` clean on the rewritten `main.lua` (115,114 B) and `options.lua` (7,261 B); `manifest.json` valid JSON at 4.3.0; the removed file is gone from the tree (221 -> 220 files). The engine zip was built from the live kv exactly the way the studio does it (JSZip DEFLATE, `g9-battle-engine/` prefix, every file) and re-read: 220 entries, 1,009,011 B, no `stats/modern_stats_screen.lua`, `dev_stats_screen.lua` and `train_screen.lua` both present. The new summary was checked with a NEW fengari harness (`scratch/sim/gui_harness.lua` + `scratch/sim/run-gui-layout.js`) that loads g9-gui's REAL sources against recording love.graphics / engine stubs, rasterises every recorded draw call with the real bundled PlainPixel TTF (head-cropped battle sprites, party icons, ink-offset text) and bounds/overlap-checks each shot: 12 shots, no errors, nothing off-surface, and every surviving overlap is deliberate (the faux-bold double-print on the selected word-list row, the modal popup over the dimmed roster, and the summary panel over the menu it floats on).

**Version / live.** Engine project **4.2.0 -> 4.3.0** (written back to the studio kv, `project.v` 83 -> 84). The kv now holds TWO projects: `project` (g9-battle-engine) and `g9gui` (g9-gui, 11 files, 85,188 B). The user must re-export/replace `mods/g9-battle-engine` (4.3.0) and add `mods/g9-gui` (1.0.0). Both zips are attached.
2026-09-26 round one-hundred-ninety-nine — user: "in battle engine, remove the access from start menu to g9 dex" (with a screenshot of the START menu listing the rows POKéDEX / ITEM / Dan / SAVE / OPTION / MODS / QUIT, with a "G9 DEX" row selected beneath them) — **the engine no longer injects a "G9 DEX" row into the START menu; its options schema is still defined and is reached from the engine's own mod manager** (engine 4.3.0 -> 4.3.1; scene, sprites and g9-gui unchanged).

**What left.** `main.lua`'s `debug_options` boot block had a second half: a `mod.hooks:wrap("ui.start_menu.items", ...)` that appended `{label = "G9 DEX", onSelect = ...}` to the START menu's item list, whose handler pushed a `ManagerState` frame and ran `state:openOptions({ id = mod.id })`. That wrap (and its `require("src.mods.ManagerState")` closure) is deleted; it was the ONLY writer of `ui.start_menu.items` in the engine, so that hook now goes untouched.

**What stays.** The same boot block still runs `mod.options:define(loadSibling("options.lua"))`, so every row in `options.lua` remains a live option of the mod, editable from the launcher's own mod-manager options screen. No other file names "G9 DEX" (the tree's only other hit is README.md's line about `self.g9dex.exports`), and `ManagerState` is still required by the manager itself.

**Verified.** `luaparse 5.1` clean on the rewritten `main.lua` (114860 B) and `manifest.json` valid JSON at 4.3.1; a scan of all 220 files finds the removed row's label and the `ui.start_menu.items` hook nowhere outside this README's own round-199 entry. The engine zip was rebuilt from the live kv exactly the way the studio does it (JSZip DEFLATE, `g9-battle-engine/` prefix, every file) and re-read: 220 entries, every entry byte-identical to the kv content (~1.01 MB).

**Version / live.** Engine project **4.3.0 -> 4.3.1** (written back to the studio kv, `project.v` 84 -> 85). `g9-Battle-Scene` (3.0.7), `g9-battle-sprites` (3.0.9) and `g9-gui` (1.7.0) are unchanged. The user must re-export `mods/g9-battle-engine` (4.3.1).

2026-09-10 round two-hundred-and-six — user: "undesired behavior, if second pokemon is fainted, it's being brought into combat (fainted prior battle) it should be skipped and next alive take its place, same with third (triple battles) and fourth (boss fights)" — **a registered `doubles`/`triples`/`bossFight` trainer's battle no longer sends a fainted party member to the field: the player side is filled from the first N LIVING party mons in party order** (engine 4.3.2 -> 4.3.3; scene, sprites, g9-gui and the trainer sample unchanged).

**What was wrong.** `trainers/custom_trainer_registry.lua`'s `World:startBattle` wrap built the scene request's `players` list as a raw `party[1..allyCount]` positional slice, so a 0-HP slot 2/3/4 went onto the field with no switch prompt. A caller mod defers to `hasRegisteredTrainer` rather than pushing its own layout, so for a REGISTERED trainer this wrap is the only place the roster is built — the skip has to live here.

**The fix.** The slice is now a walk of the whole `save.party` that appends the first `allyCount` mons with `hp > 0`, in party order (this also keeps the lead correct when `party[1]` is itself the fainted one). The enemy roster (`trainer.party`) is untouched; the other roster-building paths already apply the same rule (the separate `g9-battle-sample` mod uses the identical `shared.playerRoster` helper).

**Verified.** `luaparse` clean on the 837-line file; the engine zip rebuilt from the live kv (220 entries) and re-read byte-identical.

2026-09-10 round two-hundred-and-eighty-one — user: "protect is protecting despite failing. make sure that protect also blocks status moves effects." — **the Protect family's block flag is now turn-scoped and the turn-start clear covers the whole roster, so a failed Protect can never leave a stale shield standing; and Part D now turns aside status moves of EVERY record kind, including the Counter/Mirror Coat/Metal Burst family and the fixed-damage moves that never reach `battle.damage`** (engine 4.4.0 -> 4.4.1).

**The stale-shield bug.** Part C's `battle.turn_started` listener cleared only `battle.player`/`battle.enemy`, so in a multi-battler battle (g9-Battle-Scene's doubles/triples/boss rosters) any OTHER battler kept `protected`/`maxGuarded` set forever, and a mon whose Protect FAILED was still shielded by the flag it had earned on an earlier turn -- exactly the reported "protect is protecting despite failing". Fixed three ways: (1) each flag is stamped with the turn it was raised (`protectTurn`/`guardTurn`) and `protectionOf(battle, who)` only counts a flag whose stamp matches the live turn (`battle.turn` on Gen 2, `battle.turnCount` on Gen 1); (2) both run() handlers `clearProtection(user)` BEFORE they roll, so a failed roll leaves nothing; (3) Part C now sweeps `mod.exports.allActiveBattlers` plus `battle.party`/`playerParty`/`enemyParty` and the native pair. `clearProtection`/`protectionOf` are exported; every block path (Part B's priority-50 damage wrap, Part D's `useMove` / `performMove` wraps) reads through `protectionOf`, and `combat/modern_movepool_counter.lua`'s own `chooseDamage` protected-check was switched to it too.

**Status-move coverage.** Part D's Gen 2 swap substituted only `kind == "primary"/"secondary"` records, so a power-0 move whose effect record is `kind == "full"` slipped through entirely: the Counter/Mirror Coat/Metal Burst family (a full record carrying its own `run`), and the bare full markers the fixed-damage moves use (Seismic Toss, Night Shade, Sonic Boom, Dragon Rage, Super Fang) -- which reach the native `fixedDamage` arm PAST the record dispatch and never touch `battle.damage`, so Part B never saw them either. The swap now replaces the move's OWN effect record whatever its kind. Both Part B and Part D also gained a target gate (`targetsBattler`, exported as `protectTargetsBattler`): a move is only blocked when national_dex's own `target` archetype actually aims at the shielded battler, so Spikes/Stealth Rock (`opponents-field`), Reflect/Safeguard (`users-field`), Trick Room/Haze (`entire-field`/`all`) and self-buffs (`user`) are never wrongly stopped; an unknown/nil archetype still defaults to the old block.

**Verified.** The fengari syntax gate `__compileAll("scratch/engine-extract/")` is **211/211**. The fengari harness boots **223 files, 149/149 subsystems, 0 guarded failures**, and the round-32 battery gained these checks, all green: `staleFlagIgnored`, `staleFlagNoRider`, `freshFlagBlocks`, `targetGateExport`, `fieldMoveExempt`, `foeMoveAllowed`, `failedRollDropsFlags`, `partDPrimaryBlocked`, `partDFullBlocked`, `partDBareFullBlocked`, `partDStaleNotBlocked`, `partDUnprotectedRuns` (the round-16 `protectBlock` check was re-stamped to the turn-scoped contract). All four Protect probes are green: `probe_protect_audit.lua` (roster-wide clear, turn-scope fresh/stale on both engines, `clearProtection` drops every field), `probe_protect_partd.lua` (Gen-1 performMove chain: blocked/maxguarded/stale/unprotected/bypass + lookup restore), `probe_protect_gen1.lua` (dual-engine handlers, Gen-1 Part B block, stale flag ignored), `probe_protect_partd2.lua` (Gen-2 useMove chain: primary, full-record, bare-full, stale, bypass, lookup restored). The only remaining harness failures are the pre-existing, unrelated `round74 ldRestoresPp` and `round78 r186SnapshotParty`/`r186ReSnapshot`.

**Version / live.** Engine project **4.4.0 -> 4.4.1** (written back to the studio kv, `project.v` 91 -> 92). `g9-Battle-Scene`, `g9-battle-sprites` and `g9-gui` are unchanged. The user must re-export `mods/g9-battle-engine` (4.4.1).

2026-09-10 round two-hundred-and-eighty-five — user (a g9-gui mod-manager error log from a Gold boot): "gold errors after latest updates: ... 216 RUNTIME & LOAD ERRORS ... `g9-battle-engine: moves.BATTLE_FORMS_*_*.effect: unresolved reference to move_effects \"NO_ADDITIONAL_EFFECT\"` ... `g9-battle-engine: moves.STONEEDGE.effect: unresolved reference to move_effects \"EFFECT_ALWAYS_CRIT\"`" — **the loader's cross-reference pass now resolves every move record this mod owns: the boot seeds a bare `kind=\"full\"` marker into the boot generation's `move_effects` id space for Gen 1's `NO_ADDITIONAL_EFFECT` no-op and for any effect id a re-owned move carries** (engine 4.4.1 -> 4.4.2).

**What was wrong.** `src.mods.Loader` runs `Schemas.crossValidate` once after the merge; that pass reads every `moves.<id>.effect` as a reference into `move_effects` and checks it against the BOOT'S generation — and on Gold `Schemas.GEN2` routes `move_effects` to `data.gen2MoveEffects`, because Gold reimplements the system and names its effects `EFFECT_*` (`src/battle/gen2/Battle.lua:registerMoveEffectsInto`). Gen 1's do-nothing damaging effect is `NO_ADDITIONAL_EFFECT`; Gold's is `EFFECT_NORMAL_HIT`. The engine DOES seed a bare marker for every effect id a move uses — `registerMoveEffectsInto` walks `data.moves` for exactly this reason — but it runs from `src.mods.Builtins` at boot, BEFORE any mod registers a move, so an id that only a MODDED move carries is never seeded. This mod's patched Max/G-Max rows and `battle_forms`' `BATTLE_FORMS_*` rows all carry `NO_ADDITIONAL_EFFECT`, and every move this mod re-owns through `wireMovepoolSubEffects` keeps national_dex's own effect id — `STONEEDGE`'s `EFFECT_ALWAYS_CRIT` (it is re-owned because Stone Edge is a real high-crit move and the pass sets `highCrit`). One log line per move: 215 `NO_ADDITIONAL_EFFECT` rows plus STONEEDGE.

**The fix.** New `combat/move_effect_markers.lua` (booted right after `movepool_sub_effects`, the pass that writes the move ops) registers the SAME bare `kind="full"` marker the engine registers for its own ROM moves: `NO_ADDITIONAL_EFFECT` first — explicitly, because the mod's peers lean on it too and because on Gen 1 it is a REAL vanilla record (`src/battle/MoveEffects.lua`'s `MoveEffects.full`) that the `:get(id) == nil` guard correctly leaves alone — then every effect id a move record this mod owns references (`moves.ops` walk, the same op log crossValidate walks). A `kind="full"` marker is the engine's own choice: it is a MISS at both of `Battle.moveEffectRecordFor`'s call sites, so seeding it cannot change a battle's behaviour, only the validator's view of the id space; registering an id that already exists is skipped, so nothing collides with the engine's own seeds.

**Verified.** A NEW fengari harness (`scratch/sim/gen2_move_effects_harness.lua` + `scratch/sim/run-gen2-move-effects.js`) loads the REAL `src/mods/Schemas.lua` and runs its REAL `crossValidate` over a synthetic `moves`/`move_effects` pair built from the log's own rows, then runs the REAL sibling over it. Before: **213 rows -> 213 problems**, message format byte-identical to the user's log (`g9-battle-engine: moves.BATTLE_FORMS_SHATTEREDPSYCHE_100.effect: unresolved reference to move_effects "NO_ADDITIONAL_EFFECT"`), owner split 195 g9-battle-engine / 18 battle_forms (matching the log's alternating attribution). After: **0**. The pessimistic case (the sibling can see only its OWN ops while the loader still checks every row) is also 0 — the explicit `NO_ADDITIONAL_EFFECT` ensure carries it. The Gen 1 guard adds 0 ids when `NO_ADDITIONAL_EFFECT` already exists. `__compileAll("scratch/engine-extract/")` is **212/212**; the full fengari harness boots **224 files, 150/150 subsystems, 0 guarded failures** (the new boot step is the 150th), and `roundFails` is unchanged from the recorded baseline (only the pre-existing `round74 ldRestoresPp` and `round78 r186SnapshotParty`/`r186ReSnapshot`).

**Version / live.** Engine project **4.4.1 -> 4.4.2** (written back to the studio kv). `g9-Battle-Scene`, `g9-battle-sprites` and `g9-gui` are unchanged (g9-gui is at 2.8.3 from round 284). The user must re-export `mods/g9-battle-engine` (4.4.2).

2026-09-10 round two-hundred-and-eighty-seven — user (the SAME Gold boot log, after installing 4.4.2): "remaining errors after last update (gen 2 only): 3 RUNTIME & LOAD ERRORS ... `g9-battle-engine: moves.STONEEDGE.effect: unresolved reference to move_effects \"EFFECT_ALWAYS_CRIT\"`" — **the 4.4.2 sweep's op-log walk was dead code on a real boot: `mod.content.moves` is not the raw Registry but `Loader:_contentApi`'s closure, whose whole surface is register/override/patch/remove/get/each and NO `ops` field, so `type(moves.ops) == "table"` was false and only the no-op marker was ever seeded; the sweep now walks the public `moves:each()` merged view** (engine 4.4.2 -> 4.4.3).

**What was wrong.** `Loader:_contentApi` (src/mods/Loader.lua) hands a mod a table of closures over the shared Registry — `register`, `override`, `patch`, `remove`, `get`, `each` — and nothing else. `combat/move_effect_markers.lua` guarded its sweep with `type(moves.ops) == "table"`, which is nil on that closure, so on every real boot the loop was skipped. That is invisible for the 213 `NO_ADDITIONAL_EFFECT` rows (the explicit ensure carries them) and invisible in this repo's boot harness, whose JS `moves` stub also answers `get` with a bare `{id}` — but it left the ONE row whose effect id is peer-written: `battle_forms`' `src/speciesbasemoves.lua` re-spells `STONEEDGE`'s effect as Gold's own `EFFECT_ALWAYS_CRIT` (the string `src/battle/gen2/Battle.lua:hitOnce` compares against; it is NOT in `Battle.MOVE_EFFECT_RECORDS`, so the engine's own `registerMoveEffectsInto` never seeds it). `battle_forms` loads at priority 80 and this mod at 95 (Loader.lua:71 — priority ascending), so that patch is already in the shared registry when this file runs, and this mod's own `highCrit` patch on the same record lands after it, which is why `registry.owners` attributes the dangling id to g9-battle-engine.

**The fix.** The sweep now prefers `moves:each()` — the registry's own merged view (base ids first, then op-only ids, each folded through `get()`), a superset of the ids `Schemas.crossValidate` scans — and keeps the `moves.ops` walk as the fallback for a raw Registry (this file's own test double). Both arms run inside a pcall, so an unknown registry shape can never take the no-op marker down with it. A `kind="full"` marker stays exactly the engine's own choice (a MISS at both of `Battle.moveEffectRecordFor`'s call sites) and registering an id that already exists is still skipped, so nothing collides with the engine's own seeds.

**Verified.** `scratch/sim/gen2_move_effects_harness.lua` now models the REAL closure and reproduces the bug: scenario 0 hands the sibling a `get`-only view (no `each`, no `ops` — the 4.4.2 assumption) and the `STONEEDGE` row survives, byte-identical to the user's log; scenario 1 hands it the real shape (`get` + `each`, still no `ops`) and the count goes **213 -> 0**, with `EFFECT_ALWAYS_CRIT` confirmed seeded and the specific `STONEEDGE` message gone. Scenario 1b (raw-registry fallback), scenario 2 (`each()` yielding only this mod's ids, so the explicit no-op ensure must carry the peers) and scenario 3 (Gen 1 guard: 0 added when `NO_ADDITIONAL_EFFECT` already exists) all pass. `__compileAll("scratch/engine-extract/")` is **212/212**; the full fengari boot harness is **224 files, 150/150 subsystems, 0 guarded failures**, with `roundFails` unchanged from the recorded baseline (only `round74 ldRestoresPp` and `round78 r186SnapshotParty`/`r186ReSnapshot`).

**Version / live.** Engine project **4.4.2 -> 4.4.3** (written back to the studio kv). `g9-Battle-Scene` and `g9-battle-sprites` are unchanged; `g9-gui` goes to 2.8.4 in the same studio round. The user must re-export `mods/g9-battle-engine` (4.4.3).



## SHORT HEAL CHAT wiring (4.5.1)

`overworld/pokecenter_heal.lua` reads g9-gui's SHORT HEAL CHAT row through TWO
channels: the documented `mod.find("g9-gui").exports.shortHealChatEnabled`
handle first, then the persisted row straight off the live save
(`save.options.modOptions["g9-gui"].short_heal_chat`). The value is accepted
as a boolean, the `"true"`/`"false"` strings the Mod Manager stores,
`"on"`/`"off"`, or a number, and the resolved value is logged once per session
(`SHORT HEAL CHAT is ON/OFF (...)`), so a wiring problem is a readable line
instead of a switch that silently does nothing. `g9-gui` is now named in this
manifest's `optional_dependencies`.

## Party-menu HP drain fix (4.5.2)

**The bug.** On Gold, `src/ui/gen2/PartyMenu.lua` calls `Mon.refreshStats` for
every party member in its CONSTRUCTOR -- i.e. on every open of the POKeMON
screen, including the LEFT/RIGHT page turn onto it. This mod wraps that
function (`stats/train_screen.lua`, the change-preservation block) to re-apply
an edited mon's modern stats afterwards. The wrapper called the native refresh
FIRST, which overwrites `mon.stats` with the DV-derived block and sets
`mon.maxHp` to that (usually smaller) NATIVE max; the re-apply then measured
its carried "missing HP" against those post-refresh numbers instead of the
modern max that was there before, so every open drained `nativeMax -
modernMax` HP. When that difference is 1 -- e.g. an edited mon whose modern HP
lands one point below its Gen 2 stat-exp HP -- the mon lost exactly 1 HP on
EVERY page turn onto the party: the report "a pokemon ... loses 1 hp every
time the cursor passes to party row".

**The fix.** The wrapper snapshots the modern max/HP BEFORE the native recompute
and passes them into `applyModern` (new optional `keepMax`/`keepHp` args), which
measures the missing HP against those instead. A party-menu open is now
HP-idempotent and `mon.hp` is preserved exactly. The non-wrapper callers
(`pokemon.level_up`, `battle.started`, the TRAIN screen's own commit) pass no
keep args and keep their previous behaviour.

**Verified.** `luaparse 5.1` clean (1498 lines). A numeric reproduction of the
two formulas showed the old path draining 1 HP per open (230 -> 229 -> 228 ->
...) at base HP 45 / level 100 / stat-exp 25 / modern IV 30, and the new path
holding 230 flat. `g9-gui` 3.0.2 adds `ui/hp_guard.lua`, a sentinel that
catches (and restores) ANY unexplained party-HP drop during a mere page turn,
so the whole class of bug is visible in the mod log even if some other writer
is ever responsible.

## Center heal keeps its modern max (4.5.3)

**The bug.** After a POKeMON CENTER heal a party mon could sit at **max - 1** --
current HP one point under the displayed maximum, in some cases.

**Root cause (Gen 2).** `overworld/pokecenter_heal.lua` heals to this mod's
MODERN max: it runs `ModernStats.ensure` + `recalcAll` and sets `mon.hp =
mon.stats.hp` (mirrored into `mon.maxHp`). But Gold's native
`src/battle/gen2/Mon.lua` `Mon.refreshStats` -- called for every party member by
`src/ui/gen2/PartyMenu.lua` on each party-menu open, and again by `Battle.new`
at battle start -- **replaces** `mon.stats` with the DV/stat-exp block and sets
`mon.maxHp` to that. Its HP formula rounds differently from the modern one
(`floor(sqrt(statExp.hp)/4)` vs the converted `floor((statExp*252/65535)/4)`),
so for a small stat-exp total the DV-derived max can be exactly **1 more** than
the modern max. `refreshStats` only clamps `mon.hp` DOWN (`if mon.hp > stats.hp
then mon.hp = stats.hp end`), never tops it up, so the healed current HP (the
modern max) was left under the now-native max -- max - 1. Once the native block
was in place the numbers stayed put, which is why it looked like a one-off.

**Root cause (Gen 1).** `ModernStats.recalcAll` writes the modern block under
the native key names (`hp/attack/defense/speed` + `spa/spd`) but never writes
Gen 1's single `special` key. The engine's own `Stats.ensure` (called by
`src/ui/SummaryMenu.lua`, `src/ui/BoxMenu.lua` and `SaveData.validate`) rebuilds
the WHOLE block from DVs the moment any of its five Gen 1 keys is missing, so a
healed/caught mon whose block came from `recalcAll` could have the modern HP
thrown away on the next summary/box open.

**The fix.**

- `ModernStats.recalcAll` now stamps **`mon.g9ModernOwned = true`** -- it is the
  one function that writes the whole stat block from the modern model, so a mon
  that has been through it must not be silently re-typed by a native recompute.
  Deliberately NOT set in `.ensure`, because `stats/save_scrub.lua` runs
  `.ensure` on every mon in a loaded save (fill-only) and that must not read as
  ownership.
- The change-preservation block in `stats/train_screen.lua` now gates on a
  `modernOwned(mon)` helper (`mon.g9TrainEdited or mon.g9ModernOwned`) instead of
  `g9TrainEdited` alone: the Gen 2 `Mon.refreshStats` wrapper, the
  `pokemon.level_up` re-apply and the `battle.started` re-apply all re-apply the
  modern block for a modern-owned mon. `g9TrainEdited` is unchanged, so existing
  saves keep working.
- `overworld/pokecenter_heal.lua` mirrors the native shape on Gen 1
  (`mon.stats.special = mon.stats.spa`) as well as Gen 2
  (`specialAttack`/`specialDefense` + `maxHp`), so the native `Stats.ensure`
  never rebuilds the heal away.
- The same Gen 1 mirror is added to `stats/ev_yield_on_faint.lua`'s Gen 1
  recompute and `stats/wild_modern_ivs.lua`'s caught-wild path, and
  `stats/gen2_modern_stats.lua`'s `applyComputedStats` stamps `g9ModernOwned`
  so a caught Gold wild mon keeps its modern block.

**Verified.** `luaparse 5.1` clean on all six changed `.lua` files. A fengari
harness running the REAL `engine_modern_stats.lua` and the REAL `applyModern`
(extracted from `train_screen.lua`) against the engine's native Gold formulas
reproduces the report exactly -- base HP 45 / level 50 / HP DV 8 / HP stat-exp
100 gives a modern max of **113** and a native max of **114**: pre-fix the
native refresh left `hp=113, max=114` (missing 1); with the wrapper the result
is `hp=113, max=113` (missing 0); a mon at `hp=108` stays `108/113` (no free
heal). The Gen 1 check shows `Stats.ensure` rebuilding a block with no
`special` (`hp` changed) and leaving one with `special` alone (`hp` kept).

## The engine no longer sets trainer teams (4.5.4)

**What changed.** `overworld/gym_trainer_teams.lua` (the generated roster data)
and `overworld/install_gym_trainer_teams.lua` (its installer) are **removed**,
and the two `boot(...)` calls that loaded them are gone from `main.lua`. The
engine no longer rewrites any trainer's team: the 22 `FALKNER`..`RED` trainer
classes revert to the game's own rosters, and the special IV-31 / EV-85 /
per-species-nature profile that installer registered (priority 50) goes with
it.

**Why.** Team *setting* is not this engine's job. A caller mod asks for a team
through the engine's own public API -- see the next section -- and the engine
processes the stats of what it is handed; it must not carry a roster of its own
that silently alters the drawn gym fights.

**What is deliberately UNTOUCHED (the mod-to-mod contract).** Everything a peer
uses to hand this engine a team, and everything the engine uses to process one,
still exists and behaves exactly as before:

- `mod.exports.registerTrainer(trainerId, party, options)` -- the public
  roster-registration API (`trainers/custom_trainer_registry.lua`), together
  with `unregisterTrainer`, `getRegisteredTrainer`, `hasRegisteredTrainer` and
  `setTrainerMaxHpMultiplier`. Its own stats provider (priority 100) and its
  `battle.started` / `World:startBattle` integration points are unchanged.
- `mod.exports.registerTrainerStatsProvider(fn, priority)` --
  `stats/trainer_modern_stats.lua`'s provider chain, the seam every stats
  contributor (including the removed file's own provider) registers on.
- The `"trainer.party"` runtime hook itself -- the seam a party rewrite is
  delivered through. The engine simply stops being one of its callers; any mod
  that wraps it (or that a peer wraps) still does.
- The base modern-stats pipeline (`stats/gen2_modern_stats.lua`,
  `stats/wild_modern_ivs.lua`), which generates modern IVs/EVs/natures for
  every trainer and wild mon regardless of roster source, is untouched.

**Nothing published was removed.** The deleted installer exported nothing (it
only wrapped `trainer.party` and registered a private provider), so no peer mod
can be depending on it; and no other file in this engine or any sibling mod
referenced either file. `g9-battle-sample`'s own provider (priority 100) simply
outranks nothing now instead of outranking the removed priority-50 provider --
functionally identical, and its comment was updated to match.

**Verified.** `luaparse 5.1` clean on `main.lua`; both deleted paths are gone
from `files.json` (222 files remain) and no `.lua`, `.md` or `.json` under
`src/` still points at either file except the historical round notes; the
studio's own wiring gate is re-run by the reader. LÖVE cannot run in the
preview, so the in-game confirmation is the user's.

## Pivot self-switch pause / resume (4.5.5)

**What changed.** A self-switch move (U-turn, Volt Switch, Flip Turn, Teleport)
no longer ends the round before the switch-in is on the field. The engine can
now **pause** a scene-driven round at a self-switch, let the battle scene
perform the player's bench pick, and **resume the same round** with the
not-yet-acted actions retargeted onto the mon that came in.

**Why.** `combat/switch_primitives.lua`'s `requestSwitch` sets the real, public
`battle.forcedSwitch` field, and `resolveTurnActions` has always honored it by
ending the round early (matching native's own Roar/Whirlwind drag-out). That is
correct for a drag-out but wrong for a pivot: the scene owns the player's bench
pick and never got the chance to make it, so the switch-in was never actually
sent out, and the opponent's pending move -- which the engine had captured
against the outgoing mon at queue time -- was skipped.

**How.**

- `combat/switch_primitives.lua`'s player branch now records the leaving mon on
  `battle.__g9PendingSelfSwitch = { mon, side, reason }` before it sets
  `forcedSwitch`.
- `combat/turn_order.lua`'s `resolveTurnActions` reads that tag at the
  forced-switch break. When the paired scene advertises
  `battle.__g9SceneHandlesPivotSwitch`, it stores the live order list
  (`ordered`, `orderIndex`, `chosen`) on `battle.__g9PivotPause`, emits a
  `{kind = "pivot-switch", mon, side = battle:sideOf(mon)}` event, and returns
  WITHOUT running the end-of-turn. The turn counter is deliberately **not**
  advanced again on the resume -- it is the SAME round.
- New `mod.exports.resumeAfterPivot(battle, incoming, outgoing)` re-enters
  `resolveTurnActions` with the stored order list, repoints every not-yet-acted
  actor whose chosen `target` was the outgoing mon onto `incoming`, clears the
  pause, and finishes the round -- residuals included, so weather / Leftovers /
  etc. tick the field as it stands (the mon that actually came in). It returns
  `false` and does nothing when no pause is pending, so a caller can always call
  it defensively.

**Scope / compatibility.** The whole path is OPT-IN: a scene that does not set
`battle.__g9SceneHandlesPivotSwitch` (or a caller that never sets
`battle.__g9PendingSelfSwitch`) keeps the previous behaviour exactly -- the round
ends at the switch. `requestSwitch`'s public signature is unchanged, the enemy
branch is untouched (it resolves synchronously), and native runTurn never calls
this resolver, so a normal battle is completely unaffected.

**Verified.** `luaparse 5.1` clean on `turn_order.lua` and
`switch_primitives.lua`. The new fengari driver `pivot_pause_test.lua` runs the
REAL `turn_order.lua` against a mock Gen-2 battle and is **19/19** -- case (A)
U-turn acts first, the round pauses, only the pivot has acted, the `pivot-switch`
event fires, and on resume the pending `TACKLE` follows the slot to the
switch-in with no second turn increment; case (B) Teleport acts last, so nothing
is pending on resume; case (C) with no scene flag the old behaviour is preserved
(no pause, the remaining actor is skipped, the round closes). The engine boot
harness still reports 146/146 subsystems with 0 guarded failures, and the scene
side is covered by g9-Battle-Scene's own `exp_share_screen` **46/46** (was
38/38). LÖVE cannot run in the preview, so the in-game confirmation is the
user's.

## Hardcoded fallback move records (4.6.0)

**What changed.** A new boot pass, `combat/modern_fallback_moves.lua`, supplies a
move record the running game's move data does not -- and the runtime power a
record cannot express. Its one entry today is **Pika Papow** (`PIKA_PAPOW`), the
fourth Let's-Go partner-Pikachu move: the `national_dex` build this repo
references registers Zippy Zap, Floaty Fall and Splishy Splash but **not** Pika
Papow, so a mon built carrying it (`g9-battle-sample`'s LEAGUE ACES Red does,
with the other three) held a move id with no record at all -- no name, no type,
no damage.

**Why the engine supplies it.** national_dex is this mod's hard dependency and
owns the move data, so a move it does not carry normally stays absent -- correct
for a random battle, wrong for a caller that deliberately builds a set naming
it. `g9-battle-sample`'s `resolveMoveId` already fell back to THUNDERBOLT at
runtime, which kept the set four valid moves but silently substituted a
different move. With this file the engine answers the id for real, on both
generations, without any game data change.

**How.**

- `FALLBACK_MOVES` holds the record in the move schema's own shape
  (`Schemas.lua` `R.moves`): `id`/`name`/`type`/`category`/`power`/`accuracy`/
  `pp`/`priority`/`effect`. Pika Papow is `ELECTRIC` / `special`, accuracy 100,
  20 PP, effect `NO_ADDITIONAL_EFFECT` (which `combat/move_effect_markers.lua`
  already seeds as a no-op `kind="full"` marker, so the damaging move falls
  through to the generic damage path on both generations).
- `power = 1` is deliberate: it is this codebase's placeholder for a move whose
  real power is computed at runtime -- the same convention `national_dex`'s own
  computed-power records carry, and exactly what `modern_combat.lua`'s
  `hasComputedPower` gate wants (`powerOverrides[move.id] ~= nil` keeps a stored
  0/1 from turning the move away as a status move).
- `sureHit = true` is the engine's own extension the record carries: Pika Papow
  bypasses the accuracy check and always hits, which `combat/
  modern_crit_override.lua`'s `battle.accuracy` wrap already honours on BOTH
  generations (Gen 1's percent-domain threshold would otherwise turn a
  0-accuracy record into a ~255/256 miss). It is the same key
  `wireMovepoolSubEffects` patches onto a critRate>=6, accuracy-0 move, and
  `Schemas` preserves unknown top-level keys as a feature.
- **The power formula** rides `registerPowerOverride` -- the base-power
  substitution seam Heavy Slam / Return / Fury Cutter use -- not the record's
  static `power`, because it is a function of the user's friendship
  (Bulbapedia, Generation VII): **`power = floor(friendship / 2.5)`**, 1 at
  friendship 0 and 102 at 255, clamped to `[1, 102]` here so a hand-edited
  happiness above 255 can never overshoot. Friendship is read with the same
  fallback RETURN/FRUSTRATION use (`mon.happiness`, default 70), and the mon is
  resolved through the same generation-aware helper they use (Gen 2's battler
  IS the mon; Gen 1's carries it under `.mon`).
- **Existence check, not blind register.** The pass calls
  `mod.content.moves:get(id)` first and registers ONLY when it answers nil, so
  an authoritative record an engine build or another mod already provides is
  never overwritten -- the same `get`-then-`patch`/`register` idiom
  `wireMovepoolSubEffects` and `modern_combat_protect` use. A missing
  `registerPowerOverride` export asserts loudly rather than booting a move with
  no power.

**Verified.** `luaparse 5.1` clean on `main.lua` and the new file. A new fengari
unit test drives the REAL file against registry doubles that model the record
registry exactly (`get` nil when absent, `register` colliding when present) and
is **30/30**: the register-when-absent branch (all ten record fields), the
never-clobber branch (an existing record is untouched, the override still
registers), the missing-seam assert, and the formula at happiness 0 / 1 / 70 /
128 / 250 / 255 plus clamp-above-255, both battler shapes, absent happiness, and
the full 0..255 range invariant. The record the file builds, CAPTURED from the
file rather than retyped, passes the **real** `Schemas.check` on BOTH
generations with `sureHit` preserved. The engine boot harness reports
**145/145** subsystems (was 144; the new pass is the +1) with 0 guarded
failures. LÖVE cannot run in the preview, so the in-game confirmation is the
user's.

## Transform and Imposter copy the moveset and the ability (4.6.1)

**What changed.** Transform -- and Imposter, which is Transform on switch-in --
now copy the target's **four moves** and the target's **ability**, not just its
species/stats/type. This makes a transformed mon read like the one it copied in
the battle UI (move menu, PP, ability triggers) while its own learned set stays
safe for when the transformation ends.

**The moveset copy.** `combat/modern_transform.lua`'s `applyTransform` used to
copy `target.curMoves` as-is; it now builds a fresh battle-only set via
`buildMoveCopy(battle, target)`:

- The source slots come from `sourceMovesOf(target)` -- `target.curMoves` when
  the target already has a battle moveset, else the target mon's own
  `mon.moves` -- so transforming into an already-transformed (or otherwise
  moveset-overridden) mon copies what that mon is actually using.
- Each copied slot is `{ id, pp = 5, maxPp = <the move's max>, ppUps = 0,
  mimic = true }`. The **current PP is always 5** (the canonical Transform
  value: a copied move starts at 5 PP), and `maxPp` is the move's own maximum
  so the scene's `Combat.maxPpOf` shows `5 / <max>` rather than a flat 5.
- `moveMaxPp(battle, slot)` resolves that maximum from the move's definition:
  the slot's own `maxPp` if present, else `def.pp + ppUps * floor(def.pp / 5)`
  (the game's PP-Up maths), falling back to `slot.pp`/5 when no definition is
  reachable.
- The copy is written to **both** surfaces the two generations read:
  `user.curMoves = moveCopy` (the engine's own battle moveset, which
  `resolveMoveTargets`/`battle:useMove` consult) and `(user.mon or user).moves
  = moveCopy` (what the scene's move menu and `Combat.allMoves` /
  `usableMoves` read). Gen 1's battler is a wrapper around `.mon`, so the same
  table is installed in both places; Gen 2's battler is the mon itself.

**The ability copy + one switch-in trigger.** `copyAbility(battle, user, target)`
sets the user's ability to `abilityIdOf(target.mon or target)` -- the raw mon
carries `.ability` on both generations, and a Gen-1 wrapper may not. When the
id actually **changes**, it calls `fireSwitchInAbility(battle, user)`, so a
copied Intimidate lowers the opposing Attack, a copied weather/terrain/primal
setter sets its field, a copied Trace/RKS-System/Commander/Hospitality/held-item
switch-in effect runs -- **exactly once**, at the moment of the Transform. A
Transform into a mon whose ability you already have fires nothing (the id did
not change).

**The seam.** `abilities/ability_dispatch.lua` gained a small registry:
`registerSwitchInAbility(fn)` (append, returns the fn) and
`fireSwitchInAbility(battle, who)` -- unwrap `who` to its raw mon, `pcall` each
registered fn `(battle, rawMon)`, count successes, warn on failures. **Twelve**
switch-in ability modules register their entry point: `switchin_stat_change`,
`switchin_weather`, `switchin_terrain`, `switchin_primal_weather`,
`switchin_multitype`, `ability_copy` (Trace), `switch_priority_misc`,
`other_misc`, `form_combat_effects` (both RKS System and Commander),
`heal` (Hospitality) and `item_interaction`. This is deliberately narrow --
only switch-in triggers, not every ability hook -- and the raw-mon argument is
required because those engines guard on `mon.hp`/`target.hp`, which a Gen-1
battler wrapper does not carry.

**`move_targeting.lua`'s native fallback now hands out raw mons.**
`nativeFallbackAdjacency` (the Gen-1 positional-adjacency fallback behind
`g9.request_adjacency`) previously returned battler wrappers; it now resolves
`rawSide(battle.enemy/player)` and matches the caster as wrapper **or** raw.
Every consumer in this engine wants raw mons (the switch-in seam, and
`resolveMoveTargets` -> `battle:useMove`), and the scene's own wrap resolves the
caster through `battlerArraysFor` (`b.mon == caster`) and returns raw mons, so
they now agree.

**Revert.** `revertTransform` restores the user's pre-transform state from the
snapshot bucket as before, and now also restores `mon.moves = pre.monMoves` (the
snapshot also records `monMoves`), so the mon's **own four learned moves come
back with their PP-Ups and current PP intact** and its own ability is restored
(`restoreNaturalAbility`). Reversion runs on faint, battle end, or switch-out
(switch-out via the raw-mon `handleBattlerSwitched` path), and restores table
identity where the snapshot had it.

**Verified.** `luaparse 5.1` clean on all 13 edited Lua files. The fengari
harness boots the real `src/g9-battle-engine/` tree: new probe
`probe_transform_round338.lua` (Gen 1, all green) proves the four copied slots
(pp 5, maxPp from the move's own PP + PP-Ups -- PSYBEAM 20, THUNDERBOLT
15+3x3 = 24), that the user's own moves are untouched, that revert restores
table identity + PP + PP-Ups + `curMoves`, that INTIMIDATE is copied and
`restoreNaturalAbility` returns IMPOSTER, that Intimidate **fires once**
(opponent Attack -1, user's stage untouched), that an unchanged ability does
**not** re-fire, and that the raw-mon switch-out restores moves + `curMoves`.
The round-183 `probe_transform_revert.lua` regression is still fully green, and
the full Gen-2 driver on this tree reports **145/145** subsystems with 0
failures and the same three pre-existing `roundFails` as the untouched
baseline -- so this change is neutral to everything else. LÖVE cannot run in the
preview, so the in-game confirmation is the user's.

## Multi-hit moves hit the right number of times on both generations (4.6.2)

**The report.** "multi hit moves like double kick are dealing damage once only,
it should be 2 hits, double check all multi hit moves (bug detected in gen 1,
double check on gen 2)."

**Root cause.** There are two independent reasons a multi-hit move resolved as
one hit, and the engine's existing `multiHit` patching missed both:

- **The patch is content-owned only.** `main.lua`'s `wireMovepoolSubEffects`
  writes a custom `.multiHit` onto records the content registry owns. A move
  left to the cart -- the national_dex takeover explicitly skips ids the ROM
  already defines (`existingIds`) -- never receives it, so a cart-owned Gen-1
  multi-hit move has no `multiHit` for the native effect to fall back to.
- **Gen 2 dispatches the count off the EFFECT STRING, not `move.multiHit`.**
  `gen2/Battle.lua`'s `useMove` reads `Effects.hitCount(def.effect, roller())`,
  and `gen2/Effects.lua`'s `HIT_COUNTS` only knows `EFFECT_DOUBLE_HIT` (2),
  `EFFECT_POISON_MULTI_HIT` (2) and `EFFECT_TRIPLE_KICK` (3), with
  `EFFECT_MULTI_HIT` routed to the 2-5 `multiHitCount`. A Gen-2 move whose
  effect is `EFFECT_NORMAL_HIT` -- the default for a re-owned move whose
  multi-hit behaviour lives only in its `minHits`/`maxHits` record -- is not in
  that table at all and therefore hits once. Eleven Gen-2 moves are in exactly
  that state: BEATUP, DOUBLEIRONBASH, DRAGONDARTS, POPULATIONBOMB, SCALESHOT,
  SURGINGSTRIKES, TACHYONCUTTER, TRIPLEAXEL, TRIPLEDIVE, TRIPLEKICK, TWINEEDLE.

The reference engine already handles this correctly in Gen 1 (`MoveEffects`
carries `hitCount`, and `ATTACK_TWICE_EFFECT` reads `hitsFrom(ctx.move.multiHit
or 2)`), but it is fragile for the same reason -- a cart-owned record without a
`multiHit` is one nil away from a single hit. The engine was also setting
`multiHit` on `MoveEffects.full` rather than `MoveEffects.RECORDS`, which meant
Skill Link (the 2-5 -> 5 ability) was inert.

**The new file.** `combat/multi_hit.lua`, booted from `main.lua` right after
`movepool_sub_effects` and before `move_effect_markers`. It reads the **real**
distribution from national_dex's live `minHits`/`maxHits` for every move,
keyed by both the record id and a separator-stripped spelling (`normalise()`,
so `DOUBLE_KICK`/`DOUBLEKICK` both resolve), and builds a plan: fixed counts
become `{ n, n }`, the 2-5 family becomes the canonical weighted
`{ 2, 2, 2, 3, 3, 3, 4, 5 }` with `isTwoToFive = true`, and anything else is a
flat range. It then enforces that plan at each generation's **own execution
seam** rather than trying to mutate data the engine has already snapshotted:

- **Gen 1** -- wrap `EffectRegistry.runDamaging(battle, ctx, record)` so that
  `ctx.move.multiHit` is set from the plan immediately before the native effect
  reads it. Because this runs even for a cart-owned record that never got a
  patch, every Gen-1 multi-hit move now has its count; and because the value is
  written on the context just before the read, a 2-5 move under Skill Link is
  forced to 5 (`abilityIdOf(ctx.user) == "SKILLLINK"`), fixing the inert ability.
- **Gen 2** -- wrap `Battle2:useMove(attacker, defender, moveId)`. For a planned
  move whose live `def.effect` is **not** one of the natives the engine already
  counts (`EFFECT_MULTI_HIT`, `EFFECT_DOUBLE_HIT`, `EFFECT_POISON_MULTI_HIT`,
  `EFFECT_TRIPLE_KICK`), push the plan onto a LIFO stack and temporarily
  override the module-level `Gen2Effects.hitCount(effect, random)` -- a field
  the native `useMove` resolves at call time -- so that one call rolls the plan
  instead of returning 1. The override is removed with `pcall` + a stack pop,
  the error is re-raised, and the wrapped method's extra returns are forwarded
  (`table.unpack(res, 2)`, with the 5.1 `unpack` fallback) so nothing about the
  call shape changes. Moves that already carry a native multi-hit effect are
  left completely untouched (double-guarded), so nothing double-counts.

The file returns the number of moves it planned and logs
`g9-battle-engine: multi_hit installed (N moved; Gen 1 runDamaging wrap + Gen 2
useMove/hitCount wrap)` at boot.

**Verified.** `luaparse 5.1` clean on `main.lua` and `combat/multi_hit.lua`.
Two fengari harnesses against the real reference engine sources:
`scratch/sim/multihit_fix.js` (+ `multihit_fix_probe.lua`, Gen 1: real
`MoveEffects.lua` + `EffectRegistry.lua` + `g9.multi_hit`) proves DOUBLE_KICK
(`ATTACK_TWICE_EFFECT`) = 2, DOUBLE_KICK with a missing record = 2, FURY_ATTACK
= 2, DOUBLEIRONBASH (effect-less, previously 1) = 2, SURGINGSTRIKES = 3,
TRIPLEKICK = 3, TACKLE control = 1, and Skill Link FURY_ATTACK = 5. The Gen-2
harness (`multihit_fix_gen2.js` + `multihit_fix_probe_gen2.lua`, real
`gen2/Effects.lua` + a mock Battle carrying Gold's own `useMove` loop shape)
proves DOUBLE_KICK via its native `EFFECT_DOUBLE_HIT` = 2, the effect-less
multi-hit moves = 2, SURGINGSTRIKES = 3, TACKLE control = 1, BULLET_SEED
(`EFFECT_MULTI_HIT`) = 2. The full engine boot driver
(`scratch/sim/run-engine.js`) reports **146/146** subsystems on Gen 2 (was 145,
the new subsystem being `multi_hit`) with the same pre-existing `roundFails`,
and 146/146 on Gen 1; an A/B run that disabled the `boot("multi_hit")` call
reproduced the identical failure set at 145/145, confirming the change is
neutral to everything else. LÖVE cannot run in the preview, so the in-game
confirmation is the user's.

## Bide stores for a turn, locks the user, then releases double (4.6.3)

**The report.** "Bide is used and nothing happens ... follow bide logic of pokemon
showdown gen7 ... bide user shouldn't be able to act during bide state duration
... pain split must not contribute to accumulated damage."

**Root cause.** national_dex's takeover hands BIDE a `modernMove` record whose
effect is `NO_ADDITIONAL_EFFECT` (Gen 1) / `EFFECT_NORMAL_HIT` (Gen 2) and whose
power is 0. That record **replaces** the cart's own native BIDE effect id, so the
cart's whole Bide machine -- Gen 1's `BIDE_EFFECT` / `continueBide` /
`applyDamage` storage, Gen 2's `EFFECT_BIDE` / `bideStored` storage -- never
started. Using the move just spent a turn and printed "used BIDE!" with no state
set, which is exactly "nothing happens".

**The new file.** `combat/modern_bide.lua`, booted from `main.lua` right after
`modern_movepool_counter` and wired through `CUSTOM_EFFECT_PATCH` as
`BIDE = "GALAR_BIDE_EFFECT"` (right after OUTRAGE). It re-homes the mechanic under
one cross-generation id, the way `modern_movepool_damage.lua` re-homes
Outrage/Bounce. Registered `kind = "full"`, so Gen 1's `EffectRegistry` offers its
`chooseDamage` the real damaging pipeline and `run` is ignored there; Gen 2's
dispatch calls `run` and returns without touching its own damage path. The
`run` arm is gen2-guarded, so the two arms can never both fire on one generation.

**Showdown gen7.** `data/moves.ts`'s `bide` has a condition with `duration: 3` and
`onLockMove: 'bide'`; the duration ticks down at end of turn and the release fires
on the turn it reads 1. In "continuations still to run after the use turn" that is
exactly **2**: continuation 1 = wait, continuation 2 = release. Both generations
use that same fixed 2 (`BIDE_CONTINUATIONS`), so this build is Showdown's fixed
three-turn move -- NOT the cart's old random 2-3.

**What accumulates.** Showdown's `onDamage` banks every damaging MOVE hit the user
takes (a real Move with a source), excluding source-less chip like recoil and
confusion self-damage; the release deals `totalDamage * 2` as a typeless fixed
hit. Pain Split is the user's explicit example of what must NOT bank: Showdown's
Pain Split rewrites HP rather than dealing damage, and this mod's
`GALAR_PAINSPLIT_EFFECT` likewise writes `mon.hp` directly -- it never reaches
either engine's damage path, so it cannot enter the store (verified by a
source-shape harness check, not by inspection alone).

**Gen 1 keeps the cartridge's machine.** `chooseDamage` only STARTS the store --
it sets the native battler's `bideTurns = 2` / `bideDamage = 0` and returns
`(nil, "%s is storing energy!")`, the same "no damage, one flavour line" shape the
native `BIDE_EFFECT`'s store turn reads. The scene's own executor then runs the
cart's native `BattleState:continueBide` for the wait/release beats -- see the new
Bide arm in `g9-Battle-Scene/native.lua`'s `state:useMove`, placed right after the
trapping branch and before the status gauntlet, which `pcall`s `continueBide` and
then `drainNativeMove("BIDE")` -- and the cart's own `applyDamage` does the
accumulation. That keeps Bide's damage delivery, animation, Substitute and Rage
interactions exactly the native ones. A defensive full wait/release fallback
lives inside `chooseDamage`, reached only if `continueBide` is absent from the
running build (without it a store could never release).

**Gen 2 owns the lifecycle.** `run` sets `battle:volatile(user).bideTurns = 2`,
`bideStored = 0` and `bideMove = moveId` (the field the native `Battle:forcedMove`
reads to keep the user locked on). The native `Battle:dealDamage` already banks
every hit the user takes into `bideStored`, so the release is
`min(0xffff, stored * 2)` routed through `routeThroughBattleDamage` (so Protect,
Wonder Guard and the shared chain still get first refusal) and then delivered via
`battle:dealDamage`. A store that accumulated nothing emits "unleashed energy!"
then "But, it failed!". Because Gen 2's `useMove` decrements PP before any effect
runs and only skips that for the literal `EFFECT_BIDE` id (which this
cross-generation record deliberately does not use), `run` refunds one PP per
continuation -- Bide costs exactly ONE PP for the whole store-and-release, the
same as the cart, and the scene's 0-PP filter never refuses the locked move.

**The lock.** `combat/move_usability.lua` gained a `bideGate` (right after
`healBlockGate`, added to the `moveUsability` `or` chain): while the store is live,
every move BUT BIDE is refused with `flag = "volatile"` and reason
"%s is locked into Bide!". Gen 2 reads the engine's own `volatile.bideTurns`; Gen 1
reads the native battler's `bideTurns` through the scene's mon -> battler map
(`battle.battlersByMon[rawMon]`). The refusal covers both the scene's move menu
and the AI, so the user genuinely cannot act until Bide releases.

**Verified.** `luaparse 5.1` clean on `main.lua`, `combat/modern_bide.lua` and
`combat/move_usability.lua`. Two fengari harnesses, both green:
`scratch/tests/bide_engine_test.lua` + `run_bide_engine.mjs` -- **41/41** (loads
the real `modern_bide.lua` and `move_usability.lua` under mocks: Gen 1 and Gen 2
start/wait/release lifecycles, the routing and fail paths, the per-continuation PP
refund, the lock for non-BIDE moves, and the Pain-Split source-shape exclusion);
`scratch/tests/gen1_bide_e2e_test.lua` + `run_gen1_bide_e2e.mjs` -- **21/21**
(loads the real `native.lua` + `hp_bar.lua` with a mock `BattleState` shaped like
the cart's `continueBide`/`applyDamage`, proving the bide branch advances WITHOUT
`performMove`, spends no PP, emits its lines, releases at 2x, and fails cleanly
when nothing was stored). The full boot driver (`scratch/sim/run-engine.js`)
reports **147/147** subsystems on Gen 2 and 147/147 on Gen 1 (was 146; the new
subsystem is `modern_bide`), with the same pre-existing warnings. The scene
regressions stay green (`scene_guard` 15/15, `forced_switch` 42/42, `white_row`
27/27, `learn_move` 32/32, `scene_prize` 19/19, `special_boss` 41/41,
`exp_share_screen` 46/46, `multihit_hp` 15/15, and the other multi-hit suites).
LÖVE cannot run in the preview, so the in-game confirmation is the user's.

## Manifest description (studio rule)

`manifest.json`'s `description` is capped at 80 characters (a studio rule, so
the Mod Manager row and the generator listing stay readable). The full text
that used to live there is kept in `documentation.md` beside it.

## Wild Illusion crashed the battle on its first disguise roll (4.6.4)

**The report.** A Red-gameplay crash from a player's session: the battle aborted
with `mods/g9-battle-engine/combat/modern_transform.lua:568: bad argument #2 to
'random' (number expected)` the moment a wild Illusion holder entered.

**Root cause.** `wildDisguise` -- the user's wild rule that picks a disguise
species from the current map's own encounter table -- rolled its index with
`rng(battle, 1, #pool)`. `battle.rng` is the engine's inclusive `(lo, hi)` roller
(`src/battle/BattleState.lua`: `function(a, b) return love.math.random(a, b)
end`); passing the battle table as its first argument fed a table straight into
`love.math.random`, which raised the bad-argument error and took the battle down.
Gen 2's separate single-argument `battle.random(n)` is the primitive this call
was mistaken for; every other roll in this mod already calls `battle.rng(lo, hi)`.

**The fix.** One line -- `rng(battle, 1, #pool)` -> `rng(1, #pool)` -- plus a
comment naming the real signature. The lookup's own bounds clamp
(`if index < 1 or index > #pool then index = 1 end`) is unchanged.

**Verified.** `luaparse 5.1` clean on the file; `manifest.json`/`files.json` valid
JSON at 4.6.4. The fengari engine harness boots **147/147 subsystems, 0 guarded
failures**, and the round-179 transform probe
(`scratch/sim/probe_transforms.lua`) drives the real `setupIllusion` wild path.
Its `battle.rng` stub was made faithful to the engine's two-argument shape
(`function(lo, hi) return lo end`) instead of the tolerant one-argument mock that
had hidden this bug, so replaying the pre-fix line now FAILS the probe
(`attempt to compare table with number` at the same statement) while the fixed
line passes -- the wild disguise resolves to `PIDGEY`, never the holder's own
species. LÖVE cannot run in the preview, so the in-game confirmation is the
user's.

## A Gold boot's guarded failures and cross-generation warnings (4.6.5)

**The report.** The user's own Gold boot log: a `GRISEOUS_ORB` item-registration
failure, sixteen `[modern_*] failed to initialize: src/mods/Registry.lua:103:
move_effects already registered: <ID>` lines, a `[modern_transform] no Gen-1
BattleState.effectRecord; skipped` warning, a `[modern_effect_guard] failed to
initialize: ... BattleState.effectRecord missing` line, and a `tera_state:
battle_forms present but its options.get is not a patchable field` warning.

**Root causes.** (1) `combat/move_effect_markers.lua` seeds a bare `kind="full"`
marker for every `moves.<id>.effect` in the registry and was booted right after
`multi_hit`, i.e. before every `modern_*` module; a move whose `.effect`
`wireMovepoolSubEffects` had already repointed at a custom id got a marker seeded
for that id, and the module registering the real record then hit
`Registry.lua:103`'s duplicate guard. (2) `modern_held_items_phase2.lua`
registered its item list unconditionally, so `GRISEOUS_ORB` -- owned by
battle_forms at priority 80 -- collided. (3) On Gold `src.battle.BattleState` is
the engine's Gen-2 facade, which has no Gen-1 `effectRecord`, so the guard's
`assert` and the transform file's skip both fired. (4) `mod:find(id)` answers a
`{id, version, exports}` handle, never another mod's own mod table, so
`mod.find("battle_forms").options` is nil by design and the tera gate could never
have patched `tera_type`.

**The fixes.** (1) `move_effect_markers` moved to the very end of the boot, after
`modern_effect_guard`; it seeds only ids nothing else claimed (a stock boot
seeds exactly `NO_ADDITIONAL_EFFECT`). (2) The item loop checks
`mod.content.items:get(def.id)` first and counts an already-registered id as
present. (3) `modern_effect_guard.lua` returns cleanly with one `info` line (and
`effectGuardInstalled = false`) when the live `BattleState` has no
`effectRecord`; `modern_transform.lua`'s skip is an `info` too. (4)
`tera_state.lua` logs the unreachable-options fact once at `info` and documents
the handle design; the per-mon `mon.battleFormsTeraType` stamp
`ensureTeraStamps` maintains is the real ownership seam.

**Verified.** `luaparse 5.1` clean; `manifest.json`/`files.json` valid at 4.6.5.
The fengari harness boots **147/147 subsystems, 0 guarded failures** both in its
default mode and with the new `faithfulMoves` stub, which gives the harness a
real `moves` record store (whose `patch`/`register`/`each` behave like the live
registry) and a `move_effects` registry that errors on a duplicate `register`
exactly like `Registry.lua:103`. Reconstructing the old boot order under that
stub reproduces the user's failures (`137/147`, ten guarded failures, 49 seeded
markers including every collided id); the fixed order boots `147/147` with
`NO_ADDITIONAL_EFFECT` alone. LÖVE cannot run in the preview, so the in-game
confirmation is the user's.

## A Gold boot is silent: the four Gen-1-only facade reads go through rawget (4.6.6)

**The report.** A Gold boot still logged four warnings after 4.6.5:
`src.battle.BattleState.newWild has no Gen 2 backing`, and the same for
`newTrainer`, `performMove` and `effectRecord`.

**The cause.** On a Gold boot `require("src.battle.BattleState")` returns the
engine's `Gen2Compat` facade, and that facade's `__index` warns ONCE per member
the moment a mod READS a name Gold cannot back (`Gen2Compat.lua`'s `warnOnce`).
This engine read each of those four at boot only to ask a yes/no question --
"does the real Gen-1 BattleState carry this member, so should I install my
Gen-1 wrap?" -- in the `type(BattleState.performMove) == "function"` shape. The
read itself was the warning; and for `performMove` the read was followed by a
WRITE of a wrapper onto the facade -- a write nothing on a Gen-2 boot reads.

**The fix.** Every such probe now reads through `rawget(BattleState, "...")`.
`rawget` cannot invoke `__index`, so on Gold the name reads `nil` and the Gen-1
wrap is skipped cleanly; on Gen 1 the genuine `src/battle/BattleState.lua`
carries all four as raw keys (`newWild` :770, `newTrainer` :844, `effectRecord`
:2687, `performMove` :4217), so the member is found and every wrap installs
exactly as before. Where the read fed an install (the `performMove` wraps, and
`modern_transform`'s `newWild`/`newTrainer`), the install is now additionally
gated by `if type(native) == "function" then`, so a Gold boot never writes a
dead wrapper onto the facade either. Touched: `interaction_memory.lua`,
`modern_combat_protect.lua`, `modern_effect_guard.lua`, `modern_move_flags.lua`,
`modern_movepool_damage.lua`, `modern_weather.lua`, `modern_transform.lua`,
`wild_modern_ivs.lua`, `trainer_modern_stats.lua`, `gimmick_dynamax.lua` and the
six `abilities/engine/*` files (`aroma_veil`, `dancer`, `form_combat_effects`,
`good_as_gold`, `magic_bounce`, `pressure`).

**Verified.** `luaparse 5.1` clean on all sixteen files; a repo-wide scan for
the four names in code finds no remaining non-`rawget` read off `BattleState`.
The fengari harness's `src.battle.BattleState` stub gained `performMove` (the
real Gen-1 class has it), so the harness mirrors reality: the engine boots
**147/147 subsystems, 0 guarded failures** in BOTH its default and Gen-1 modes,
and the Gen-1 Protect Part-D probe is still green (blocked / max-guarded /
unprotected / bypass / stale). LÖVE cannot run in the preview, so the in-game
confirmation is the user's.

## Ally-side spread moves: Life Dew, Lunar Blessing, Howl, Coaching and Dragon Cheer reach adjacent allies (4.6.7)

**The report.** "battle engine doesn't have defined spread moves to ally side?
I know earthquake works, but lifedew and other status/recovery moves that affect
adjacent allies as per pokemon showdown aren't working that way yet?"

**The cause.** An ally-side move (`user-and-allies` / `all-allies`) is delivered
ONCE, and the effect handler is what walks the user's side --
`combat/move_targeting.lua`'s `resolveMoveTargets` deliberately expands only the
two OFFENSIVE spread archetypes (`all-opponents` / `all-other-pokemon`, which is
why Earthquake always worked). Several ally-side effects already did this through
the adjacency seam (Aromatherapy / Heal Bell / Jungle Healing via
`combat/modern_party_support.lua`; Gear Up / Magnetic Flux via
`modern_movepool_stages.lua`), but four did not: **Life Dew** and **Lunar
Blessing** healed/cured `n.user` only (with stale comments claiming "this engine
has no ally slot to also heal"), **Howl** was a plain self +1 Atk, and
**Coaching** was wired nowhere at all (its national_dex record is a power-0
status move, so `installMovepoolEffects`'s `battle.damage_dealt` listener never
fired for it). **Dragon Cheer** sat in `combat/structural_exemptions.lua` as
unobservable ("no allied battler => empty target set").

**The fix.** All five now read the user's real adjacent side through
`mod.exports.requestAdjacency` (the engine's N-way roster primitive; native
two-battler fallback when no scene mod is present), so the recipient set is
exactly the user (+ allies) in singles, the literally-adjacent slots in
doubles/triples, and the whole team in the 4v4 / boss / horde layouts:

- `combat/modern_movepool_damage.lua`: Life Dew heals the user and every
  adjacent ally by **1/4** max HP (Showdown `heal: [1, 4]`; the 1/2 an earlier
  note claimed was simply wrong -- no generation ever raised it), and Lunar
  Blessing heals the user and every adjacent ally by 1/4 and cures each. Both
  emit one line per recipient; Life Dew fails only when nobody needed healing.
- `combat/modern_movepool_stages.lua`: a new `teamBoostMove` helper applies a
  stat change to each of the user + adjacent allies. **Howl** uses it (Atk +1
  to the side) and **Coaching** uses it with `includeUser = false` -- Atk +1 /
  Def +1 to every adjacent ally, never the user (Bulbapedia's real rule, which
  Showdown's `adjacentAlly` and national_dex's `user-and-allies` each only half
  describe; fails with no ally).
- `combat/modern_crit_override.lua`: **Dragon Cheer** puts a switch-scoped
  `dragonCheer` volatile on every adjacent ally (never the user), with
  `hasDragonType` frozen at application time, and a new `dragoncheer`
  crit-stage modifier gives +1 (+2 for a Dragon-type recipient). It skips an
  ally already holding Focus Energy and fails when nobody took it. It is retired
  from `structural_exemptions.lua`, which now holds exactly Ally Switch, Follow
  Me, Rage Powder, Helping Hand and Spotlight. `status_condition_cleanup.lua`
  clears the two fields on switch-out.

`main.lua`'s `CUSTOM_EFFECT_PATCH` gained `COACHING` and `DRAGONCHEER`.

**Verified.** `luaparse 5.1` clean on all six touched Lua files; both JSONs
valid. A new fengari harness (`scratch/tests/ally_spread_test.lua` +
`run_ally_spread.mjs`, loading the REAL four files under mocks) is **20/20**:
Life Dew heals 1/4 in singles, only the adjacent ally in doubles, and the whole
side when the adjacency seam reports it, failing when nobody needs it; Lunar
Blessing heals+cures the adjacent side and leaves the far slot alone; Howl
boosts the side; Coaching boosts the ally but not the user and fails alone;
Dragon Cheer tags allies (Dragon flag frozen), skips Focus Energy and its crit
modifier returns +1/+2/0; the exemption registry keeps exactly the five
remaining ids. The engine's full boot is unchanged: **147/147 subsystems, 0
guarded failures** on both a Gen 2 and a Gen 1 boot. LÖVE cannot run in the
preview, so the in-game confirmation is the user's.

## Ally-targeting moves reach adjacent allies, and Imposter only ever copies the foe opposite its slot (4.6.8)

**The report.** "moves like helping hand, heal pulse and others (selected
adjacent ally) and transform (any adjacent pokemon including allies, right now
only can target enemies). right now, moves that should usually be able to
target allies, can't in scene, we need to adjust cursor to allow it. imposter
fix: Double Battles: A Pokemon with Imposter will automatically transform into
the opponent directly opposite its position. If no opponent is standing in that
exact slot, the ability fails completely and will not target your ally."

**The cause (two separate bugs).** (1) The scene's target picker has offered
allies since round 26 (`battle_screen.lua`'s `Screen:isAllyTargetable`,
`Screen:reachableAllies`, allies-first candidate list), and its authority is the
engine's own `mod.exports.isAllyTargetable`. That export only recognised the
inherently ally-directed archetypes (`ally` / `user-or-ally`) plus
selected-pokemon HEAL records, so **Heal Pulse / Helping Hand worked through the
heal half but every other selected-pokemon status/support move -- Transform,
Thunder Wave, Toxic, Trick, Skill Swap, Instruct, ... -- fell through and the
picker listed foes only**, which is exactly the reported "moves that should be
able to target allies can't in scene". (2) Imposter's transform target came from
`combat/modern_transform.lua`'s `opposingOf`, which fell back through
`battle.player` / `allActiveBattlers` -- an arbitrary/own-side mon in a doubles
fight. Worse, the scene builds its own battle model (`native.lua`'s
`buildBattle`) and never called the engine's `newWild` / `newTrainer`
constructors, so a double-battle Imposter never fired at all (or picked a wrong
mon), and there was no "directly opposite slot" question the engine could ask.

**The fix -- engine side.**

- `combat/move_targeting.lua` gained **`isAllyOnlyMove(moveId)`**: true for the
  inherently ally-directed archetypes (`ally` -- Helping Hand, Aromatic Mist;
  `user-or-ally` -- Acupressure) and for the selected-pokemon HEAL records
  (`healing > 0` or `category == "heal"` -- Heal Pulse, Floral Healing). A move
  in this set must offer **no foe** in the picker, and in singles it is USED and
  FAILS rather than being silently applied to the lone enemy.
- **`isAllyTargetable(moveId)`** was rewritten as `isAllyOnlyMove` **OR**
  (selected-pokemon AND `damageClass == "status"`). national_dex's own
  `damageClass == "status"` is the authoritative non-damaging marker, so it
  correctly admits Transform, Thunder Wave, Toxic, Trick, Skill Swap, Instruct
  and the rest of the status/support family while excluding a variable-power
  DAMAGING move like Seismic Toss. **Pollen Puff is deliberately excluded**:
  its only damaging ally-capable move, its ally half (a 50% heal) is still an
  unimplemented structural no-op in this engine (`combat/modern_status_moves.lua`
  records it), so offering an ally would run the native DAMAGE path on that
  ally. It stays foe-only until its heal half is wired.
- `combat/move_targeting.lua` also gained **`requestOpposite(battle, caster)`**
  (with `nativeFallbackOpposite`), the position query Imposter needs. It
  forwards to a battle scene's `g9.request_opposite` hook -- the same seam
  discipline as `requestAdjacency`, so this engine still tracks no battlefield
  position itself -- and otherwise answers the native two-battler case (a 1-vs-1
  fight's one other battler IS the one directly opposite). It returns the single
  directly-opposite foe, or **nil**, and **never an ally**.
- `combat/modern_transform.lua` replaced `opposingOf` with
  **`oppositeOpponentOf(battle, battler)`**, which asks `requestOpposite` and
  returns nil (nothing happens) when that exact opposing slot is empty or its
  occupant is not standing. The IMPOSTER branch of `runSwitchInAbilities` uses
  it and simply no-ops on nil -- the Showdown `if (!target) return false` rule.
  `opposingWho` is kept in the signature for the callers that pass one but is
  ignored for Imposter.

**The fix -- scene side.** `battle_screen.lua` gained `Screen:isAllyOnly(picked)`
(trusts the engine's `isAllyOnlyMove`, with a move-def fallback on a stale
engine), broadened `Screen:isAllyTargetable`'s fallback to also accept
`damageClass == "status"` / `power == 0`, and rewrote the A-branch candidate
build so an ally-only move offers **only** `reachableAllies` (empty in singles
-> used-and-failed, never applied to the lone enemy), an ally-targetable move
offers **allies first then foes**, and everything else stays foe-only. It also
added a `mod.hooks:wrap("g9.request_opposite", ...)` that answers from the
screen's own index-aligned `playerBattlers` / `enemyBattlers` arrays (matching
the RAW mon the engine hands in by `b.mon == mon`), and a **switch-in sweep at
the end of `Screen:finishIntro()`**: the scene now runs the engine's
`runSwitchInAbilities` for every active battler once the intro is over (its
model-building path never called the engine constructors), which is what makes a
double-battle Imposter fire at all -- and, with the position seam, fire at the
right mon.

**Verified.** `luaparse 5.1` clean on all three touched Lua files
(`combat/move_targeting.lua`, `combat/modern_transform.lua`,
`battle_screen.lua`) and both JSONs valid. Two new fengari probes:
`scratch/sim/probe_ally_target.lua` (rules + the position query) is all-green --
`transform_only=false / transform_tgt=true / helpinghand_only=true /
helpinghand_tgt=true / healpulse_only=true / healpulse_tgt=true /
pollenpuff_only=false / pollenpuff_tgt=false / thunderwave_only=false /
thunderwave_tgt=true / seismictoss_only=false / seismictoss_tgt=false /
aerialace_only=false / aerialace_tgt=false / unknown_tgt=false /
transform_needsPick=true / opposite_from_player=true / opposite_from_enemy=true /
opposite_none=true / opposite_stranger=true` -- and
`scratch/sim/probe_imposter_opposite.lua` (end-to-end `runSwitchInAbilities`
through a stand-in `g9.request_opposite`) is **14/14**: an Imposter copies the
ally-column foe by its own stat/type, the fainted opposite slot makes it do
nothing (never the other foe, never the ally), an enemy-side Imposter answers in
reverse, and the native fallback transforms in a 1-vs-1 and fails with no
opposing battler. The engine's full boot is unchanged: **147/147 subsystems, 0
guarded failures** on both a Gen 2 and a Gen 1 boot. LÖVE cannot run in the
preview, so the in-game confirmation (a doubles battle: Transform / Helping
Hand / Heal Pulse offer an adjacent ally, and an Imposter copies the foe in its
own slot) is the user's.


## Combat narration routes through `Strings()` (4.7.0)

Every battle message this engine builds now goes through the engine's own
`Strings("<template>", args)` (or `Strings("<text>")`) call instead of Lua
string concatenation.  The engine's `Strings` looks its source up in
`Data.strings`, the catalog a translation mod installs through
`mod.content.strings:override(key, value)` -- keying on the English source
means any translation the mod already carries applies verbatim, and a source
with no entry falls through to English, so nothing can render a raw key and
no arity mistake can crash a turn (`Strings` falls back to the source when a
translation's `%`-directive count disagrees).

**Why.** The engine had two kinds of message: the ones it already emitted via
`Strings` (so the translation mod reached them) and the ones our modules built
by concatenation (`self:monName(x) .. "'s fully paralyzed!"`), which the
translation mod could never see.  This round converts the second kind: around
120 call sites across `combat/` and `abilities/engine/`.

**What was converted.** Status turn-loss (paralysis/sleep/freeze, Gen 1 and
Gen 2), trap moves (`can't escape now!`), hazards (Spikes, pointed stones,
sharp steel), drag-out, MIST, Forewarn, Cursed Body, item interactions (Fling,
Knock Off, Covet, Harvest, the berry-eat/status/confusion lines), terrain /
weather / room start and end lines, the Protect / Endure / `But it failed!`
family, side conditions and the four guards, Future Sight / Doom Desire,
Psychic Terrain, Trick Room / Wonder Room / Magic Room, the `Go!` and
`X\nused Y!` announcements, and the G-Max residual team lines.

**Which source each site uses.** Where the engine already has the exact
wording (its own Gen-2 `Battle.lua`, `BattleState.lua`, `Status.lua`,
`MoveEffects.lua` &c. carry the canonical `Strings` literals), the call is
converted to that key so the translation mod's own catalog applies.  Where the
message is Showdown-only with no engine equivalent, the mod's existing English
is kept as the source -- still routed through `Strings`, so a future catalog
entry can cover it.

**Verification.** `luaparse` 5.1 parses all 212 engine Lua files; a
first-argument/argument-count audit over all 378 `Strings(...)` calls finds
no unresolved `%`-directive; and a fengari harness against
`src/core/Strings.lua` confirms a cataloged source translates, `%s` slots
fill from the arguments, an uncataloged source passes through, and a
translation whose `%`-directive count disagrees falls back to the English
source instead of raising. The same audit also caught ten older call sites
that passed an empty-string placeholder for a `%s` (so the actor's name
rendered blank, or the raw `%s` showed) -- each now passes the real display
name via `displayNameFor`: Aqua Ring, Leech Seed, Ingrain, Yawn, Disable,
Embargo / Heal Block / Throat Chop, Telekinesis and Swallow.

## License

GNU General Public License v3.0 (GPL-3.0). Copyright (C) 2026
[tectorifter](https://github.com/tectorifter/). The full text ships as
`LICENSE` beside this file.

## Third-party notices

Pokemon and all related names, characters, creatures, moves, items, sprites and
other assets are the property of Nintendo, Creatures Inc., GAME FREAK inc. and
The Pokemon Company. This is an unofficial fan mod and is not affiliated with,
sponsored by or endorsed by them; it owns only its own Lua source (see
`LICENSE`). The engine's combat formulas and move / ability / item behaviour are
a derivative of **Pokemon Showdown** (`smogon/pokemon-showdown`), used under the
MIT License. The full notices -- the Pokemon IP statement, the Showdown
attribution with its MIT licence text, and the companion-mod credits -- ship in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
