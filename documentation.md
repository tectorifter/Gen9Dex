# g9-battle-engine — manifest description

This file records the full `description` for the **g9-battle-engine** mod
(`manifest.json`). The manifest's own `description` field is capped at
**80 characters** (a studio rule, so the Mod Manager row and the generator
listing stay readable), so the complete text lives here and the manifest
carries only a short summary.

## Current description (full)

4 gimmicks, updated battle engine -- moves/stats/gigantamax combat only, no sprites, no overworld spawns, no followers. 4.4.1: the Protect family is turn-scoped (no stale shield after a failed roll) and blocks status-move effects. 4.4.2: a new combat/move_effect_markers pass seeds the boot generation's move_effects id space with the no-op markers modded move records reference (Gen 1's NO_ADDITIONAL_EFFECT, and any id a re-owned national_dex move carries), so the loader's cross-reference pass resolves them instead of logging one unresolved-reference line per move on a Gold boot. 4.4.3: that sweep now walks the content API's own merged view (`moves:each()`) instead of a raw `moves.ops` op log no mod is ever handed -- `mod.content.moves` is Loader:_contentApi's closure, whose whole surface is register/override/patch/remove/get/each -- so it seeds the effect ids of peer-written move records too; battle_forms' `STONEEDGE.effect = "EFFECT_ALWAYS_CRIT"` was the one line still standing after 4.4.2. The op-log walk stays as the fallback for a raw registry. 4.4.4: resolveTurnActions no longer resolves a spread move that expanded to zero live targets to NOTHING -- the guard was `#live == 0 and failed`, and the spread path never sets `failed`, so a Surf with no adjacent opponent silently did nothing, spent no PP and printed no line; it now announces the move and prints "But it failed!", exactly like the single-target no-recipient case. An `actingBattlers` entry may now also carry `fail = true` (the battle scene's own positional-adjacency refusal): both resolveTurnActions and the Gen-1 resolveNextActionForGen1 announce and fail that ONE action at its own place in the order while every other actor still resolves -- which is what stops one un-reaching triple-battle slot from skipping the rest of its team's turn. 4.4.5: the __g9Dynamaxed marker battle_forms' dynamax_applied/reverted pair drives is now strictly battle-scoped -- swept over the WHOLE party at battle.started (self-healing a save that already carries a stale marker) and battle.ended, the leaving mon at battle.battler_switched and the fainter at battle.fainted -- because battle_forms' own battle-end teardown clears silently, its form sweep emits no dynamax_reverted, and the battle scene raises no battle.fainted at all, so a Dynamaxed mon that was benched or fainted at battle end kept the marker into the save and stayed permanently immune to flinch and every status (a 100% flinch move like Fake Out simply stopped landing). 4.4.6: the POKeMON CENTER nurse is taken over on BOTH generations (overworld/pokecenter_heal.lua). Healing now full-heals every party member to its MODERN max HP -- the same ModernStats.ensure + recalcAll pair the TRAIN editor uses, mirrored into Gold's maxHp/specialAttack/specialDefense, and eggs are skipped outright so a center heal can never resurrect one -- the pokeball-into-the-machine sequence is never played (Gen 1's own healAnim is bypassed, Gen 2's startHealMachineAnim resumes instantly), the player turns away to face south when the conversation ends, and the POKeRUS report is preserved with ALL of its sequencing (the ROM's own nurse text, the ENGINE_CAUGHT_POKERUS engine flag and the SPECIALCALL_POKERUS phone call). The chat itself can be shortened to a single line ("We restore your tired Pokemon to full health."), with POKeRUS still reported first, gated on g9-gui's new SHORT HEAL CHAT option (default ON; the shortening is also the default when g9-gui is absent). Gen 2 recognises the nurse by the SPRITE_NURSE sprite (the script's jumpstd PokecenterNurseScript is a second, independent signal) and takes the talk over through the documented OverworldController.talkTo facade seam; with the option OFF the cart's own extracted PokecenterNurseScript runs untouched and a per-step watcher turns the player south once it settles. 4.5.0: all evolution handling is removed -- this engine no longer patches species evolutions, registers evolution methods (HAPPINESS + the exotic stubs), registers evolution items, or hooks ItemEffects for them, and no longer ships the 1025-species evolution data; evolution is a separate mod's job (g9-evolutions). 4.5.3: a POKeMON CENTER heal's modern max HP is no longer silently replaced by the native DV-derived one on the next party-menu open / battle start (Gold) or summary/box open (Gen 1) -- which could leave a healed mon at "max - 1". ModernStats.recalcAll now stamps the mon as modern-owned and the Gen 2 Mon.refreshStats wrapper (plus the level-up and battle-start re-applies) re-apply the modern block for any such mon, carrying the current HP across; the heal and the Gen 1 EV-yield/wild recalcs also mirror Gen 1's single `special` key so the engine's own Stats.ensure never rebuilds the block from DVs. 4.5.4: the engine no longer sets ANY trainer's team -- the generated gym/Elite Four/Champion/Red roster data (`overworld/gym_trainer_teams.lua`) and its installer (`overworld/install_gym_trainer_teams.lua`) are removed, so those 22 trainer classes revert to the game's own rosters, and the installer's special IV-31/EV-85/per-species-nature profile goes with it. Team setting now happens only through the public `registerTrainer` API (and the `registerTrainerStatsProvider` chain and the `trainer.party` hook), which are untouched: the engine processes the stats of the teams it is handed and never carries a roster of its own. 4.5.5: a self-switch (U-turn / Volt Switch / Flip Turn / Teleport) in a scene-driven battle now PAUSES the round instead of ending it -- `combat/switch_primitives.lua` parks the leaving mon on `battle.__g9PendingSelfSwitch`, `combat/turn_order.lua`'s `resolveTurnActions` stops there and emits a `pivot-switch` event when the paired scene advertises `battle.__g9SceneHandlesPivotSwitch`, and the new `mod.exports.resumeAfterPivot(battle, incoming, outgoing)` re-enters the SAME round, repointing every not-yet-acted actor whose chosen target was the mon that left onto the mon the scene sent in. Teleport (-6 priority, acts last) therefore leaves nothing pending -- its switch-in meets only entry hazards and field conditions -- while a fast U-turn leaves the opponent's move pending and it lands on the switch-in. 4.6.0: a new combat/modern_fallback_moves.lua pass supplies move records the running move data omits -- today Pika Papow (PIKA_PAPOW), the fourth Let's-Go partner-Pikachu move national_dex does not carry -- registering an Electric/special record (power placeholder 1, accuracy 100, 20 PP, and the engine's own sureHit flag) only when the move registry has no record for that id, and wiring its real power through registerPowerOverride: floor(friendship / 2.5), clamped to 1..102, read like Return/Frustration (mon.happiness, default 70); an authoritative record is never overwritten. Opt-in: a scene that does not advertise the flag keeps the old end-the-round-at-the-switch behaviour, and native runTurn is never involved. 4.6.1: Transform and Imposter now rewrite the user's battle moveset to the target's four moves -- each copied slot kept at 5 current PP carrying the move's own max PP -- and copy the target's ability, firing the copied on-switch-in ability effect exactly once (Intimidate and the other switch-in stat/weather/terrain/type setters, Trace, etc.), so a transformed mon behaves like the one it copied; the user's real four learned moves (their PP-Ups and current PP intact) and its own ability come back the instant the transformation ends -- faint, battle end, or switch-out. 4.6.2: multi-hit counts are now guaranteed on both generations -- combat/multi_hit.lua builds the real hit distribution from national_dex's live minHits/maxHits and enforces it at each generation's own execution seam (Gen 1's EffectRegistry.runDamaging sets ctx.move.multiHit immediately before the native read; Gen 2 wraps Battle:useMove and its Effects.hitCount for moves whose effect isn't already EFFECT_DOUBLE_HIT/EFFECT_MULTI_HIT/EFFECT_POISON_MULTI_HIT/EFFECT_TRIPLE_KICK), so Double Kick and all 32 multi-hit moves hit the right number of times, and Skill Link's 2-5 -> 5 now applies on Gen 1 too. 4.6.3: Bide works again -- national_dex's takeover had replaced the cart's own BIDE effect with a power-0 no-op record, so the native store-and-release machine never started and the move "did nothing"; the new combat/modern_bide.lua re-homes it as the cross-generation GALAR_BIDE_EFFECT (wired through CUSTOM_EFFECT_PATCH). It follows Showdown gen7's bide (duration 3 = a fixed two continuations after the use turn: one wait, then the release), banks only real damaging move hits the user takes, and releases `stored * 2` as a routed typeless fixed hit. Gen 1 starts the store on the native battler (bideTurns/bideDamage) and lets the cart's own BattleState:continueBide/applyDamage run the wait and release; Gen 2's `run` owns the whole lifecycle through battle:volatile and the native dealDamage bideStored accumulator, refunding one PP per continuation so Bide costs exactly one PP. Pain Split writes mon.hp directly and never enters either damage path, so it cannot be banked. combat/move_usability.lua gained a Bide gate that refuses every move but BIDE while the store is live, on both generations, so the user genuinely cannot act during Bide. 4.6.4: wild Illusion no longer crashes the battle -- combat/modern_transform.lua's wildDisguise roll called rng(battle, 1, #pool), but battle.rng is the engine's inclusive (lo, hi) roller (src/battle/BattleState.lua: `function(a, b) return love.math.random(a, b) end`), not a (battle, lo, hi) helper; passing the battle table fed it straight to love.math.random and aborted the fight with "bad argument #2 to 'random' (number expected)". The roll is now rng(1, #pool). 4.6.5: a Gold boot is clean. combat/move_effect_markers.lua now boots LAST, after every modern_* module has registered its real record, so the sweep stops seeding a bare marker for an id a module is about to register and the sixteen `move_effects already registered` guarded failures are gone (a stock boot now seeds only NO_ADDITIONAL_EFFECT). combat/modern_held_items_phase2.lua skips an item id another mod already registered (GRISEOUS_ORB, owned by battle_forms) instead of reporting it as a failure. combat/modern_effect_guard.lua and combat/modern_transform.lua both skip the Gen-1-only effectRecord guard cleanly, at info, when src.battle.BattleState is the Gen-2 facade. gigantamax/tera_state.lua logs once at info that battle_forms' `options.get` is not a patchable field -- the loader's mod:find answers a {id, version, exports} handle, never another mod's own table -- so TERA TYPE stays battle_forms' and the per-mon battleFormsTeraType stamp remains the real seam. 4.6.6: a Gold boot is now SILENT -- the four remaining "has no Gen 2 backing" denials (`BattleState.newWild`, `newTrainer`, `performMove`, `effectRecord`) no longer fire. Each is a Gen-1-only member of the engine's Gen2Compat facade, whose `__index` warns once when read; this engine touched them only to decide whether its Gen-1 wraps should install (e.g. `type(BattleState.performMove) == "function"`), so every such probe now reads through `rawget`, which never invokes the facade's `__index`. On Gold the member is absent (nil), so the Gen-1 wrap is skipped and no dead wrapper is written to the facade; on Gen 1 the genuine `src/battle/BattleState.lua` carries all four as raw keys (`newWild` :770, `newTrainer` :844, `effectRecord` :2687, `performMove` :4217), so every wrap still installs exactly as before. No behaviour changes on either generation. 4.6.7: ally-side ("user-and-allies" / "all-allies") status and recovery moves now reach the user's adjacent allies. Life Dew heals 1/4 of max HP -- corrected from a mistaken 1/2; Showdown's own `heal: [1, 4]` and national_dex's `healing = 25` agree -- to the user and every adjacent ally, and Lunar Blessing heals 1/4 and cures the status of the user and every adjacent ally; both walk the user's real side through `requestAdjacency` (the same adjacency seam Aromatherapy / Heal Bell / Jungle Healing already used). Howl is a side-wide Atk +1, and Coaching -- previously wired nowhere at all -- is now Atk +1 / Def +1 to every adjacent ally but never the user (the real game rule; it fails when no ally is present). Dragon Cheer applies its switch-scoped `dragonCheer` crit volatile to every adjacent ally (+2 for a Dragon-type recipient) and is retired from the structural-exemption registry, which now holds exactly Ally Switch, Follow Me, Rage Powder, Helping Hand and Spotlight. The recipient set is the engine's own real adjacency, so all five behave correctly in singles (the user alone), doubles/triples (literally-adjacent slots) and the 4v4/boss/horde layouts (the whole team), with the two offensive spread archetypes (Earthquake, Surf) untouched. 4.6.8: the ally-targeting rules are widened from "the ally archetypes plus the selected-pokemon heals" to every NON-DAMAGING selected-pokemon move (national_dex damageClass == "status"), so Transform -- any adjacent Pokemon including an ally -- and the whole status/support single-target family (Thunder Wave, Toxic, Trick, Skill Swap, Instruct, ...) can be aimed at an adjacent ally in the battle scene's target picker, while a variable-power damaging move like Seismic Toss stays foe-only; a new isAllyOnlyMove marks the moves (Helping Hand, Aromatic Mist, Acupressure, Heal Pulse, Floral Healing) that must offer NO foe at all and be used-and-failed in singles rather than applied to the lone enemy, and Pollen Puff stays foe-only because its ally-heal half is still an unimplemented no-op. Imposter now transforms only into the foe DIRECTLY OPPOSITE the user's own slot: a new requestOpposite position query forwards to a battle scene's g9.request_opposite hook (native two-battler fallback, and never an ally), and modern_transform.lua's IMPOSTER branch does nothing at all when that exact slot is empty -- the Showdown rule. The battle scene (g9-Battle-Scene 4.5.1) answers the hook from its index-aligned grid, offers allies (allies first) for ally-targetable moves and allies as the sole candidates for ally-only moves, and runs the engine's switch-in abilities once the intro finishes so a double-battle Imposter fires. 4.7.0: every battle message the engine builds is now constructed through the engine's own `Strings("<template>", args)` (or `Strings("<text>")`) instead of Lua string concatenation, so an installed translation mod's catalog (`mod.content.strings`) reaches it -- the fix for combat narration that stayed English under a translation. Around 120 call sites across `combat/` and `abilities/engine/` were converted (status turn-loss, trap/hazard damage, drag-out, MIST, Forewarn, Cursed Body, item interactions, terrain/weather/room start+end lines, the Protect/Endure/"But it failed!" lines, side conditions, Future Sight/Doom Desire, the `Go!`/`used` announcements and the G-Max residual lines). Each source is the engine's own wording where one exists (so the translation mod applies verbatim) and the mod's own English otherwise, and any message with no catalog entry falls through to its English source.

## Manifest summary (<= 80 chars)

Modern battle engine: moves, stats, gimmicks and overworld fixes.

## History

- **4.7.2** adds a third-party-IP notice. A new `THIRD-PARTY-NOTICES.md` now
  ships with the mod: it states that Pokemon and all related names and assets
  belong to Nintendo, Creatures Inc., GAME FREAK inc. and The Pokemon Company,
  that this is an unofficial fan mod with no affiliation, and that only the
  mod's own Lua is the author's work (GPL-3.0-or-later). It also carries the
  full **MIT License** of **Pokemon Showdown** and attributes the engine's
  combat formulas, turn order and move / ability / item behaviour to that
  project's server source. No code change.
- **4.7.1** relicenses the mod under the **GNU GPLv3** (it was MIT): the shipped
  `LICENSE` is now the full GNU General Public License, version 3, copyright
  **tectorifter** (<https://github.com/tectorifter/>). No code change.
- Full text moved here and the manifest `description` shortened to the
  summary above (doc/description-only change, no version bump for the move
  itself). The same edit added `g9-gui` to `optional_dependencies` and is
  released as 4.5.1 alongside the SHORT HEAL CHAT rewire.
- **4.5.3** -- the center-heal "max - 1" fix (modern-owned HP is re-applied
  after a native stat recompute). The full description above is extended with a
  `4.5.3:` note; implementation notes live in `README.md` ("Center heal keeps
  its modern max").
- **4.5.4** -- the engine stops setting trainer teams: `overworld/
  gym_trainer_teams.lua` + `overworld/install_gym_trainer_teams.lua` and their
  two `main.lua` boot calls are removed, restoring the game's own gym/Elite
  Four/Champion/Red rosters. The public team API (`registerTrainer`,
  `registerTrainerStatsProvider`, the `trainer.party` hook) is untouched. The
  full description above is extended with a `4.5.4:` note; implementation notes
  live in `README.md` ("The engine no longer sets trainer teams").
- **4.5.5** -- pivot self-switch pause/resume: `battle.__g9PendingSelfSwitch`
  (set by `requestSwitch`), `battle.__g9PivotPause`, the `pivot-switch` event
  and the new `mod.exports.resumeAfterPivot` let a scene perform a mid-round
  self-switch and finish the SAME round, so the actions still pending follow the
  slot to the switch-in. The full description above is extended with a `4.5.5:`
  note; implementation notes live in `README.md` ("Pivot self-switch pause /
  resume (4.5.5)").
- **4.6.0** -- hardcoded fallback move records: `combat/modern_fallback_moves.lua`
  registers PIKA_PAPOW -- the fourth Let's-Go partner-Pikachu move national_dex
  omits -- when the move registry has no record for it, and wires its
  friendship-based power (`floor(friendship / 2.5)`, clamped to 1..102) through
  `registerPowerOverride`; the record carries the engine's own `sureHit` flag.
  The full description above is extended with a `4.6.0:` note; implementation
  notes live in `README.md` ("Hardcoded fallback move records (4.6.0)").
- **4.6.1** -- Transform/Imposter copy the target's moveset and ability:
  `combat/modern_transform.lua` builds a battle-only copy of the target's four
  moves (each at 5 current PP with the move's own max PP) onto both
  `battler.curMoves` and `mon.moves`, and copies the target's ability, firing
  the copied switch-in ability effect exactly once; reversion restores the
  user's own learned moves (PP-Ups and PP intact) and its own ability. A new
  `registerSwitchInAbility`/`fireSwitchInAbility` seam in
  `abilities/ability_dispatch.lua` is registered by twelve switch-in ability
  modules, and `combat/move_targeting.lua`'s native adjacency fallback now hands
  the engine raw mons. The full description above is extended with a `4.6.1:`
  note; implementation notes live in `README.md` ("Transform and Imposter copy
  the moveset and the ability (4.6.1)").
- **4.6.2** -- multi-hit counts guaranteed on both generations:
  `combat/multi_hit.lua` reads every move's live `minHits`/`maxHits` from
  national_dex and enforces that count at each generation's own execution seam.
  Gen 1 wraps `EffectRegistry.runDamaging` to set `ctx.move.multiHit` right
  before the native effect reads it (also making Skill Link's 2-5 -> 5 apply on
  Gen 1); Gen 2 wraps `Battle:useMove` and its `Effects.hitCount` for any
  planned move whose effect isn't already `EFFECT_DOUBLE_HIT`,
  `EFFECT_MULTI_HIT`, `EFFECT_POISON_MULTI_HIT` or `EFFECT_TRIPLE_KICK`, so
  Double Kick and the other effect-less multi-hit moves stop resolving as a
  single hit. The full description above is extended with a `4.6.2:` note;
  implementation notes live in `README.md`.
- **4.6.3** -- Bide works again on both generations: national_dex's takeover
  had replaced the cart's own BIDE effect with a power-0 no-op record, so the
  native store-and-release machine never started. `combat/modern_bide.lua`
  re-homes it as `GALAR_BIDE_EFFECT` (via `CUSTOM_EFFECT_PATCH`), follows
  Showdown gen7 (a fixed 2 continuations: wait, then release), banks only real
  damaging move hits, and releases `stored * 2`; Gen 1 uses the cart's own
  `continueBide`/`applyDamage`, Gen 2's `run` owns the lifecycle and refunds
  one PP per continuation. `combat/move_usability.lua` gained a Bide gate that
  refuses every move but BIDE while the store is live, so the user cannot act
  during Bide. Pain Split never enters the damage path, so it is not banked.
  The full description above is extended with a `4.6.3:` note; implementation
  notes live in `README.md` ("Bide stores for a turn, locks the user, then
  releases double (4.6.3)").
- **4.6.4** -- wild Illusion no longer crashes the battle:
  `combat/modern_transform.lua`'s `wildDisguise` rolled its spawn-table index
  as `rng(battle, 1, #pool)`, but `battle.rng` is the engine's inclusive
  `(lo, hi)` roller (`src/battle/BattleState.lua`), not a `(battle, lo, hi)`
  helper -- the battle table reached `love.math.random` and aborted the Red
  battle with "bad argument #2 to 'random' (number expected)". The roll is now
  `rng(1, #pool)`. The round-179 transform probe's `battle.rng` stub was made
  faithful to the real two-argument shape, so it now catches this. The full
  description above is extended with a `4.6.4:` note; implementation notes live
  in `README.md` ("Wild Illusion crashed the battle on its first disguise roll
  (4.6.4)").
- **4.6.5** -- a Gold boot has no guarded failures and no cross-generation
  warning it cannot act on, and the marker sweep no longer races the modules
  that register real records:
  `combat/move_effect_markers.lua` moved to the very END of the boot (after
  `modern_effect_guard`), so it seeds only ids nothing else claimed instead of
  seeding a bare marker for an id a `modern_*` module is about to register --
  the sixteen `move_effects already registered` guarded failures are gone, and
  a stock boot seeds exactly `NO_ADDITIONAL_EFFECT`. `combat/
  modern_held_items_phase2.lua` skips an item id another mod already registered
  (`GRISEOUS_ORB`, owned by battle_forms at priority 80) instead of logging the
  `items already registered` failure. `combat/modern_effect_guard.lua` returns
  cleanly with one `info` line (and `effectGuardInstalled = false`) when the
  live `src.battle.BattleState` is the Gen-2 facade and has no Gen-1
  `effectRecord`; `combat/modern_transform.lua`'s skip is an `info` too.
  `gigantamax/tera_state.lua`'s unreachable battle_forms options gate logs once
  at `info`, naming the loader's `{id, version, exports}` handle design -- the
  per-mon `battleFormsTeraType` stamp `ensureTeraStamps` maintains is the real
  seam. The fengari harness gained a faithful `moves` stub
  (`opts.faithfulMoves`) that reproduces the old failure set and proves the
  fix. The full description above is extended with a `4.6.5:` note;
  implementation notes live in `README.md` ("A Gold boot's guarded failures and
  cross-generation warnings (4.6.5)").
- **4.6.6** -- the last four cross-generation warnings are gone: a Gold boot no
  longer logs `src.battle.BattleState.newWild / newTrainer / performMove /
  effectRecord has no Gen 2 backing`. Those four are Gen-1-only members of the
  engine's Gen2Compat facade, and its `__index` warns once per member the
  moment a mod READS the name; this engine read each one at boot only to ask
  "does the real Gen-1 BattleState carry this, so should I install my Gen-1
  wrap?" (`type(BattleState.performMove) == "function"`, and the same shape in
  `modern_effect_guard`, `modern_combat_protect`, `modern_transform`,
  `modern_move_flags`, `modern_movepool_damage`, `modern_weather`,
  `interaction_memory`, `wild_modern_ivs`, `trainer_modern_stats`, and the six
  `abilities/engine/*` wraps). Every such read now goes through
  `rawget(BattleState, "...")`, which cannot invoke the facade's `__index`: on
  Gold the member reads nil, so the Gen-1 wrap is skipped and nothing is
  written to the facade; on Gen 1 the real `src/battle/BattleState.lua` carries
  all four as raw keys, so every wrap installs exactly as before. The four
  warnings (and the dead wrappers they used to install on the facade) are gone
  with no behaviour change on either generation. The full description above is
  extended with a `4.6.6:` note; implementation notes live in `README.md`
  ("A Gold boot is silent: the four Gen-1-only facade reads go through rawget
  (4.6.6)").
- **4.6.7** -- ally-side spread moves reach adjacent allies: Life Dew and Lunar
  Blessing (`combat/modern_movepool_damage.lua`) walk the user's real adjacent
  side through `requestAdjacency` instead of touching `n.user` alone, Life Dew's
  heal is corrected to 1/4 max HP, Howl and the newly wired Coaching
  (`combat/modern_movepool_stages.lua`'s new `teamBoostMove` helper) boost the
  side, and Dragon Cheer (`combat/modern_crit_override.lua`) applies its
  switch-scoped crit volatile to adjacent allies (retired from
  `combat/structural_exemptions.lua`). `main.lua`'s `CUSTOM_EFFECT_PATCH` gained
  `COACHING` and `DRAGONCHEER`. The full description above is extended with a
  `4.6.7:` note; implementation notes live in `README.md` ("Ally-side spread
  moves: Life Dew, Lunar Blessing, Howl, Coaching and Dragon Cheer reach adjacent
  allies (4.6.7)").
- **4.6.8** -- ally-targeting moves reach adjacent allies, and Imposter copies
  only the directly-opposite foe: `combat/move_targeting.lua`'s
  `isAllyTargetable` now admits every non-damaging selected-pokemon move
  (national_dex `damageClass == "status"`), so Transform and the whole
  status/support family can be aimed at an adjacent ally, and a new
  `isAllyOnlyMove` marks the Helping Hand / Heal Pulse family that must offer no
  foe and be used-and-failed in singles. A new `requestOpposite` position query
  (a scene's `g9.request_opposite` hook, with a native two-battler fallback and
  never an ally) drives `combat/modern_transform.lua`'s `oppositeOpponentOf`, so
  Imposter transforms only into the foe in its own slot and does nothing when
  that slot is empty (`COACHING`/`DRAGONCHEER` untouched). The scene
  (g9-Battle-Scene 4.5.1) answers the hook, widens its picker on the same rules,
  and runs the switch-in abilities after the intro. The full description above
  is extended with a `4.6.8:` note; implementation notes live in `README.md`
  ("Ally-targeting moves reach adjacent allies, and Imposter only ever copies
  the foe opposite its slot (4.6.8)").

- **4.7.0** -- combat narration routes through `Strings()`. Every message the
  engine built by concatenation now goes through the engine's own
  `Strings("<template>", args)` form, so the installed translation mod's
  catalog (`mod.content.strings`) reaches it. Around 120 call sites across
  `combat/` and `abilities/engine/` were converted: status turn-loss
  (paralysis/sleep/freeze), trap moves, hazards (Spikes / pointed stones /
  sharp steel), drag-out, MIST, Forewarn, Cursed Body, item interactions
  (Knock Off, Covet, Fling, Harvest, berries), terrain/weather/room start and
  end lines, the Protect/Endure/`But it failed!` lines, side conditions and
  guards, Future Sight / Doom Desire, the `Go!`/`used` announcements and the
  G-Max residual lines. Each source is the engine's own key where one exists
  (so the translation mod applies verbatim) and the mod's own English wording
  otherwise. `Strings` is now required at the top of the mod function in every
  touched file; `luaparse` 5.1 parses all 212 engine Lua files, a
  first-argument/argument-count audit over all 378 `Strings(...)` calls finds
  no unresolved `%`-directive, and a fengari harness confirms the lookup, the
  slot substitution and the wrong-arity English fallback. The same audit also
  caught ten sites that had been passing an empty-string placeholder for a
  `%s` -- so the actor's name rendered blank, or the raw `%s` showed -- and
  each now passes the real display name via `displayNameFor` (Aqua Ring,
  Leech Seed, Ingrain, Yawn, Disable, Embargo / Heal Block / Throat Chop,
  Telekinesis, Swallow). Implementation notes live
  in `README.md` ("Combat narration routes through `Strings()` (4.7.0)").
