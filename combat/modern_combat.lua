-- Native Lua port of the modern (Gen 6+) damage formula, replacing the
-- Showdown live-bridge approach entirely: this hooks the engine's own
-- sanctioned battle.damage extension point (BattleState:computeDamage,
-- src/battle/BattleState.lua:2239-2247) rather than monkey-patching a
-- BattleState method directly -- Runtime.call("battle.damage", vanilla,
-- ctx) already exists in the core engine for exactly this purpose, and
-- mod.hooks:wrap is the real, generic public API every mod gets
-- (src/mods/Loader.lua:598), not something invented for this file.
--
-- Applies to EVERY battle (wild, trainer, link) -- there is no kind=="wild"
-- gate anywhere in this file, unlike the retired Showdown bridge.
--
-- Reused, not reimplemented: MoveCategory.of (src/pokemon/MoveCategory.lua)
-- for Physical/Special/Status, ModernStats.ensure (src/pokemon/
-- ModernStats.lua) for spa/spd + EV/IV/nature, TypeChart.effectiveness/
-- .rows (src/battle/TypeChart.lua, already includes modern_type_framework's
-- registered types via the shared type_chart content registry) for type
-- effectiveness, Stats.applyStage for stat stages. None of this is
-- reimplemented here -- only the parts nothing else in the engine already
-- does in a modern way: the spa/spd-aware formula shape, a real
-- multiplier-slot chain, and a stage-based crit.
return function(mod)
  local Runtime = require("src.mods.Runtime")
  local MoveCategory = mod.exports.MoveCategory
  local ModernStats = mod.exports.ModernStats
  local TypeChart = require("src.battle.TypeChart")
  local Stats = require("src.pokemon.Stats")
  local Status = require("src.battle.Status")
  local Damage = require("src.battle.Damage") -- BADGE_BOOSTS table only, reused as data
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")

  -- Gen 2 detection, needed early (the STAB modifier below already
  -- reads a generation-aware type list). Same pattern proven in
  -- gen2_modern_stats.lua: compare the live battle's metatable against
  -- the real Gen 2 Battle class.
  local gen2Ok, Gen2Battle = pcall(require, "src.battle.gen2.Battle")
  Gen2Battle = gen2Ok and Gen2Battle or nil
  local function isGen2Battle(battle)
    return Gen2Battle ~= nil and battle ~= nil and getmetatable(battle) == Gen2Battle
  end

  -- Gen 1 detection, same identity-check shape as isGen2Battle above --
  -- deliberately its OWN positive check against Gen 1's real class, never
  -- derived as "not gen2" anywhere in this mod. The comment right below
  -- this block (monLooksGen2, a real bug found via Max Guard) already
  -- proved why: ctx.battle's own identity can fail to match even during
  -- a genuine battle of that generation, so "not gen2 therefore gen1" can
  -- be actively wrong, not just unconfirmed, in the exact cases where a
  -- caller hands this mod an unreliable ctx.battle. Two independent
  -- positive checks close that gap; a negation of one never can.
  local gen1Ok, BattleState = pcall(require, "src.battle.BattleState")
  BattleState = gen1Ok and BattleState or nil
  local function isGen1Battle(battle)
    return BattleState ~= nil and battle ~= nil and getmetatable(battle) == BattleState
  end
  mod.exports.isGen1Battle = isGen1Battle

  -- Confirmed live (2026-08-20, Max Guard): ctx.battle isn't always the
  -- real, metatable-matching Gen 2 Battle instance every battle.damage
  -- hook call gets -- whatever battle_forms's own Max Guard block-check
  -- does to trigger this hook hands it a ctx.battle that fails
  -- isGen2Battle's identity check even during a genuine Gen 2 battle,
  -- which sent every downstream gen2-gated helper (rawStat included)
  -- down the Gen 1 branch and crashed on who.curStats -- a field that
  -- only ever exists on Gen 1's battler wrapper, never on a real Gen 2
  -- raw mon (which only ever has .stats). This checks the mon objects
  -- themselves as a self-contained fallback signal, since a real Gen 1
  -- battler always has .curStats and a real Gen 2 mon never does --
  -- unlike ctx.battle's identity, that can't be spoofed/missing.
  local function monLooksGen2(who)
    return who ~= nil and who.curStats == nil and who.stats ~= nil
  end

  -- Gen 1's battler wrapper exposes curTypes (Transform/Conversion-
  -- aware); Gen 2's raw mon carries the same live-type list as .types
  -- (confirmed from Gen 2's own native STAB check, gen2/Damage.lua:
  -- 249-253, which reads attacker.types).
  local function curTypesOf(who, gen2)
    return (gen2 and who.types or who.curTypes) or {}
  end
  -- Exported for Phase 4 (combat/modern_weather.lua): Sand's chip-damage
  -- immunity check (Ground/Steel/Rock) needs the same Transform/
  -- Conversion-aware live type list this file already uses for STAB.
  mod.exports.curTypesOf = curTypesOf

  -- Real, fully-resolved defender type multiplier -- the single place
  -- Foresight/Miracle Eye/Smack Down/Scrappy/Mind's Eye's real immunity
  -- NEGATION and Telekinesis's real immunity GRANT both actually apply,
  -- before the natural TypeChart lookup ever runs. Found 2026-08-28
  -- during the Wonder-Guard-reachability review ("review abilities
  -- similar to these," following the Magic Guard audit): this logic
  -- used to live ONLY inside modern_status_volatiles.lua's own
  -- registerPostEffectivenessModifier("type_immunity_negation", ...)
  -- entry, which is unreachable dead code -- this function's own caller
  -- below (computeModernDamage) returns 0 damage the instant the
  -- NATURAL multiplier reads 0, before the postEffectivenessModifiers
  -- loop that entry lives in ever runs, so Scrappy/Mind's Eye/Foresight/
  -- Miracle Eye/Smack Down never actually let a hit through in practice
  -- despite being fully coded up. Fixed by resolving negation HERE,
  -- against the real defender type LIST (filtering out whichever single
  -- type causes the natural 0x, e.g. Ghost for a Normal/Fighting move
  -- under Scrappy) before either the aggregate multiplier or the real
  -- per-row TypeChart.rows() scaling ever sees it -- a raw "override the
  -- final number to math.huge" trick (the old entry's own approach)
  -- can't work here since TypeChart.rows() still walks the SAME 0x row
  -- independently of any post-hoc multiplier.
  --
  -- Exported (not just used internally) so combat/legacy_move_takeover
  -- .lua's own centralized fixed-damage/OHKO moves (Seismic Toss, Night
  -- Shade, Sonic Boom, Dragon Rage, Psywave, Super Fang, Fissure/
  -- Guillotine/Horn Drill, Sheer Cold) -- which never call
  -- computeModernDamage at all -- can reach the exact same real
  -- resolution instead of the raw, negation-blind TypeChart.effectiveness
  -- check they used before this fix.
  local function resolvedTypeMult(battle, user, target, gen2, moveType)
    -- Telekinesis: the OPPOSITE direction -- GRANTS a Ground immunity a
    -- Ground-type move wouldn't naturally have, regardless of the
    -- target's real types. Checked first/short-circuited, matching the
    -- old entry's own real ordering.
    if moveType == "GROUND" and target.telekinesisTurns then
      return 0, {}
    end
    local targetTypes = curTypesOf(target, gen2)
    if mod.exports.defensiveTypesOf then
      targetTypes = mod.exports.defensiveTypesOf(battle, target, gen2, targetTypes)
    end
    local negate = false
    if moveType == "NORMAL" or moveType == "FIGHTING" then
      if target.foresighted then negate = true end
      local abilityIdOf = mod.exports.abilityIdOf
      local aid = abilityIdOf and user and abilityIdOf(user)
      if aid == "SCRAPPY" or aid == "MINDSEYE" then negate = true end
    elseif moveType == "PSYCHIC" and target.miracleEyed then
      negate = true
    elseif moveType == "GROUND" and target.groundedByMove then
      negate = true
    end
    if negate then
      local filtered = {}
      for _, dt in ipairs(targetTypes) do
        if TypeChart.effectiveness(moveType, { dt }) ~= 0 then
          filtered[#filtered + 1] = dt
        end
      end
      targetTypes = filtered
    end
    return TypeChart.effectiveness(moveType, targetTypes), targetTypes
  end
  mod.exports.resolvedTypeMult = resolvedTypeMult
  -- Exported for the same sibling: several weather touch-points (the
  -- Solar Beam charge-skip performMove wrap, the sand-chip end-of-turn
  -- hook, the Thunder/Blizzard battle.accuracy hook) run OUTSIDE the
  -- move_effects normalize() bridge, so they need this discriminator
  -- directly instead of re-deriving it.
  mod.exports.isGen2Battle = isGen2Battle

  ------------------------------------------------------------------
  -- Multiplier-slot framework: named, priority-ordered damage
  -- modifiers, applied one at a time (each its own floor step, same
  -- style native Damage.compute already uses for type-effectiveness
  -- rows rather than one combined fraction) so a later pass can add
  -- an entry without ever touching computeModernDamage's body.
  --
  -- STAB is one of two built-in entries today. "tera_stab" (priority 110,
  -- above "stab"'s 100) is combat/modern_tera.lua's own -- see that file's
  -- header for the full rule; "stab" itself defers to it (returns 1.0)
  -- whenever the attacker is Terastallized, so the two never double-count
  -- the same hit.
  --
  -- Documented, NOT implemented, extension points for later work:
  --   "adaptability_stab": an ability multiplier replacing stab's 1.5x
  --     with 2.0x for a matching type -- register at the same priority
  --     as "stab" and have "stab" itself check for the ability and
  --     return 1.0 (deferring) when adaptability's entry already fired.
  --   general ability/item damage multipliers: priority < 100 (after
  --     STAB), e.g. Life Orb, Choice Band, a damage-boosting ability.
  --   TODO -- spread-move damage reduction (real Gen 9 rule: a move that
  --     hits more than one target this turn deals 0.75x damage to each,
  --     versus hitting a single target at full damage) -- a real
  --     registerDamageModifier entry once combat/MULTI_BATTLE_HOOKS.md's
  --     multi-target resolver exists (ctx needs a target COUNT for this
  --     hit, which nothing in a 2-battler engine can ever produce above
  --     1 -- see that doc's own "what's still missing" section, same
  --     root cause as the turn-order gap: no multi-battler data model
  --     here yet). Not buildable or testable until then -- flagged now
  --     so it isn't rediscovered as a surprise later.
  ------------------------------------------------------------------
  local damageModifiers = {} -- { {id=, priority=, fn=}, ... }, sorted desc

  local function registerDamageModifier(id, priority, fn)
    assert(type(id) == "string" and id ~= "", "damage modifier id is required")
    assert(type(fn) == "function", "damage modifier must be a function")
    for i, entry in ipairs(damageModifiers) do
      if entry.id == id then table.remove(damageModifiers, i) break end
    end
    table.insert(damageModifiers, { id = id, priority = priority or 0, fn = fn })
    table.sort(damageModifiers, function(a, b) return a.priority > b.priority end)
  end
  mod.exports.registerDamageModifier = registerDamageModifier

  -- Companion chain to registerDamageModifier, for the class of ability
  -- registerDamageModifier structurally can't express: Phase 2's own
  -- effectiveness-tier abilities (Neuroforce/Tinted Lens/Filter/Solid
  -- Rock/Prism Armor -- "1.25x when super effective," "2x when not very
  -- effective," etc.) need the REAL, final type multiplier to check
  -- against, and every registerDamageModifier entry runs BEFORE that
  -- multiplier exists at all (same root problem Delta Stream's own
  -- effectivenessOverrideFor hook was built for in Phase 1.5, just
  -- "add a factor" shaped instead of "replace the multiplier" shaped).
  -- Consulted once, right after Delta Stream's own override and Tera
  -- Stellar's own extra multiplier have both already applied -- so these
  -- abilities react to the REAL, final effectiveness the hit will
  -- register as, not a pre-Delta-Stream/pre-Stellar value.
  local postEffectivenessModifiers = {}
  local function registerPostEffectivenessModifier(id, priority, fn)
    assert(type(id) == "string" and id ~= "", "post-effectiveness modifier id is required")
    assert(type(fn) == "function", "post-effectiveness modifier must be a function")
    for i, entry in ipairs(postEffectivenessModifiers) do
      if entry.id == id then table.remove(postEffectivenessModifiers, i) break end
    end
    table.insert(postEffectivenessModifiers, { id = id, priority = priority or 0, fn = fn })
    table.sort(postEffectivenessModifiers, function(a, b) return a.priority > b.priority end)
  end
  mod.exports.registerPostEffectivenessModifier = registerPostEffectivenessModifier

  -- Runs a caller-chosen SUBSET of the postEffectivenessModifiers chain
  -- against an already-computed damage number and a real, resolved type
  -- multiplier -- built for combat/legacy_move_takeover.lua's own
  -- centralized fixed-damage/OHKO moves, which never call
  -- computeModernDamage (this file's own base formula, below) and so
  -- never reach this chain naturally. `onlyIds` matters: real Showdown
  -- fact, verified against Bulbapedia/Smogon sourcing during the
  -- 2026-08-28 Wonder-Guard-reachability review -- Wonder Guard's own
  -- entry ("wonderguard") is a real HARD GATE these fixed-damage moves
  -- DO respect (it blocks anything not super effective, fixed-damage
  -- moves included -- confirmed, Shedinja's own real Psywave/Fissure/
  -- Metal Burst immunity is the textbook example), but Filter/Solid
  -- Rock/Prism Armor/Tinted Lens/Neuroforce/Tera Shell are honest
  -- SCALING modifiers (0.75x/1.3x/etc. on the super/not-very-effective
  -- multiplier) that a fixed-damage move's own number never receives in
  -- the first place -- a fixed amount doesn't scale by type
  -- effectiveness even in the normal, non-ability case, confirmed via
  -- real sourcing ("Solid Rock (and Filter)," Smogon forums). Passing
  -- every caller an explicit allow-list keeps that real distinction
  -- correct instead of silently over-applying scaling abilities that
  -- were never supposed to reach these moves.
  local function applyPostEffectivenessModifiers(ctx, onlyIds)
    local allow
    if onlyIds then
      allow = {}
      for _, id in ipairs(onlyIds) do allow[id] = true end
    end
    local d = ctx.damage
    for _, entry in ipairs(postEffectivenessModifiers) do
      if not allow or allow[entry.id] then
        local m = entry.fn({
          battle = ctx.battle, user = ctx.user, target = ctx.target, move = ctx.move,
          category = ctx.category, mult = ctx.mult, gen2 = ctx.gen2,
        }) or 1.0
        if m ~= 1.0 then d = math.floor(d * m) end
      end
    end
    return d
  end
  mod.exports.applyPostEffectivenessModifiers = applyPostEffectivenessModifiers

  -- Part B Phase 5 Tier 1: real per-move variable base power (Heat Crash/
  -- Heavy Slam's weight ratio, Power Trip's stat-stage count, Flail's HP
  -- fraction). Deliberately separate from registerDamageModifier above --
  -- that chain only ever scales the FINAL post-formula `d` (confirmed by
  -- Snow's own Ice-Defense boost needing a special inline case instead of
  -- going through it, this file's own earlier precedent), which is the
  -- wrong shape for a genuine base-power SUBSTITUTION: real Showdown
  -- computes these before the damage formula even starts, not as a
  -- trailing multiplier, and forcing a substitution through a multiplier
  -- (power/move.power) would compound the formula's own floor()s in the
  -- wrong order. keyed by move id, single winner (first match), same
  -- one-entry-per-move shape these moves actually need -- no move in
  -- this batch has more than one power-override source.
  local powerOverrides = {} -- { [moveId] = fn(ctx) -> integer power }

  -- Moves that return a finished damage number from their own branch inside
  -- computeModernDamage rather than scaling a power. They have no entry in
  -- powerOverrides by design, so the zero-power gate has to be told about
  -- them separately or their branch is unreachable.
  local COMPUTES_OWN_DAMAGE = { ENDEAVOR = true }

  -- What a computed-power move falls back to when its formula CANNOT answer.
  --
  -- An override returns nil when an input it needs is missing, and the old
  -- fallback was `or move.power` -- which for exactly these moves is 0,
  -- because PokeAPI reports no power for them. So "the data was missing"
  -- silently became "the move does nothing", which is the failure mode this
  -- whole area keeps producing.
  --
  -- It is not hypothetical: speciesWeightOf reads dexEntry.weightKg, and
  -- national_dex only attaches a dexEntry to species it REGISTERS. The
  -- original 251 arrive through its `patch` bucket with no dexEntry at all,
  -- so Heavy Slam or Heat Crash aimed at any cart Pokemon had no target
  -- weight, no ratio, and no damage. Reported from a real game: Bastiodon's
  -- Heavy Slam "did not do anything".
  --
  -- These are each move's real-world average power, so a mon with no weight
  -- data plays as an ordinary move of its own tier rather than a dud. A
  -- number here is a LAST RESORT and never preferred over a real formula.
  local FALLBACK_POWER = {
    HEAVYSLAM = 100, HEATCRASH = 80, GRASSKNOT = 60, LOWKICK = 50,
    GYROBALL = 80, ELECTROBALL = 80, CRUSHGRIP = 80, WRINGOUT = 80,
    HARDPRESS = 80, PUNISHMENT = 100, FLING = 30, TRUMPCARD = 80,
    SPITUP = 100, METALBURST = 70,
  }
  local function registerPowerOverride(moveId, fn)
    assert(type(moveId) == "string" and moveId ~= "", "power override move id is required")
    assert(type(fn) == "function", "power override must be a function")
    powerOverrides[moveId] = fn
  end
  mod.exports.registerPowerOverride = registerPowerOverride

  local critStageModifiers = {} -- { fn(ctx) -> integer stage delta, ... }
  local function registerCritStageModifier(id, fn)
    assert(type(id) == "string" and id ~= "", "crit stage modifier id is required")
    assert(type(fn) == "function", "crit stage modifier must be a function")
    critStageModifiers[id] = fn
  end
  mod.exports.registerCritStageModifier = registerCritStageModifier

  -- Built-in: STAB. A flat 1.5x when the move's type is one of the
  -- attacker's current types (curTypes -- Transform/Conversion-aware,
  -- same field native Damage.compute already reads).
  --
  -- Defers entirely (returns 1.0) whenever the attacker is Terastallized:
  -- combat/modern_tera.lua's own "tera_stab" (priority 110, above this
  -- one) owns the whole STAB computation in that case instead, since
  -- curTypesOf() only ever holds the tera type once Terastallized (the
  -- mon's ORIGINAL types are gone from it entirely) -- this modifier alone
  -- would silently lose original-type STAB and never grant the real 2.0x
  -- when the tera type matches an original one. See modern_tera.lua's own
  -- header for the full rule; this is the seam this file's own comment
  -- already reserved for it.
  registerDamageModifier("stab", 100, function(ctx)
    if mod.exports.isTerastallized and mod.exports.isTerastallized(ctx.battle, ctx.user, ctx.gen2) then
      return 1.0
    end
    -- Adaptability (abilities/engine/damage_multiplier.lua's own
    -- "adaptability_stab" entry, same priority tier) replaces the usual
    -- 1.5x with 2.0x -- deferred to explicitly here (checking the
    -- ability directly) rather than relying on registration/sort order
    -- between two same-priority entries, exactly the plan this file's
    -- own header already documented before either entry existed.
    if mod.exports.abilityIdOf and mod.exports.abilityIdOf(ctx.user) == "ADAPTABILITY" then
      return 1.0
    end
    for _, t in ipairs(curTypesOf(ctx.user, ctx.gen2)) do
      if t == ctx.move.type then return 1.5 end
    end
    return 1.0
  end)

  -- Real Gen 9 spread-move rule (the TODO this file's own header already
  -- flagged): a move hitting more than one target the same turn deals
  -- 0.75x to each, versus full damage against a single target. Reads
  -- ctx.opts.targetCount -- a NEW, purely additive field on the SAME
  -- opts table computeModernDamage already threads through, populated by
  -- whatever calls useMove with more than one real target resolved (see
  -- combat/move_targeting.lua's own resolveMoveTargets, and combat/
  -- MULTI_BATTLE_HOOKS.md's own updated contract) -- absent or 1 on
  -- every call site today, so this is a genuine no-op until a real
  -- multi-battler caller exists, not a behavior change for anything
  -- currently working. Boss-fight exception, explicit user rule: AoE
  -- diminishing is removed entirely against a protected boss regardless
  -- of which boss-fight flags are active -- Life Dew and Earthquake hit
  -- everyone at full force, not 0.75x each.
  registerDamageModifier("spread_reduction", 95, function(ctx)
    local count = ctx.opts and ctx.opts.targetCount
    if not (count and count > 1) then return 1.0 end
    if ctx.target == ctx.battle.enemy and mod.exports.bossFightHas
        and next(ctx.battle.bossFightFlags or {}) ~= nil then
      return 1.0
    end
    return 0.75
  end)

  ------------------------------------------------------------------
  -- Phase 4: GalarGmaxDex-owned weather state. Gen 1 has no native
  -- weather concept at all -- field.weather is a declared-but-dead field
  -- (confirmed zero real consumers; BattleCheckpoint.lua:367 only
  -- persists whatever nil is already there). battle.weather/
  -- battle.weatherTurns are new fields, written directly onto the battle
  -- object itself, the same direct-field convention already used for
  -- per-battler state elsewhere in this engine (user.thrashTurns,
  -- user.protected) -- no side table needed, since the battle object's
  -- own lifetime already bounds it (unlike stageState above, which needs
  -- one because it's keyed off a table it doesn't own).
  --
  -- Gen 2 already has this SAME state, for real: self.weather/
  -- self.weatherTurns (gen2/Battle.lua:291-292; native RAINDANCE/
  -- SUNNYDAY/SANDSTORM handlers at :1896-1906 set them; tickWeather at
  -- :4275-4304 counts them down and, for sandstorm, applies end-of-turn
  -- chip). Reused directly here, not shadowed with a parallel field --
  -- setWeather below writes straight into those same two fields, using
  -- Gen 2's own lowercase value convention ("rain"/"sun"/"sandstorm"),
  -- so every OTHER native consumer already keyed off self.weather
  -- (Effects.weatherHealFraction, gen2/Ai.lua's sun check, the
  -- EFFECT_SOLARBEAM sun-skip at gen2/Battle.lua:1460) keeps working
  -- automatically. modern_weather.lua's own header explains why
  -- GalarGmaxDex's own override handlers have to be the ones calling
  -- this now instead of native's hardcoded EFFECT_RAIN_DANCE/EFFECT_
  -- SUNNY_DAY/EFFECT_SANDSTORM ones.
  --
  -- "snow" is a weather value Gen 2 never produces natively (no Hail/
  -- Snow move exists in its own Effects.WEATHER table) -- modern_
  -- weather.lua adds it as pure new DATA into Gen 2's own Effects.
  -- WEATHER_START_TEXT/TURN_TEXT/END_TEXT tables (not a new field), so
  -- tickWeather's own generic countdown/expiry logic -- keyed by
  -- self.weather's VALUE, not a fixed key list -- handles it correctly
  -- with no control-flow changes at all.
  ------------------------------------------------------------------
  -- STRONGWINDS (Delta Stream's own "mysterious air current" -- Phase
  -- 1.5): not a real native Gen 2 weather value, added here purely so
  -- setWeather/currentWeather stay the ONE cross-engine reader/writer for
  -- every field-weather state this project has, primal included, with no
  -- special-casing anywhere else. Native Gen2 tickWeather's own end-of-
  -- turn countdown is keyed off self.weather's VALUE generically (already
  -- confirmed for SNOW, see combat/modern_weather.lua's own header) --
  -- an unrecognized value ticks down harmlessly with no special message,
  -- same as any other weather already does.
  local GEN2_WEATHER_VALUE = { RAIN = "rain", SUN = "sun", SAND = "sandstorm", SNOW = "snow", STRONGWINDS = "strongwinds" }
  local FROM_GEN2_WEATHER_VALUE = { rain = "RAIN", sun = "SUN", sandstorm = "SAND", snow = "SNOW", strongwinds = "STRONGWINDS" }

  -- Single cross-engine reader: "RAIN"|"SUN"|"SAND"|"SNOW"|nil, regardless
  -- of which engine's own field shape backs it. Every weather touch-point
  -- (the damage modifier below, the Ice-type Defense boost further down,
  -- modern_weather.lua's accuracy/charge/chip hooks) goes through this
  -- one function rather than reading battle.weather directly.
  local function currentWeather(battle, gen2)
    if not battle then return nil end
    if gen2 then
      return battle.weather and FROM_GEN2_WEATHER_VALUE[battle.weather] or nil
    end
    return battle.weather
  end
  mod.exports.currentWeather = currentWeather

  -- Air Lock/Cloud Nine (Phase 8, other bucket): "nullifies all weather
  -- effects in battle without stopping the weather itself" -- real,
  -- confirmed field-wide effect (active while EITHER holder is out,
  -- either side), checked via the real N-way roster
  -- (mod.exports.allActiveBattlers) rather than the hardcoded pair.
  -- Honestly scoped, not exhaustive: wired into the single highest-
  -- value case (this file's own Sun/Rain Fire/Water damage multiplier,
  -- right below) -- NOT into every other weather-dependent mechanic
  -- scattered across this mod (Chlorophyll-family speed doubling,
  -- Thunder/Blizzard's real accuracy exception, Synthesis/Moonlight/
  -- Morning Sun's weather-variable heal fraction, Sand's own chip
  -- damage) -- each of those would need its own real touch, not
  -- attempted this pass, a real remaining gap.
  mod.exports.weatherNullified = function(battle)
    local allActiveBattlers = mod.exports.allActiveBattlers
    local abilityIdOf = mod.exports.abilityIdOf
    if not (battle and allActiveBattlers and abilityIdOf) then return false end
    for _, mon in ipairs(allActiveBattlers(battle)) do
      local id = mon and abilityIdOf(mon)
      if id == "AIRLOCK" or id == "CLOUDNINE" then return true end
    end
    return false
  end

  -- 5 turns: real Showdown's default weather duration (no weather-rock/
  -- ability extension modeled), and exactly Gen 2's own native
  -- Effects.WEATHER_TURNS -- both engines agree already.
  local WEATHER_TURNS = 5
  mod.exports.WEATHER_TURNS = WEATHER_TURNS

  -- key is "RAIN"|"SUN"|"SAND"|"SNOW"|nil (nil clears the weather). turns
  -- defaults to WEATHER_TURNS (5) when omitted -- this function stays
  -- state-only, no item knowledge of its own; a caller wanting the real
  -- Damp/Heat/Smooth/Icy Rock extension (modern_weather.lua's own
  -- weatherStarter) resolves its own duration via
  -- mod.exports.resolveFieldDuration (combat/field_duration.lua) first and
  -- passes the result in explicitly.
  --
  -- setterMon (optional, 5th arg): who's actually setting this weather.
  -- Every caller in this mod already knows this (the move's user, or the
  -- ability's holder) -- passed through here purely for the boss-fight
  -- "sun" protection below, which needs to know WHICH side is setting
  -- weather, not just what value. A caller with no boss-fight concern at
  -- all can keep omitting it exactly like before this parameter existed.
  local function setWeather(battle, gen2, key, turns, setterMon)
    turns = key and (turns or WEATHER_TURNS) or 0
    -- Boss-fight "sun" protection (combat/boss_fight.lua): whenever the
    -- boss itself (battle.enemy) is the one setting weather while this
    -- protection is active, the set becomes permanent and locked at the
    -- SAME tier primal weather already uses (battle.weatherPrimal) --
    -- reusing that existing lock rather than inventing a second one,
    -- since the semantics are identical (irreplaceable, indefinite). The
    -- one thing layered on top is battle.weatherBossLocked, which
    -- canSetWeather below treats as a tier ABOVE primal (explicit user
    -- rule: "even if player has primal weather, primal weather can't win
    -- over boss' set weather") and which abilities/engine/
    -- switchin_primal_weather.lua's own "ends when the setter leaves"
    -- listener checks to stay permanent for the whole fight rather than
    -- clearing on a mid-fight boss-side switch.
    -- Real N-way check (2026-08-28): "the boss set this" generalizes to
    -- "an enemy-side battler set this" (battle:sideOf), not literal
    -- identity against battle.enemy -- same reasoning as boss_fight_
    -- status.lua's own fix, applied here.
    if key and battle and setterMon and battle:sideOf(setterMon) == "enemy"
        and mod.exports.bossFightHas and mod.exports.bossFightHas(battle, "sun") then
      turns = math.huge
      battle.weatherPrimal = true
      battle.weatherPrimalSetter = setterMon
      battle.weatherBossLocked = true
    end
    if gen2 then
      battle.weather = key and GEN2_WEATHER_VALUE[key] or nil
      battle.weatherTurns = turns
      mod.events:emit("g9.weather_changed", { battle = battle, key = key })
      return
    end
    battle.weather = key
    battle.weatherTurns = turns
    -- Shared notification, any future feature can subscribe to this, not
    -- specific to one consumer: fired on every explicit weather change
    -- this mod's own code makes (every caller funnels through this one
    -- function) -- covers Gen 1's natural expiry too, since that already
    -- calls back into this same function (combat/modern_weather.lua's own
    -- battle.turn_ended handler: setWeather(battle, false, nil)), not a
    -- direct field write. Does NOT cover Gen 2's native tickWeather
    -- expiry (gen2/Battle.lua) -- that path is pure native code this
    -- mod's own setWeather is never called from, the same "Gen 2 handles
    -- its own thing" gap this mod has documented elsewhere since Phase 4.
    -- Added this session for abilities/engine/forecast_weather.lua's own
    -- reactive re-derivation (Forecast needs to know the INSTANT weather
    -- actually changes, not just at switch-in) -- that file's own header
    -- explains how it covers the one Gen-2-native gap this emission can't
    -- reach (a battle.turn_ended safety-net recheck, accepting at most
    -- one turn of lag for that specific case only).
    mod.events:emit("g9.weather_changed", { battle = battle, key = key })
  end
  mod.exports.setWeather = setWeather

  -- Gate for every plain (move or ability) weather setter, Phase 1.5's own
  -- addition: Desolate Land/Primordial Sea/Delta Stream set an
  -- irreplaceable field state (battle.weatherPrimal) that this function
  -- alone decides whether a given caller may touch. isPrimalSource=false
  -- (every move starter, every Phase-1 plain weather ability) is refused
  -- outright while a primal weather is up -- real current Showdown: not
  -- even another primal-weather-caliber ability, only its own kind, can
  -- override a plain Rain Dance, and nothing at all can override a primal
  -- except one of the other two primals. isPrimalSource=true always
  -- succeeds, matching the real rule that Groudon replacing Kyogre's Primal
  -- Sea with its own Desolate Land (or vice versa) is legal. Kept here
  -- (not inside setWeather itself) so setWeather stays a plain, opinionless
  -- state setter every caller already trusts -- the irreplaceability
  -- RULE belongs at each call site, not inside the primitive.
  --
  -- setterMon (optional 3rd arg): required to evaluate the boss-fight
  -- "sun" protection, checked FIRST, ahead of the primal tier -- explicit
  -- user rule: a boss's own set weather beats even a player's primal
  -- weather. Only the boss's own side (battle.enemy) is ever authorized
  -- while this protection is active; every other caller, primal included,
  -- is refused outright. A caller that omits setterMon while this
  -- protection happens to be active is refused by default (nil ~= battle
  -- .enemy) rather than silently bypassing the lock.
  mod.exports.canSetWeather = function(battle, isPrimalSource, setterMon)
    if battle and mod.exports.bossFightHas and mod.exports.bossFightHas(battle, "sun") then
      -- Real N-way check (2026-08-28): any enemy-side battler authorized,
      -- not just the literal battle.enemy object -- see this function's
      -- own header note above for the "boss's own side" rule this
      -- generalizes correctly rather than narrows.
      return setterMon ~= nil and battle:sideOf(setterMon) == "enemy"
    end
    if not (battle and battle.weatherPrimal) then return true end
    return isPrimalSource == true
  end

  -- Sun/Rain's Fire/Water damage multiplier. Priority 110, ABOVE stab's
  -- 100 -- real Gen 6+ Showdown applies the weather modifier before STAB
  -- in the damage-stage order (Bulbapedia's damage formula: ...weather,
  -- glaive rush, critical, random, STAB, type...), so this has to run
  -- first through the descending-priority chain for the per-stage floor
  -- rounding to land in the right place. Sand/Snow have no flat damage
  -- multiplier in real Showdown (Sand's old Rock SpDef boost and Snow's
  -- real Ice Defense boost are BOTH stat-input effects, not whole-damage
  -- multipliers -- Snow's is wired directly into this function's own
  -- defense-stat resolution below instead; Sand's is out of scope per
  -- the plan). Registered here, not in modern_weather.lua, purely so it
  -- sits next to currentWeather() -- the actual call site (registerDamage
  -- Modifier is already a public export) doesn't care which file calls it.
  -- Mega Sol (Phase 8, other bucket -- explicit user directive, "crucial"
  -- to build for real): a real, personal-only harsh-sunlight simulation
  -- for this Pokemon's OWN moves specifically, confirmed by national_dex
  --'s own real notes ("a personal, simulated weather state distinct
  -- from set_weather, which would change the field weather for everyone
  -- rather than just this Pokémon's own moves") -- NOT a field-weather
  -- setter, so it correctly coexists with any real (or absent, or
  -- opposite) actual field weather.
  --
  -- Checked FIRST, before either the real weatherNullified gate or the
  -- real currentWeather read, and returns immediately when it applies --
  -- per explicit user spec: "doesn't get blocked by any weather
  -- suppression" (Air Lock/Cloud Nine's own real field-wide nullify
  -- never touches a personal, non-field effect) and "permanent... until
  -- ability is suppressed/changed" (no separate persistence flag is
  -- actually needed for that: abilityIdOf itself already returns nil
  -- the instant Neutralizing Gas suppresses this holder, or the instant
  -- setAbility overwrites it to something else -- a live per-hit check
  -- against abilityIdOf already IS "on for as long as the ability
  -- itself is," with zero extra state to leak across turns or battles).
  registerDamageModifier("weather", 110, function(ctx)
    local abilityIdOf = mod.exports.abilityIdOf
    if abilityIdOf and ctx.user and abilityIdOf(ctx.user) == "MEGASOL" then
      if ctx.move.type == "FIRE" then return 1.5 end
      if ctx.move.type == "WATER" then return 0.5 end
      return 1.0
    end
    if mod.exports.weatherNullified and mod.exports.weatherNullified(ctx.battle) then return 1.0 end
    local weather = currentWeather(ctx.battle, ctx.gen2)
    if weather == "SUN" then
      if ctx.move.type == "FIRE" then return 1.5 end
      if ctx.move.type == "WATER" then return 0.5 end
    elseif weather == "RAIN" then
      if ctx.move.type == "WATER" then return 1.5 end
      if ctx.move.type == "FIRE" then return 0.5 end
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- Part B Phase 5 Tier 1: simple binary-condition power doublers.
  -- Each move's own `effect` field points at an empty kind="full"
  -- move_effects record (below) purely so isMoveDataComplete stops
  -- treating it as stubbed -- same deliberate-empty-record precedent
  -- GALAR_BLIZZARD_EFFECT already established (modern_weather.lua's own
  -- header). The real mechanic is this priority-100 (same tier as STAB
  -- -- Showdown's own modifier order has these move-specific doublers
  -- and STAB as coequal, order-independent slots) registerDamageModifier
  -- entry per move, keyed directly off ctx.move.id since none of these
  -- generalize to more than one move.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_ACROBATICS_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GMAX_VENOSHOCK_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GMAX_ASSURANCE_EFFECT", { kind = "full" })

  -- Gen 1 mons have no held-item concept anywhere in this engine at all
  -- (confirmed: zero references to a mon-level `item` field in the whole
  -- src/pokemon/ tree, unlike Gen 2's real mon.item) -- so "no item" is
  -- unconditionally true for a Gen 1 battler, and Acrobatics correctly
  -- always doubles there (not a special case; it falls out of the same
  -- check Gen 2 uses, matching how Gen 1 itself never had an item
  -- economy in the real games either).
  local function itemOf(who, gen2)
    return gen2 and who.item or nil
  end

  registerDamageModifier("acrobatics_no_item", 100, function(ctx)
    if ctx.move.id ~= "ACROBATICS" then return 1.0 end
    return itemOf(ctx.user, ctx.gen2) and 1.0 or 2.0
  end)

  -- Cross-generation status reader (Gen 1: battler-wrapper's mon.status;
  -- Gen 2: status lives directly on the raw mon, same convention as
  -- itemOf above) -- confirmed real ids via src/battle/Status.lua/
  -- StatusRegistry.lua ("PSN" for both regular and Toxic poison; this
  -- engine does not distinguish a separate Toxic id, so Venoshock's real
  -- Showdown behavior of doubling for either variant needs no extra
  -- check here).
  local function statusOf(who, gen2)
    return gen2 and who.status or (who.mon and who.mon.status)
  end

  registerDamageModifier("venoshock_poisoned", 100, function(ctx)
    if ctx.move.id ~= "VENOSHOCK" then return 1.0 end
    return statusOf(ctx.target, ctx.gen2) == "PSN" and 2.0 or 1.0
  end)

  registerDamageModifier("assurance_hurt_this_turn", 100, function(ctx)
    if ctx.move.id ~= "ASSURANCE" then return 1.0 end
    return ctx.target.damagedThisTurn and 2.0 or 1.0
  end)

  -- Twister: double power while the target is in the semi-invulnerable
  -- "in sky" phase of Fly/Bounce -- reuses the real `invulnerable` flag
  -- those two-turn moves already set (confirmed: gimmick_dynamax.lua/
  -- modern_weather.lua both read and clear it), not a new tracked state.
  -- The 20% flinch half is unrelated to this modifier -- it rides the
  -- move's own effect field (GALAR_FLINCH_EFFECT_20, moves_new.lua),
  -- the same shared per-chance mechanism every other flinch move uses.
  registerDamageModifier("twister_in_sky", 100, function(ctx)
    if ctx.move.id ~= "TWISTER" then return 1.0 end
    return ctx.target.invulnerable and 2.0 or 1.0
  end)

  ------------------------------------------------------------------
  -- Part B Phase 5 Tier 1 (continued): real variable-base-power moves,
  -- via registerPowerOverride (defined above, next to registerDamage
  -- Modifier) rather than the multiplier chain -- these substitute
  -- move.power outright, matching real Showdown's own formula order.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_HEATCRASH_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GMAX_HEAVYSLAM_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GMAX_POWERTRIP_EFFECT", { kind = "full" })
  mod.content.move_effects:register("GMAX_FLAIL_EFFECT", { kind = "full" })
  -- Endeavor's real mechanic is the move.id=="ENDEAVOR" special case
  -- directly inside computeModernDamage (bypasses the scaling formula
  -- entirely) -- this empty record exists purely so isMoveDataComplete
  -- stops treating it as stubbed, same as the four above.
  mod.content.move_effects:register("GMAX_ENDEAVOR_EFFECT", { kind = "full" })

  -- Current HP only (first return value) -- callers that also want max
  -- HP call this directly for both slots rather than a second helper.
  local function currentAndMaxHP(who, gen2)
    local mon = gen2 and who or who.mon
    local maxHp = gen2 and (mon.maxHp or (mon.stats and mon.stats.hp))
      or (mon.stats and mon.stats.hp)
    return mon.hp or 0, math.max(1, maxHp or 1)
  end

  -- Species weight, in whatever unit dexEntry carries it (kg preferred,
  -- lbs fallback) -- confirmed real path: national_dex's own dex-list
  -- code (gen2dexlist.lua:142-148) reads record.dexEntry.weight/
  -- weightKg straight off a live registered pokemon record, and its own
  -- register() call (nationaldex.lua:180-181) hands the whole record
  -- (dexEntry included) to mod.content.pokemon:register unmodified -- so
  -- this is real post-registration data, not raw pre-registration
  -- source. Only the RATIO between two mons matters for Heat Crash/Heavy
  -- Slam, so a consistent unit choice is all that's required, not a
  -- specific one. A species with no weight data at all defers to the
  -- move's plain, unboosted power (nil override, formula falls back to
  -- move.power) rather than guessing a ratio.
  local function speciesWeightOf(who, gen2)
    local speciesId = gen2 and who.species or (who.mon and who.mon.species)
    local def = speciesId and mod.content.pokemon:get(speciesId)
    local dexEntry = def and def.dexEntry
    if type(dexEntry) ~= "table" then return nil end
    local w = dexEntry.weightKg or dexEntry.weight
    if not (type(w) == "number" and w > 0) then return nil end
    -- Heavy Metal / Light Metal (Phase 8, other bucket): real, confirmed
    -- effect is doubling/halving the mon's own EFFECTIVE weight for
    -- every weight-based calculation, this function's one real choke
    -- point (both directions of Heat Crash/Heavy Slam's ratio, and any
    -- future weight-based move added later) -- not a move-specific
    -- patch.
    local abilityIdOf = mod.exports.abilityIdOf
    local id = abilityIdOf and abilityIdOf(who)
    if id == "HEAVYMETAL" then w = w * 2
    elseif id == "LIGHTMETAL" then w = w / 2 end
    return w
  end

  -- Real Showdown tiers (Heat Crash/Heavy Slam, identical formula):
  -- ratio = userWeight/targetWeight -- >=5 -> 120, >=4 -> 100, >=3 -> 80,
  -- >=2 -> 60, else -> 40.
  local function weightRatioPower(ctx)
    local userW = speciesWeightOf(ctx.user, ctx.gen2)
    local targetW = speciesWeightOf(ctx.target, ctx.gen2)
    if not (userW and targetW and targetW > 0) then return nil end
    local ratio = userW / targetW
    if ratio >= 5 then return 120
    elseif ratio >= 4 then return 100
    elseif ratio >= 3 then return 80
    elseif ratio >= 2 then return 60
    else return 40 end
  end
  registerPowerOverride("HEATCRASH", weightRatioPower)
  registerPowerOverride("HEAVYSLAM", weightRatioPower)

  -- Power Trip's registerPowerOverride call is further down, right after
  -- sideOfWho/stagesFor are actually declared (this file's own stat-
  -- stage store) -- both are `local function`s defined later in this
  -- same scope, so a closure up here would have captured them as
  -- unresolved globals instead of the real locals, not a working
  -- forward reference. See that call site's own comment for the
  -- mechanic itself.

  -- Flail: real Showdown HP-fraction tiers (permille, <= means at-or-
  -- below): <=4 -> 200, <=10 -> 150, <=20 -> 100, <=34 -> 80, <=67 -> 40,
  -- else -> 20. (416/1024, 1075/1024 etc. rounding is a Gen 3-era
  -- hardware artifact this mod doesn't replicate -- the whole-percent
  -- breakpoints above match real Showdown's own modern implementation.)
  -- Reversal (Phase 8, other bucket, added 2026-08-28, explicit user
  -- directive to close the real remaining move-formula gaps): real,
  -- confirmed Showdown fact -- Reversal and Flail share the IDENTICAL
  -- real HP-fraction power table, just different flavor/type. Reuses
  -- the exact same function rather than a second, possibly-drifting
  -- copy.
  local function flailPower(ctx)
    local hp, maxHp = currentAndMaxHP(ctx.user, ctx.gen2)
    local pct = 100 * hp / maxHp
    if pct <= 4 then return 200
    elseif pct <= 10 then return 150
    elseif pct <= 20 then return 100
    elseif pct <= 34 then return 80
    elseif pct <= 67 then return 40
    else return 20 end
  end
  registerPowerOverride("FLAIL", flailPower)
  registerPowerOverride("REVERSAL", flailPower)

  -- Low Kick / Grass Knot: real Showdown TARGET-weight tiers (kg) --
  -- confirmed a genuinely different real formula from Heat Crash/Heavy
  -- Slam's own ratio above, not a duplicate: <10 -> 20, <25 -> 40,
  -- <50 -> 60, <100 -> 80, <200 -> 100, else -> 120. Real games also
  -- special-case Dynamax/Gigantamax targets (treated as maximum weight,
  -- so always 120) -- this mod's own real Dynamax state IS queryable
  -- (gigantamax/gimmick_dynamax.lua's own armState/transforms registry),
  -- but wiring that cross-file check is deferred; every non-Dynamaxed
  -- target (the overwhelming common case) is fully correct.
  local function targetWeightPower(ctx)
    local w = speciesWeightOf(ctx.target, ctx.gen2)
    if not w then return nil end
    if w < 10 then return 20
    elseif w < 25 then return 40
    elseif w < 50 then return 60
    elseif w < 100 then return 80
    elseif w < 200 then return 100
    else return 120 end
  end
  registerPowerOverride("LOWKICK", targetWeightPower)
  registerPowerOverride("GRASSKNOT", targetWeightPower)

  -- Trump Card: real Showdown power scales with the move's OWN
  -- remaining PP (read from the user's own moveset slot, right after
  -- this use's own real PP deduction has already happened -- the same
  -- point registerPowerOverride's own callback fires at, confirmed by
  -- its own real call site: the formula reads power BEFORE computing
  -- damage, but PP is spent by the native engine earlier still, at
  -- move-selection time): 0 -> 200, 1 -> 80, 2 -> 60, 3 -> 50, else 40.
  registerPowerOverride("TRUMPCARD", function(ctx)
    local moves = ctx.gen2 and ctx.user.moves or (ctx.user.mon and ctx.user.mon.moves)
    local pp
    for _, mv in ipairs(moves or {}) do
      if mv.id == "TRUMPCARD" then pp = mv.pp break end
    end
    if not pp then return nil end
    if pp <= 0 then return 200
    elseif pp == 1 then return 80
    elseif pp == 2 then return 60
    elseif pp == 3 then return 50
    else return 40 end
  end)

  ------------------------------------------------------------------
  -- GalarGmaxDex-owned stat-stage store (atk/def/spa/spd only -- speed/
  -- accuracy/evasion stay 100% native for both generations, out of
  -- scope this phase). Both native engines already track stages
  -- correctly, but in two incompatible shapes (Gen 1: per-battler-
  -- wrapper mon.stages, combined "special"; Gen 2: per-side on the
  -- Battle object, split specialAttack/specialDefense) -- and, more to
  -- the point, Gen 2's native dispatch never actually reaches most
  -- stock stat-changing moves at all today: data.moves is Gen-1-ROM-
  -- sourced, Gen 2's own dispatcher looks up a different id convention
  -- (confirmed: gen2/Battle.lua's Battle.moveEffectRecordFor checks
  -- data.gen2MoveEffects/Battle.MOVE_EFFECT_RECORDS, both keyed
  -- "EFFECT_*", against data.moves[x].effect strings that are still
  -- Gen 1's "*_EFFECT" convention) -- Growl, Swords Dance etc. are
  -- non-functional on Gen 2 right now, mod or no mod. So this owns
  -- stage storage AND re-registers every atk/def/spa/spd move effect
  -- through one shared handler, rather than reading/writing whichever
  -- native storage happens to exist per generation.
  --
  -- Storage: stageState[battle] = { player = {attack=,defense=,spa=,
  -- spd=}, enemy = {...} }, the same battle-keyed-table shape already
  -- proven by gimmick_dynamax.lua's gState. A missing entry means
  -- "unmodified" (stage 0), same convention native tables already use.
  -- (Gen 2 detection/isGen2Battle already defined above, next to
  -- curTypesOf -- reused here, not redefined.)
  ------------------------------------------------------------------
  local stageState = {}
  local function ensureStageState(battle)
    local s = stageState[battle]
    if not s then
      s = { player = {}, enemy = {} }
      stageState[battle] = s
    end
    return s
  end
  local function stagesFor(battle, side)
    return ensureStageState(battle)[side]
  end
  -- Exported (Phase 8, other bucket): the same real, mod-owned atk/def/
  -- spa/spd stage bucket every existing stat-changing move/ability
  -- already reads and writes through changeStage above -- Download/
  -- Moody/Curious Medicine/Costar reuse it directly rather than a
  -- second, possibly-drifting stage store. Scoped the same way Power
  -- Trip's own header already documents this store's boundary: speed/
  -- accuracy/evasion stay native/out of scope here, not newly narrowed
  -- for this batch.
  mod.exports.stagesFor = stagesFor

  -- "player"/"enemy", uniformly, regardless of generation. Gen 1's own
  -- BattleState:sideOf returns a side-record object (not a string,
  -- confirmed BattleState.lua:1487), so this doesn't reuse it --
  -- who.isPlayer is the reliable Gen 1 signal (set at makeBattler
  -- construction). Gen 2's Battle:sideOf already returns "player"/
  -- "enemy" directly (confirmed gen2/Battle.lua:411-413), reused as-is.
  local function sideOfWho(battle, who, gen2)
    if gen2 then return battle:sideOf(who) end
    return who.isPlayer and "player" or "enemy"
  end
  mod.exports.sideOfWho = sideOfWho

  -- Power Trip (Part B Phase 5 Tier 1): real Showdown is 20 + 20*(sum of
  -- every POSITIVE stage across all 7 raiseable stats: atk/def/spa/spd/
  -- spe/accuracy/evasion). This mod's own stage store above only tracks
  -- atk/def/spa/spd (its own header a few lines up: speed/accuracy/
  -- evasion stay native, out of scope this phase) -- speed/accuracy/
  -- evasion stages are therefore NOT counted here. A genuine partial
  -- implementation, flagged rather than silently passed off as complete:
  -- a mon that only raised Speed/accuracy/evasion (never atk/def/spa/
  -- spd) reads as +0 here and deals a flat 20 power, same as real
  -- Showdown would only if none of the 7 stats were raised.
  registerPowerOverride("POWERTRIP", function(ctx)
    local stages = stagesFor(ctx.battle, sideOfWho(ctx.battle, ctx.user, ctx.gen2)) or {}
    local total = 0
    for _, key in ipairs({ "attack", "defense", "spa", "spd" }) do
      total = total + math.max(0, stages[key] or 0)
    end
    return 20 + 20 * total
  end)

  -- ---------------------------------------------------------------
  -- The rest of the variable-power roster.
  --
  -- These six had no override at all, so they fell through to a stored
  -- power of 0 and dealt nothing. Every input below is an existing,
  -- already-exported primitive -- no new plumbing.
  -- ---------------------------------------------------------------

  -- Crush Grip and Wring Out: power falls with the TARGET's remaining HP.
  -- One function for both, the same way flailPower serves Flail and
  -- Reversal -- two copies of one formula is two chances to drift.
  local function targetHpFractionPower(scale)
    return function(ctx)
      local hp, maxHp = currentAndMaxHP(ctx.target, ctx.gen2)
      if not (hp and maxHp) or maxHp <= 0 then return 1 end
      return math.max(1, math.floor(scale * hp / maxHp))
    end
  end
  registerPowerOverride("CRUSHGRIP", targetHpFractionPower(120))
  registerPowerOverride("WRINGOUT", targetHpFractionPower(120))
  -- Hard Press is the same shape on a 100 scale.
  registerPowerOverride("HARDPRESS", targetHpFractionPower(100))

  -- Punishment: harder the more the TARGET has buffed itself. Power Trip
  -- above is the same idea pointed at the user, and carries the same honest
  -- limitation -- stagesFor only tracks atk/def/spa/spd, so a target that
  -- raised only Speed, accuracy or evasion reads as +0 here. Flagged rather
  -- than passed off as complete, exactly as Power Trip's own header does.
  registerPowerOverride("PUNISHMENT", function(ctx)
    local stages = stagesFor(ctx.battle,
      sideOfWho(ctx.battle, ctx.target, ctx.gen2)) or {}
    local total = 0
    for _, key in ipairs({ "attack", "defense", "spa", "spd" }) do
      total = total + math.max(0, stages[key] or 0)
    end
    return math.min(200, 60 + 20 * total)
  end)

  local function displayNameFor(battle, who, gen2)
    if gen2 then
      local nm = battle:monName(who)
      return sideOfWho(battle, who, true) == "player" and nm or Strings("Enemy %s", nm)
    end
    return (who.isPlayer and who.name) or Strings("Enemy %s", who.name)
  end

  -- Mist/Substitute gate -- same rule both generations share (a status
  -- move can't lower a Substitute'd/Mist'd target's stat from the
  -- outside), different field shapes per engine's own volatile-state
  -- convention: Gen 1 keeps the flags directly on the battler wrapper;
  -- Gen 2 keeps them in Battle:volatile(mon) (confirmed
  -- gen2/Battle.lua:968 construction, :2010 mist read, substitute is a
  -- remaining-HP number rather than a boolean).
  local function isProtectedFrom(battle, who, gen2)
    if gen2 then
      local vol = battle:volatile(who)
      return (vol.substitute or 0) > 0, vol.mist
    end
    return who.substituteHP, who.mist
  end

  local function rawStat(who, key, gen2)
    return gen2 and who.stats[key] or who.curStats[key]
  end

  -- Registered HERE, below rawStat, and not beside the other power
  -- overrides above it: these two are the only ones that read a raw
  -- stat, and a local named above its definition is not that local --
  -- Lua compiles it to a global, nil at runtime. The suite's own
  -- bytecode lint caught exactly that on the first attempt.
  -- Gyro Ball: the SLOWER the user, the harder it hits.
  -- min(150, floor(25 * targetSpeed / userSpeed) + 1). Guarded against a
  -- zero/absent user Speed, which would otherwise divide by zero and hand
  -- the damage formula a nan.
  registerPowerOverride("GYROBALL", function(ctx)
    local userSpeed = rawStat(ctx.user, "speed", ctx.gen2) or 0
    local targetSpeed = rawStat(ctx.target, "speed", ctx.gen2) or 0
    if userSpeed <= 0 then return 150 end
    return math.min(150, math.floor(25 * targetSpeed / userSpeed) + 1)
  end)

  -- Electro Ball: the mirror image -- the FASTER the user, the harder it
  -- hits -- and a tier table rather than a continuous ratio.
  registerPowerOverride("ELECTROBALL", function(ctx)
    local userSpeed = rawStat(ctx.user, "speed", ctx.gen2) or 0
    local targetSpeed = rawStat(ctx.target, "speed", ctx.gen2) or 0
    if targetSpeed <= 0 then return 150 end
    local ratio = userSpeed / targetSpeed
    if ratio >= 4 then return 150
    elseif ratio >= 3 then return 120
    elseif ratio >= 2 then return 80
    elseif ratio >= 1 then return 60
    else return 40 end
  end)

  -- Exported (Phase 8, other bucket): Download/Beast Boost's own real
  -- "compare/find the highest raw stat" both need this same accessor
  -- the damage formula itself already uses -- "attack"/"defense"/"spa"/
  -- "spd" are the real key strings, confirmed by this function's own
  -- pre-existing call sites just below.
  mod.exports.rawStat = rawStat

  local function badgeStatNameFor(statKey)
    if statKey == "spa" or statKey == "spd" then return "special" end
    return statKey
  end

  -- Kanto badge boosts. Gen 1 battler-wrapper-only (battler.badges) --
  -- silently a no-op for Gen 2 (raw mon has no .badges field), which is
  -- correct: Johto badge boosts are a separate native Gen 2 mechanic
  -- this file doesn't touch either way.
  local function badgeBoost(battler, statKey)
    local badges = battler.badges
    if not badges then return nil end
    local badgeStat = badgeStatNameFor(statKey)
    for _, row in ipairs(battler.badgeBoosts or Damage.BADGE_BOOSTS) do
      if row.stat == badgeStat and badges[row.badge] then return row end
    end
    return nil
  end

  -- Burn's attack-halving penalty: Gen 1 battler-wrapper shape only for
  -- now (battler.statuses/battler.mon.status is that wrapper's own
  -- convention) -- Gen 2's status-penalty equivalent is a separate,
  -- not-yet-scoped piece of work, flagged here rather than guessed at.
  local function statusRecord(battler, gen2)
    if gen2 then return nil end
    return Status.recordFor(battler.statuses, battler.mon.status)
  end

  ------------------------------------------------------------------
  -- Canonical stage-change: attack/defense/spa/spd, both generations,
  -- one code path -- replaces the old changeModernStage (which only
  -- ever owned spa/spd, Gen 1 only, deferring attack/defense to native
  -- MoveEffects.changeStage). Same contract/messages/clamp native
  -- always had (Mist/Substitute protection, the -6..+6 clamp, "nothing
  -- happened", the rise/greatly-rose message tiers), just backed by our
  -- own store instead of whichever native table happens to exist per
  -- generation. Exported so future ability/item work can reuse it.
  ------------------------------------------------------------------
  local STAT_LABEL = { attack = "Attack", defense = "Defense", spa = "Sp. Atk", spd = "Sp. Def" }

  -- Turns either engine's move-effect run() call into one shape:
  -- {battle=, user=, target=, gen2=}. Gen 1's run(ctx) already hands us
  -- a ctx facade (EffectRegistry.makeCtx, ctx.battle always present);
  -- Gen 2's run(battle, attacker, defender, def, moveId, sureHit) is
  -- six positional args (confirmed gen2/Battle.lua:1529, documented at
  -- :2645-2648) -- a is the raw Battle instance there, which has no
  -- .battle field of its own, so the discriminator is safe.
  local function normalize(a, b, c)
    if type(a) == "table" and a.battle ~= nil then
      return { battle = a.battle, user = a.user, target = a.target, gen2 = false }
    end
    return { battle = a, user = b, target = c, gen2 = true }
  end

  -- Boss-fight "statsDrop" protection (combat/boss_fight.lua): true when
  -- `who` can't have this delta applied at all -- the boss can't have ANY
  -- stat lowered while protected, hostile OR self-inflicted (explicit
  -- user rule: "not even self," unlike the Substitute/Mist check below,
  -- which only ever blocks a hostile change). Exported, not inlined only
  -- here: combat/modern_movepool_stages.lua's changeNativeStage and
  -- abilities/engine/switchin_stat_change.lua's native-store branch both
  -- route speed/accuracy/evasion through Gen 2's own native
  -- Battle:changeStageAgainstMist DIRECTLY, bypassing this function (and
  -- its own Substitute check) entirely -- both of those call sites check
  -- this same rule before ever reaching the native call, so a boss's
  -- speed/accuracy/evasion is protected exactly as completely as its
  -- attack/defense/spa/spd.
  -- Real N-way check (2026-08-28): every enemy-side battler protected,
  -- not just the literal battle.enemy object -- a boss fight WITH real
  -- escorts (g9-Battle-Scene's own doubles/triples layouts) needs every
  -- one of them covered, not just whichever mon happens to be primary.
  mod.exports.bossStatsDropBlocked = function(battle, who, delta)
    return delta < 0 and battle ~= nil and who ~= nil and battle:sideOf(who) == "enemy"
      and mod.exports.bossFightHas ~= nil and mod.exports.bossFightHas(battle, "statsDrop")
  end

  -- Phase 7 (prevent bucket): the real "can't have THIS stat lowered by
  -- an opponent" family -- Clear Body/Full Metal Body/White Smoke (every
  -- stat), Hyper Cutter (Attack only), Big Pecks (Defense only), Keen
  -- Eye/Mind's Eye (accuracy only), Flower Veil (every stat, but only a
  -- Grass-type holder -- real Flower Veil protects Grass-type ALLIES, not
  -- unconditionally; this engine has no separate ally slot in a 1v1
  -- battle, so "is the holder itself Grass-type" is the one real case
  -- reachable today, same honest reduction Sweet Veil's own self+allies
  -- scope already used in Phase 3). Exported so the two OTHER real call
  -- sites this same rule has to cover (Gen 2's native speed/accuracy/
  -- evasion path in abilities/engine/stage_change_transform.lua, Gen 1's
  -- own NATIVE_STATS branch in main.lua -- neither of which routes
  -- through this function at all) share one definition instead of three
  -- copies that could drift. Self-inflicted drops (Overheat/Close Combat/
  -- Superpower against oneself, a stat-lowering ability triggering on its
  -- own holder) are NEVER blocked by this family in the real games -- only
  -- checked when `fromEnemy` is true, matching this file's own existing
  -- Mist/Substitute check immediately below.
  local ALL_STATS_IMMUNE = { CLEARBODY = true, FULLMETALBODY = true, WHITESMOKE = true }
  local SINGLE_STAT_IMMUNE = {
    HYPERCUTTER = "attack", BIGPECKS = "defense",
    KEENEYE = "accuracy", MINDSEYE = "accuracy",
  }
  local function statDropBlockedByAbility(who, gen2, stat)
    local abilityIdOf = mod.exports.abilityIdOf
    local id = who and abilityIdOf and abilityIdOf(who)
    if not id then return false end
    if ALL_STATS_IMMUNE[id] then return true end
    if SINGLE_STAT_IMMUNE[id] == stat then return true end
    if id == "FLOWERVEIL" then
      local curTypesOf = mod.exports.curTypesOf
      if curTypesOf then
        for _, t in ipairs(curTypesOf(who, gen2)) do
          if t == "GRASS" then return true end
        end
      end
    end
    return false
  end
  mod.exports.statDropBlockedByAbility = statDropBlockedByAbility

  -- Opportunist (Phase 8, other bucket): "copies the stat and stage
  -- amount of any stat boost an OPPONENT gains, onto itself" -- real,
  -- confirmed reactive copy, checked here (the one real choke point
  -- every stage change in this mod already goes through, the same
  -- reason Neutralizing Gas's own suppression lives inside abilityIdOf
  -- itself rather than a later wrap) rather than as a separate dispatch
  -- engine wrapping mod.exports.changeStage -- every earlier-loading
  -- caller already captured a LOCAL reference to this exact function at
  -- its own install time, so a later reassignment of mod.exports.
  -- changeStage would never reach any of them, the same confirmed dead
  -- end Neutralizing Gas's own header already documents.
  --
  -- Per-battle recursion guard: a copy is itself a stage change, so
  -- without this an Opportunist holder on BOTH sides would ping-pong
  -- forever. Real Showdown doesn't chain Opportunist copies either.
  local opportunistGuard = setmetatable({}, { __mode = "k" })
  local changeStageFwd -- forward-declared, assigned right after changeStage below
  local function triggerOpportunist(battle, who, stat, delta, gen2)
    if opportunistGuard[battle] then return end
    local requestAdjacency = mod.exports.requestAdjacency
    local abilityIdOf = mod.exports.abilityIdOf
    if not (requestAdjacency and abilityIdOf) then return end
    for _, foe in ipairs(requestAdjacency(battle, who, nil).enemies) do
      if foe and (foe.hp or 0) > 0 and abilityIdOf(foe) == "OPPORTUNIST" then
        opportunistGuard[battle] = true
        local ok, err = pcall(changeStageFwd, battle, foe, stat, delta, false, gen2)
        opportunistGuard[battle] = nil
        if not ok then mod.log:warn("g9-battle-engine-beta: Opportunist copy failed: %s", tostring(err)) end
      end
    end
  end

  -- Mirror Armor (Phase 8, other bucket): "any effect that would lower
  -- this Pokemon's stats instead lowers the stats of whoever caused the
  -- effect." Real, confirmed redirect -- needs to know WHO caused this
  -- specific drop, which changeStage's own signature never carried and
  -- was never going to be threaded through its ~10+ existing call sites
  -- (a genuine, rejected-as-too-invasive alternative) -- closed instead
  -- via combat/interaction_memory.lua's own real "who did what to whom,
  -- most recently" primitive (explicit user design), looked up here by
  -- `who` alone. Per-battle recursion guard, same shape Opportunist's
  -- own copy-trigger just below already uses, in case the redirect
  -- target ALSO has Mirror Armor.
  local mirrorArmorGuard = setmetatable({}, { __mode = "k" })
  local function mirrorArmorRedirect(battle, who, gen2)
    local abilityIdOf = mod.exports.abilityIdOf
    local lastInteractionAgainst = mod.exports.lastInteractionAgainst
    if not (abilityIdOf and lastInteractionAgainst and abilityIdOf(who) == "MIRRORARMOR") then
      return nil
    end
    if mirrorArmorGuard[battle] then return nil end
    local record = lastInteractionAgainst(battle, who)
    local source = record and record.source
    if not (source and source ~= who and (source.hp or 0) > 0) then return nil end
    return source
  end

  local function changeStage(battle, who, stat, delta, fromEnemy, gen2)
    if mod.exports.bossStatsDropBlocked(battle, who, delta) then
      return { romText(battle.data, "_NothingHappenedText", "Nothing happened!") }
    end
    if fromEnemy and delta < 0 then
      local source = mirrorArmorRedirect(battle, who, gen2)
      if source then
        mirrorArmorGuard[battle] = true
        local ok, result = pcall(changeStageFwd, battle, source, stat, delta, true, gen2)
        mirrorArmorGuard[battle] = nil
        if ok then return result end
        mod.log:warn("g9-battle-engine-beta: Mirror Armor redirect failed: %s", tostring(result))
      end
    end
    if fromEnemy and delta < 0 and statDropBlockedByAbility(who, gen2, stat) then
      return { Strings("%s's stats\nwon't go lower!", displayNameFor(battle, who, gen2)) }
    end
    local protectedBySub, mist = isProtectedFrom(battle, who, gen2)
    if fromEnemy and (protectedBySub or mist) then
      if mist then
        return { Strings("%s is\nprotected by MIST!", displayNameFor(battle, who, gen2)) }
      end
      return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
    end
    -- Phase 8 (Contrary/Simple): applied AFTER the boss-protection and
    -- Mist/Substitute checks above, which reason about the RAW,
    -- originally-intended sign -- a boss's statsDrop immunity, or Mist
    -- blocking a hostile decrease, must not be defeated just because the
    -- holder also has Contrary -- but BEFORE the stage math and the
    -- outcome message below, so both correctly reflect what actually
    -- happens (Contrary's "fell"->"rose" flip, Simple's doubled
    -- magnitude). Looked up lazily (abilities/ability_dispatch.lua may
    -- load after this file within the same session but always before any
    -- real battle runs).
    local id = mod.exports.abilityIdOf and mod.exports.abilityIdOf(who)
    if id == "CONTRARY" then delta = -delta
    elseif id == "SIMPLE" then delta = delta * 2 end
    local stages = stagesFor(battle, sideOfWho(battle, who, gen2))
    local cur = stages[stat] or 0
    local new = math.max(-6, math.min(6, cur + delta))
    if new == cur then
      return { romText(battle.data, "_NothingHappenedText", "Nothing happened!") }
    end
    stages[stat] = new
    who.hazeStatReset = nil
    -- Opportunist trigger: fires on any GENUINE rise (delta computed
    -- AFTER Contrary/Simple's own transform above, matching real
    -- Opportunist's own "copies the stat and stage amount" wording --
    -- it copies what actually happened, not the move's nominal intent).
    if new > cur then
      triggerOpportunist(battle, who, stat, new - cur, gen2)
    end
    local label = STAT_LABEL[stat]
    local name = displayNameFor(battle, who, gen2)
    if delta >= 2 then
      return { Strings("%s's\n%s\ngreatly rose!", name, label) }
    elseif delta == 1 then
      return { Strings("%s's\n%s rose!", name, label) }
    elseif delta == -1 then
      return { Strings("%s's\n%s fell!", name, label) }
    end
    return { Strings("%s's\n%s\ngreatly fell!", name, label) }
  end
  changeStageFwd = changeStage
  mod.exports.changeStage = changeStage
  -- Exported so sibling files (modern_movepool_stages.lua) can bridge
  -- Gen1/Gen2 move_effects run() calls the same way this file's own
  -- GMAX_* handlers do, instead of re-deriving the discriminator.
  mod.exports.normalize = normalize
  -- Exported for Phase 2 siblings (modern_movepool_status.lua) that need
  -- a battler's display name on BOTH generations -- EffectRegistry's own
  -- displayName (src/battle/EffectRegistry.lua) is Gen 1-only (reads
  -- who.name directly, which doesn't exist on a Gen 2 mon), so a
  -- primary() handler meant to run on both engines needs this version
  -- instead, same as changeStage/normalize above.
  mod.exports.displayNameFor = displayNameFor

  -- Resets a battler's OWN atk/def/spa/spd store to 0 (Clear Smog-style
  -- "wipe every stat stage" moves -- Haze-likes, if this mod ever needs
  -- one, reuse this too). Speed/accuracy/evasion are NOT this store's
  -- business (see the store's own header above) -- a caller resetting
  -- those goes straight to native storage instead, same as any other
  -- speed/accuracy/evasion change (modern_movepool_stages.lua's
  -- changeNativeStage). Returns whether anything was actually 0'd, for a
  -- caller that wants to print "Nothing happened!" on a no-op.
  local function resetStages(battle, who, gen2)
    local stages = stagesFor(battle, sideOfWho(battle, who, gen2))
    local changed = false
    for _, stat in ipairs({ "attack", "defense", "spa", "spd" }) do
      if (stages[stat] or 0) ~= 0 then
        stages[stat] = nil
        changed = true
      end
    end
    return changed
  end
  mod.exports.resetStages = resetStages

  -- One registration per native atk/def stat-effect id (statUp/
  -- statDown's exact real ids, MoveEffects.lua:166-178), both
  -- generations, one shared handler. targetsSelf=true mirrors native
  -- statUp (raises the move's own user, fromEnemy=false); false
  -- mirrors native statDown (lowers the target, fromEnemy=true so
  -- Mist/Substitute gate it). Speed/accuracy/evasion ids
  -- (SPEED_UP2_EFFECT, SPEED_DOWN1_EFFECT, EVASION_UP1_EFFECT,
  -- ACCURACY_DOWN1_EFFECT) are deliberately NOT registered here -- out
  -- of scope this phase, left exactly as native already handles them.
  -- override, not register: these 7 ids are native Gen 1 ids the base
  -- game already registers (unlike the GMAX_*-prefixed custom ids below,
  -- which are new) -- :register throws "already registered" against an
  -- existing record-semantics entry, :override replaces it outright
  -- (confirmed src/mods/Registry.lua:90-104).
  local function registerStatEffect(id, stat, delta, targetsSelf)
    mod.content.move_effects:override(id, {
      kind = "primary",
      run = function(a, b, c)
        local n = normalize(a, b, c)
        local who = targetsSelf and n.user or n.target
        return changeStage(n.battle, who, stat, delta, not targetsSelf, n.gen2)
      end,
    })
  end

  registerStatEffect("ATTACK_UP1_EFFECT", "attack", 1, true)
  registerStatEffect("ATTACK_UP2_EFFECT", "attack", 2, true)
  registerStatEffect("DEFENSE_UP1_EFFECT", "defense", 1, true)
  registerStatEffect("DEFENSE_UP2_EFFECT", "defense", 2, true)
  registerStatEffect("ATTACK_DOWN1_EFFECT", "attack", -1, false)
  registerStatEffect("DEFENSE_DOWN1_EFFECT", "defense", -1, false)
  registerStatEffect("DEFENSE_DOWN2_EFFECT", "defense", -2, false)

  -- The only three native Gen-1 moves that touched the old shared
  -- "special" stage (confirmed by grepping the engine's own generated
  -- moves.lua for every SPECIAL_UP1_EFFECT/SPECIAL_UP2_EFFECT/SPECIAL_DOWN_SIDE_EFFECT
  -- reference -- exactly AMNESIA, GROWTH, PSYCHIC_M, nothing else).
  -- Re-pointed at real Gen 2+ targeting instead of Gen 1's combined
  -- Special stat. None of GalarGmaxDex's own 174 new moves reference any
  -- stat-stage effect yet (grepped: zero matches) -- those are a
  -- separate, pre-existing "NO_ADDITIONAL_EFFECT placeholder" gap this
  -- pass does not attempt to close.
  mod.content.move_effects:register("GMAX_AMNESIA_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      -- Amnesia: Sp. Def +2 only (Gen 2+), not the combined Special +2
      -- Gen 1 originally had.
      return changeStage(n.battle, n.user, "spd", 2, false, n.gen2)
    end,
  })
  mod.content.moves:patch("AMNESIA", { effect = "GMAX_AMNESIA_EFFECT" })

  mod.content.move_effects:register("GMAX_GROWTH_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      -- Growth: Attack +1 AND Sp. Atk +1 (Gen 5+ behavior; Gen 2-4 only
      -- raised Special/Sp.Atk -- Gen 5+ is the more modern, current rule
      -- and matches this ruleset's overall Gen 9-oriented direction).
      -- Real, confirmed exception (a genuine pre-existing gap, fixed
      -- here alongside Mega Sol since both hinge on the same "is this
      -- mon's own sun in effect" question): DOUBLED to +2/+2 in harsh
      -- sunlight -- real field sun, or Mega Sol's own personal
      -- simulation of it (Phase 8, other bucket).
      local abilityIdOf = mod.exports.abilityIdOf
      local weather = mod.exports.currentWeather and mod.exports.currentWeather(n.battle, n.gen2)
      local inSun = weather == "SUN" or (abilityIdOf and abilityIdOf(n.user) == "MEGASOL")
      local stages = inSun and 2 or 1
      local atkMsg = changeStage(n.battle, n.user, "attack", stages, false, n.gen2)
      local spaMsg = changeStage(n.battle, n.user, "spa", stages, false, n.gen2)
      local out = {}
      for _, m in ipairs(atkMsg) do out[#out + 1] = m end
      for _, m in ipairs(spaMsg) do out[#out + 1] = m end
      return out
    end,
  })
  mod.content.moves:patch("GROWTH", { effect = "GMAX_GROWTH_EFFECT" })

  -- Psychic's secondary Sp.Def-drop chance. Still kind="secondary",
  -- deliberately NOT redesigned this phase: confirmed broken on Gen 2
  -- today independent of this change (Gen 2's dispatch runs ANY
  -- move_effects record with a .run field and returns immediately,
  -- before the damage path, so a secondary-kind record currently
  -- pre-empts the whole move instead of following it --
  -- gen2/Battle.lua:1526-1531). Explicit decision: once combat is fully
  -- owned, secondary/chance-based effects get applied by the mod's own
  -- turn processing after damage lands but before the turn ends, not
  -- through this registry at all -- see the combat-ownership notes.
  -- For now this just avoids crashing on Gen 2 (n.gen2 short-circuits
  -- to a clean no-op) rather than attempting a real fix here.
  mod.content.move_effects:register("GMAX_PSYCHIC_SPD_EFFECT", {
    kind = "secondary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if n.gen2 then return {} end
      if n.target.substituteHP then return {} end
      if n.battle.rng(0, 255) >= 85 then return {} end
      return changeStage(n.battle, n.target, "spd", -1, false, n.gen2)
    end,
  })
  mod.content.moves:patch("PSYCHIC_M", { effect = "GMAX_PSYCHIC_SPD_EFFECT" })

  ------------------------------------------------------------------
  -- Modern stage-based crit: stage 0 = 1/24, 1 = 1/8, 2 = 1/2, 3+ =
  -- always -- Gen 6+ rates, not Gen 1's speed-based roll. Flat 1.5x
  -- multiplier on hit (not Gen 1's x2), and crit does NOT double level
  -- (another Gen-1-only quirk dropped here).
  ------------------------------------------------------------------
  local CRIT_STAGE_DENOM = { [0] = 24, [1] = 8, [2] = 2, [3] = 1 }

  local function modernCritStage(ctx)
    local stage = 0
    if ctx.move.highCrit then stage = stage + 1 end
    if ctx.user.focusEnergy then stage = stage + 2 end
    for _, fn in pairs(critStageModifiers) do
      stage = stage + (fn(ctx) or 0)
    end
    if stage < 0 then stage = 0 end
    if stage > 3 then stage = 3 end
    return stage
  end

  -- Phase 7 (prevent bucket): Battle Armor/Shell Armor -- real modern
  -- Showdown behavior is an outright ban on landing a crit against the
  -- holder, not merely capping the stage at 0 (stage 0 is still 1/24, not
  -- zero) -- checked here, before the stage/denom lookup even runs, so a
  -- stage-3+ "always crits" guarantee (Merciless, a high-crit move plus
  -- Focus Energy) is correctly overridden too.
  local CRIT_IMMUNE_ABILITY = { BATTLEARMOR = true, SHELLARMOR = true }
  local function modernCritRoll(ctx)
    local abilityIdOf = mod.exports.abilityIdOf
    local id = ctx.target and abilityIdOf and abilityIdOf(ctx.target)
    if id and CRIT_IMMUNE_ABILITY[id] then return false end
    local denom = CRIT_STAGE_DENOM[modernCritStage(ctx)]
    return ctx.rng(1, denom) == 1
  end

  ------------------------------------------------------------------
  -- The formula itself. ctx is exactly what BattleState:computeDamage
  -- builds for the battle.damage hook: { battle, ruleset, user, target,
  -- move, opts, rng }. Returns (damage, {crit=, typeMult=x10}) --
  -- Damage.compute's exact return shape, since callers (EffectRegistry's
  -- damaging-move path) expect it verbatim.
  ------------------------------------------------------------------
  local function computeModernDamage(ctx)
    local user, target, move, opts, rng = ctx.user, ctx.target, ctx.move, ctx.opts or {}, ctx.rng


    -- MoveCategory.of returns capitalized "Physical"/"Special"/"Status" --
    -- deliberately NOT the lowercase move.category some data carries
    -- (Damage.lua's own internal categoryOf compares lowercase; these are
    -- two different casing conventions coexisting in this codebase
    -- depending on data origin, so always go through MoveCategory.of).
    local category = MoveCategory.of(move) or "Physical"
    -- A COMPUTED power is not an absent one.
    --
    -- This bail used to read `(move.power or 0) == 0`, full stop -- and it
    -- runs ~200 lines before powerOverrides is consulted, so a move whose
    -- power is DERIVED (Heavy Slam, Grass Knot, Trump Card, Spit Up, Fling,
    -- Low Kick...) returned 0 here and its already-written override never
    -- fired. Every one of those handlers existed and none of them ran.
    --
    -- It surfaced because PokeAPI reports `power: null` for exactly these
    -- moves -- the power is computed, so there is no number to report -- and
    -- national_dex faithfully writes 0. The base game distinguishes the two
    -- cases with a placeholder of 1 (its own NIGHT_SHADE, COUNTER and
    -- REVERSAL records all ship `power = 1`), but this engine should not
    -- depend on every data source knowing that convention: if a move has a
    -- registered override, the override IS its power, and a stored 0 is
    -- simply the absence of a stored number.
    --
    -- Status still bails unconditionally: an override cannot make a status
    -- move deal damage, and nothing registers one for a status move.
    -- ENDEAVOR does not scale a power at all -- it returns a flat HP
    -- difference from its own branch below -- so it has no override to find
    -- and still must not be turned away here. Its own comment below already calls
    -- power=1 "that convention's placeholder for computed at runtime".
    local hasComputedPower = powerOverrides[move.id] ~= nil
      or COMPUTES_OWN_DAMAGE[move.id]
    if category == "Status" or ((move.power or 0) == 0 and not hasComputedPower) then
      return 0, { crit = false, typeMult = 10 }
    end

    -- monLooksGen2 fallback: see its own definition above for why
    -- ctx.battle's identity alone isn't always trustworthy here.
    local gen2 = isGen2Battle(ctx.battle) or monLooksGen2(user) or monLooksGen2(target)

    -- Endeavor: not a scaled-power move at all (real PBS power=1 is that
    -- convention's placeholder for "computed at runtime", same as Heat
    -- Crash/Heavy Slam/Power Trip/Flail below) -- real Showdown sets
    -- target HP straight down to user's current HP, dealing 0 (a genuine
    -- fail, not a 1-damage hit) if the target is already at or below
    -- that. mon.hp/mon.stats.hp are the confirmed real current/max HP
    -- fields (modern_movepool_damage.lua:40's own header); Gen 2's own
    -- fallback chain (maxHp, then stats.hp) is reused as-is via
    -- currentAndMaxHP. Returns straight out of the whole formula --
    -- crit/STAB/weather/type-effectiveness never apply to a fixed HP-set
    -- effect in real Showdown either.
    if move.id == "ENDEAVOR" then
      local userHp = (currentAndMaxHP(user, gen2))
      local targetHp = (currentAndMaxHP(target, gen2))
      if targetHp <= userHp then
        return 0, { crit = false, typeMult = 10 }
      end
      return targetHp - userHp, { crit = false, typeMult = 10 }
    end

    -- Idempotent -- only fills fields that are missing, safe every call.
    -- Gen 1 only: user.def/user.mon are battler-wrapper fields that
    -- don't exist on Gen 2's raw mon objects -- gen2_modern_stats.lua
    -- already guarantees modern stats are present by battle.started
    -- time for every Gen 2 wild/trainer mon.
    if not gen2 then
      ModernStats.ensure(user.def, user.mon)
      ModernStats.ensure(target.def, target.mon)
    end

    local crit = opts.forceCrit
    if crit == nil then
      if Runtime.wantsHook("battle.crit") then
        crit = Runtime.call("battle.crit", function(c) return modernCritRoll(c) end,
          { battle = ctx.battle, user = user, move = move, rng = rng })
      else
        crit = modernCritRoll({ user = user, move = move, rng = rng })
      end
    end

    local special = category == "Special"
    local atkStat = special and "spa" or "attack"
    local defStat = special and "spd" or "defense"
    -- Psyshock / Psystrike / Secret Sword (Phase 8, other bucket, added
    -- 2026-08-28, explicit user directive -- real Gen 9 Showdown logic):
    -- all three are real, confirmed exceptions -- Special-category
    -- damage (their own attacking stat stays Sp. Atk, unaffected) that
    -- reads the DEFENDER's Defense stat instead of Sp. Def. Checked by
    -- move id directly (a fixed, small, real list -- Showdown itself
    -- special-cases these three by id too, not a flag), same
    -- established precedent as this file's own CRASH_DAMAGE_MOVES list.
    if move.id == "PSYSHOCK" or move.id == "PSYSTRIKE" or move.id == "SECRETSWORD" then
      defStat = "defense"
    end

    local atk, dfn
    if crit and ctx.ruleset and ctx.ruleset.critIgnoresStages then
      atk = rawStat(user, atkStat, gen2)
      dfn = rawStat(target, defStat, gen2)
    else
      local userStages = stagesFor(ctx.battle, sideOfWho(ctx.battle, user, gen2))
      local targetStages = stagesFor(ctx.battle, sideOfWho(ctx.battle, target, gen2))
      -- Unaware (Phase 8, other bucket): "ignores OTHER Pokémon's stat
      -- stage changes when calculating damage" -- real, confirmed
      -- direction: the DEFENDER's own Unaware ignores the ATTACKER's
      -- attack-stat boost (atkStage zeroed); the ATTACKER's own Unaware
      -- ignores the DEFENDER's defense-stat boost (defStage zeroed).
      -- Never ignores the holder's OWN stage in either direction, only
      -- the opponent's -- confirmed via Showdown's own real ruling
      -- (a +6 Swords Dance Unaware user still hits as hard as its own
      -- boost allows, it just isn't stopped by a target's own Cotton
      -- Guard).
      local abilityIdOf = mod.exports.abilityIdOf
      local atkStage = userStages[atkStat] or 0
      local defStage = targetStages[defStat] or 0
      if abilityIdOf and abilityIdOf(target) == "UNAWARE" then atkStage = 0 end
      if abilityIdOf and abilityIdOf(user) == "UNAWARE" then defStage = 0 end
      atk = Stats.applyStage(rawStat(user, atkStat, gen2), atkStage)
      dfn = Stats.applyStage(rawStat(target, defStat, gen2), defStage)
      local atkBoost = badgeBoost(user, atkStat)
      if atkBoost then
        atk = math.floor(atk * (atkBoost.num or 9) / (atkBoost.den or 8))
      end
      local defBoost = badgeBoost(target, defStat)
      if defBoost then
        dfn = math.floor(dfn * (defBoost.num or 9) / (defBoost.den or 8))
      end
      -- Burn's statPenalty.stat is always "attack" (Status.lua), so this
      -- naturally never touches Special -- no extra casing needed. Gen 1
      -- only for now -- see statusRecord.
      local record = statusRecord(user, gen2)
      local penalty = record and record.statPenalty
      if penalty and penalty.stat == atkStat and not user.hazeStatReset then
        atk = math.max(1, math.floor(atk / penalty.div))
      end
      -- Held-item stat multipliers (Choice Band/Specs, Assault Vest,
      -- Eviolite, Light Ball, Thick Club, Deep Sea Tooth/Scale, Metal
      -- Powder) -- combat/modern_held_items_phase2.lua's own real
      -- primitive, consulted here via a lazy export lookup (that file
      -- loads AFTER this one, so it can't be a plain local call) rather
      -- than inlined directly, keeping every held-item detail in that
      -- file's own single place. A nil export (that file not loaded)
      -- leaves atk/dfn untouched, same graceful-degradation shape
      -- Delta Stream's own effectivenessOverrideFor already uses.
      local applyHeldItemStatMultiplier = mod.exports.applyHeldItemStatMultiplier
      if applyHeldItemStatMultiplier then
        atk, dfn = applyHeldItemStatMultiplier(ctx, user, target, atkStat, defStat, atk, dfn)
      end
      if not crit then
        -- Real bug fixed (2026-08-28): no caller anywhere in this mod
        -- ever set opts.screens, so this always fell through to reading
        -- target.lightScreen/target.reflect directly -- correct for Gen 1
        -- (src/battle/MoveEffects.lua's own real Reflect/Light Screen
        -- handlers set exactly those per-mon fields), but Gen 2's own
        -- native screens are SIDE-keyed (self.screens[side].lightScreen/
        -- .reflect, gen2/Battle.lua:2585-2595), never written onto a mon
        -- at all -- meaning Reflect/Light Screen silently did NOTHING in
        -- this mod's own modern damage formula on Gen 2, confirmed by
        -- direct read (zero other references to opts.screens or
        -- battle:screenActive anywhere in this mod). Fixed by computing
        -- the real per-side answer via battle:screenActive (the exact
        -- native choke point TryHit's own DamageStats already reads)
        -- when gen2 is true, instead of trusting a per-mon field that
        -- was never populated.
        local screens = opts.screens
        if screens == nil and not opts.typeless then
          if gen2 and ctx.battle and ctx.battle.screenActive then
            screens = {
              lightScreen = ctx.battle:screenActive(target, false),
              reflect = ctx.battle:screenActive(target, true),
            }
          else
            screens = target
          end
        end
        -- Infiltrator (Phase 7, prevent bucket): the attacker's screens
        -- become fully transparent -- checked here, the one real choke
        -- point both engines' screen reduction goes through, rather than
        -- a second parallel check anywhere else.
        local abilityIdOf = mod.exports.abilityIdOf
        if screens and abilityIdOf and abilityIdOf(user) == "INFILTRATOR" then
          screens = nil
        end
        if screens then
          if special and screens.lightScreen then dfn = dfn * 2 end
          if not special and screens.reflect then dfn = dfn * 2 end
        end
      end
    end

    -- Vessel of Ruin / Beads of Ruin (Phase 8, other bucket): a real,
    -- field-wide flat -25% to every OTHER active battler's Special
    -- Attack / Special Defense (never the holder's own) -- a genuine
    -- stat multiplier, not a stage change, so applied here directly
    -- against the already-computed atk/dfn rather than through
    -- changeStage's own stage-bucket (which only ever expresses -6..+6
    -- relative deltas, not a flat scaling factor). Checked against
    -- EVERY other active battler (ally or foe, matching the real "all
    -- Pokémon other than this one" scope), applied only when the
    -- relevant stat is the one actually in play this hit (Special
    -- Attack for the attacker, Special Defense for the defender).
    -- Sword of Ruin (Defense) / Tablets of Ruin (Attack), the other two
    -- real members of this same quartet, aren't real ids in this
    -- national_dex build at all -- nothing to wire for them.
    do
      local abilityIdOf = mod.exports.abilityIdOf
      if abilityIdOf and special and atkStat == "spa" then
        for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(ctx.battle) or {}) do
          if mon and mon ~= user and abilityIdOf(mon) == "VESSELOFRUIN" then
            atk = math.floor(atk * 0.75)
            break
          end
        end
        for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(ctx.battle) or {}) do
          if mon and mon ~= target and abilityIdOf(mon) == "BEADSOFRUIN" then
            dfn = math.floor(dfn * 0.75)
            break
          end
        end
      end
    end

    -- Snow: Ice-type Defense +50% -- Gen 9's real replacement mechanic
    -- for old Hail (this project explicitly doesn't build Hail; see
    -- modern_weather.lua's header). A genuine STAT-INPUT multiplier, not
    -- a whole-damage multiplier like Sun/Rain's Fire/Water bonus above
    -- (registerDamageModifier's chain only ever scales the final `d`,
    -- confirmed by that chain's own call site further down -- it never
    -- touches atk/dfn), so it has to land here, on dfn itself, before
    -- it's used in the formula. Applies to the DEFENDER only, and only
    -- for a physical hit (defStat=="defense") -- Snow's real boost is to
    -- Defense specifically, not Sp. Def. Runs regardless of crit: a
    -- crit ignores stat STAGE changes (critIgnoresStages above), not a
    -- flat weather/ability-shaped multiplier, so this sits after both
    -- branches rather than inside either one.
    if defStat == "defense" and currentWeather(ctx.battle, gen2) == "SNOW" then
      for _, t in ipairs(curTypesOf(target, gen2)) do
        if t == "ICE" then
          dfn = math.floor(dfn * 1.5);
          break
        end
      end
    end

    if opts.explode then
      dfn = math.max(1, math.floor(dfn / 2))
    end

    -- No Gen-1 byte-clamp quirk here (the atk>255/dfn>255 quarter-both
    -- rule is a Game Boy hardware artifact, not a modern-game rule), and
    -- crit no longer doubles level. user.mon is the Gen 1 battler-
    -- wrapper's real-mon field; Gen 2's user IS the real mon already.
    local level = gen2 and user.level or user.mon.level
    -- Real per-move variable power (Heat Crash/Heavy Slam/Power Trip/
    -- Flail) substitutes here, before the formula ever multiplies by
    -- power -- see registerPowerOverride's own header for why this has
    -- to happen at THIS point rather than as a trailing multiplier. A
    -- nil override (species weight data missing, etc.) falls back to
    -- the move's own plain declared power unchanged.
    local override = powerOverrides[move.id]
    local computed = override and override({
      battle = ctx.battle, user = user, target = target, gen2 = gen2,
    })
    -- `or move.power` alone is a trap here: for a computed-power move that
    -- stored power is 0, so a formula that could not answer produced a move
    -- that did nothing at all. See FALLBACK_POWER's own header.
    -- The fallback is keyed on the OVERRIDE failing, not on the stored power
    -- being 0. Those were the same thing only while national_dex emitted 0;
    -- it now emits 1 (the base game's own placeholder for "computed at
    -- runtime"), so `power <= 0` stopped catching anything and a formula that
    -- could not answer silently left the move at power 1 -- which is not
    -- "nothing" any more, it is a Heavy Slam that tickles. Measured against a
    -- level 2 Pidgey: 986 damage at the real power 120, 10 at power 1.
    local power = computed or move.power
    if override and not computed then
      power = FALLBACK_POWER[move.id] or power
    end

    local d = math.floor(math.floor(2 * level / 5) + 2)
    d = math.floor(math.floor(d * power * atk / math.max(1, dfn)) / 50) + 2

    if crit then
      -- Sniper (Phase 8, other bucket): real 3x instead of 1.5x on the
      -- ATTACKER's own crit -- checked live, not gated by a `data[id]`
      -- table (this is a direct edit to the shared damage primitive,
      -- same pattern Contrary/Simple/Unaware above already use).
      local abilityIdOf = mod.exports.abilityIdOf
      local critMult = (abilityIdOf and abilityIdOf(user) == "SNIPER") and 3.0 or 1.5
      d = math.floor(d * critMult)
    end

    -- Random factor applied BEFORE the modifier chain/type effectiveness
    -- (real Gen 6+ order), not after like Gen 1.
    if not opts.typeless then
      d = math.floor(d * (100 - rng(0, 15)) / 100)
    end

    local mult = 10
    if not opts.typeless then
      for _, entry in ipairs(damageModifiers) do
        local m = entry.fn({
          battle = ctx.battle, user = user, target = target, move = move,
          category = category, atkStat = atkStat, defStat = defStat, crit = crit,
          gen2 = gen2, opts = opts,
        }) or 1.0
        if m ~= 1.0 then
          d = math.floor(d * m)
        end
      end

      -- resolvedTypeMult (this file's own header, just above curTypesOf)
      -- folds in Tera-Stellar's defensive override AND the real
      -- Foresight/Miracle Eye/Smack Down/Scrappy/Mind's Eye immunity
      -- negation / Telekinesis immunity grant -- all resolved against
      -- the real defender TYPE LIST before either the aggregate
      -- multiplier or the real per-row TypeChart.rows() scaling below
      -- ever runs, replacing what used to be a raw, negation-blind
      -- TypeChart.effectiveness(...) call here.
      local targetTypes
      mult, targetTypes = resolvedTypeMult(ctx.battle, user, target, gen2, move.type)
      if mult == 0 then
        return 0, { crit = false, typeMult = 0 }
      end
      -- Delta Stream's own field state (abilities/engine/
      -- switchin_primal_weather.lua): caps a would-be-super-effective hit
      -- against a Flying-type defender down to neutral. Computed here,
      -- once the real aggregate `mult` is already known, rather than as
      -- another registerDamageModifier entry above -- every one of those
      -- runs BEFORE `mult` exists at all, so none of them can express
      -- "replace the type multiplier," only "multiply an extra factor
      -- into `d`." A nil return (every non-Delta-Stream battle; a hit
      -- that isn't super effective in the first place) means "no
      -- override," and the real per-type rows below still run unchanged.
      local overrideMult = mod.exports.effectivenessOverrideFor
        and mod.exports.effectivenessOverrideFor(ctx.battle, target, gen2, move.type, mult)
      if overrideMult and overrideMult ~= mult then
        mult = overrideMult
        if mult ~= 1.0 then
          d = math.floor(d * mult)
        end
      else
        for _, m in ipairs(TypeChart.rows(move.type, targetTypes)) do
          d = math.floor(d * m / 10)
        end
      end
      -- Stellar's own "always weak to Stellar moves" rule: an additional
      -- x2, not a chart row (Stellar deliberately carries none) -- fires
      -- only when the incoming move is Stellar-typed AND the target is
      -- itself Stellar-Terastallized, regardless of what its real types
      -- do or don't resist.
      if mod.exports.stellarWeaknessMultiplier then
        local extra = mod.exports.stellarWeaknessMultiplier(ctx.battle, target, gen2, move.type)
        if extra and extra ~= 1.0 then
          d = math.floor(d * extra)
          mult = math.floor(mult * extra)
        end
      end
      -- Phase 2's own effectiveness-tier abilities -- see
      -- registerPostEffectivenessModifier's own header just above its
      -- definition for why this can't live in the ordinary
      -- registerDamageModifier chain.
      for _, entry in ipairs(postEffectivenessModifiers) do
        local m = entry.fn({
          battle = ctx.battle, user = user, target = target, move = move,
          category = category, mult = mult, gen2 = gen2,
        }) or 1.0
        if m ~= 1.0 then d = math.floor(d * m) end
      end
    end

    -- No "rounds to 0 counts as a miss" Gen-1 quirk -- modern games
    -- always clamp to a minimum of 1.
    return math.max(1, d), { crit = crit, typeMult = mult }
  end

  ------------------------------------------------------------------
  -- Stage-store lifecycle: reset when a new mon becomes active (covers
  -- every voluntary/forced switch and faint-replacement via
  -- battle.battler_switched -- confirmed fired for all of those, both
  -- generations, same event/payload shape), and free the whole table
  -- when the battle ends. The very first send-out at battle start does
  -- NOT emit battle.battler_switched (confirmed: only makeBattler runs
  -- there on Gen 1, no matching emit site) -- harmless, since a brand
  -- new `battle` object is never a stale key to begin with; the
  -- battle.started reset below is just cheap defensive symmetry with
  -- gimmick_dynamax.lua's own battle.started reset, not load-bearing.
  ------------------------------------------------------------------
  mod.events:on("battle.started", function(ev)
    if ev and ev.battle then stageState[ev.battle] = nil end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    if not battle or not ev.battler then return end
    local side = sideOfWho(battle, ev.battler, isGen2Battle(battle))
    ensureStageState(battle)[side] = {}
  end)
  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle then stageState[ev.battle] = nil end
  end)

  ------------------------------------------------------------------
  -- Part B Phase 5: shared "damagedThisTurn" flag -- Assurance (Tier 1)
  -- and Focus Punch (Tier 2) both need "did this battler take real
  -- battle damage this turn", which nothing native tracks. Direct field
  -- on the battler/mon itself, same convention as the engine's own
  -- user.flinched/user.thrashTurns -- set on battle.damage_dealt
  -- (confirmed real event, fires post-computation with the actual dealt
  -- amount: EffectRegistry.lua:286 Gen 1, gen2/Battle.lua:1242 Gen 2,
  -- identical payload shape both), cleared on battle.turn_started
  -- (confirmed real, fires both generations: BattleState.lua:2410,
  -- gen2/Battle.lua:4069) rather than turn_ended, so a status/hazard
  -- tick landing between turn_ended and the next turn's move selection
  -- doesn't leak a stale flag into that next turn's Focus Punch check.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    if ev and ev.target and (ev.damage or 0) > 0 then
      ev.target.damagedThisTurn = true
    end
  end)
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, b in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if b then b.damagedThisTurn = false end
    end
  end)

  ------------------------------------------------------------------
  -- Hook wiring. Explicit user decision: this formula is the only
  -- damage path, unconditionally, for every battle regardless of
  -- generation -- no options toggle, no silent pcall-to-vanilla
  -- fallback on error (removed; formerly `modern_combat_formulas`).
  -- `next` is still accepted (the battle.damage hook contract requires
  -- it) but is never called.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    return computeModernDamage(ctx)
  end, 0)

  mod.log:info("galar_gmax_dex: modern_combat loaded")
end
