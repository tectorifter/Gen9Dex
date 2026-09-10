-- The ability-execution primitive: this mod's first real integration of
-- national_dex's ability DATA (dex.exports.abilityById, 0.30.0+) into
-- actual battle behavior. Nothing before this session executed an ability
-- anywhere in this engine -- confirmed directly (a dedicated research pass
-- grepped the whole base engine and every installed mod): mon.ability
-- exists only as save/display data (stats/engine_modern_stats.lua's own
-- generation/toggle functions, the SummaryMenu page-3 readout), never read
-- by combat logic.
--
-- We do not register abilities -- national_dex already owns the species-
-- ability associations (statsBySpecies(id).abilities) and the ability
-- behavior text (abilityById(id)) -- we only WIRE what's already there
-- into the primitives this mod already has (changeStage, setMonTypes,
-- etc.), the exact same "patch, never register" discipline this mod's own
-- SUBEFFECTS.md already states for moves.
--
-- MODULARITY, explicit user directive: data and engine stay entirely
-- separate for the whole ability system, this file included. abilities/
-- data/*.lua files are pure tables (no logic, no mod.exports -- loaded via
-- loadSibling the same way combat/moves_new.lua's own plain data table
-- already is) keyed by ability id; abilities/engine/*.lua files are pure
-- dispatch logic, each reading exactly one data file and calling exactly
-- one existing primitive. This file is the one exception living outside
-- that split -- it IS the primitive every engine file depends on
-- (abilityIdOf/abilityBehaviorOf), not a per-ability dispatcher itself.
return function(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.abilityById,
    "ability_dispatch: national_dex (with abilityById) must be installed")

  -- Neutralizing Gas (Phase 8, other bucket): a real, global "no other
  -- Pokémon's ability functions while this one is active" field effect.
  -- Built HERE, directly inside abilityIdOf's own real definition --
  -- this file's own header already declares itself the one exception
  -- living outside the data/engine split, the single real choke point
  -- every ability check in this whole mod goes through. A wrap
  -- installed by a LATER-loading engine file was tried and rejected:
  -- every existing engine file captures `local abilityIdOf =
  -- mod.exports.abilityIdOf` ONCE, at its own install time -- a later
  -- reassignment of mod.exports.abilityIdOf would never reach any of
  -- those already-captured locals, a confirmed dead end for a
  -- suppression effect that has to be globally visible.
  --
  -- Self-contained by necessity: this function must keep working
  -- correctly from the moment it's first exported, long before
  -- move_targeting.lua's own allActiveBattlers exists -- so the field-
  -- wide holder scan below is a lazy mod.exports lookup, and "which
  -- battle is this" is tracked locally via battle.started/battle.ended
  -- rather than threaded in as a parameter (abilityIdOf's own real
  -- signature, called from dozens of sites across this mod, is
  -- mon-only -- adding a battle parameter would mean touching every one
  -- of those call sites instead of the one real source).
  --
  -- Real, confirmed exemptions checked here: the holder's own
  -- Neutralizing Gas is always active for itself; Comatose and Disguise
  -- (both real, built abilities in this mod) are real Showdown
  -- exemptions too. Every OTHER real exemption (Multitype, Stance
  -- Change, Schooling, Shields Down, RKS System, Battle Bond, Power
  -- Construct, Ice Face, Zen Mode, As One, Gulp Missile) is a form-
  -- changing or single-species ability this mod doesn't build at all
  -- (battle_forms' own standing scope) -- moot here, not omitted.
  local NGAS_EXEMPT = { NEUTRALIZINGGAS = true, COMATOSE = true, DISGUISE = true }
  local ngasBattle = nil
  mod.events:on("battle.started", function(ev) ngasBattle = ev and ev.battle end)
  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle == ngasBattle then ngasBattle = nil end
  end)
  local function rawAbilityId(name)
    if type(name) ~= "string" then return nil end
    local id = name:upper():gsub("[^%w]", "")
    return id ~= "" and id or nil
  end
  local function neutralizingGasActive()
    if not ngasBattle then return false end
    local allActiveBattlers = mod.exports.allActiveBattlers
    if not allActiveBattlers then return false end
    for _, other in ipairs(allActiveBattlers(ngasBattle) or {}) do
      if other and (other.hp or 0) > 0 and rawAbilityId(other.ability) == "NEUTRALIZINGGAS" then
        return true
      end
    end
    return false
  end

  -- mon.ability stores a display name ("Intimidate", "As One (Glastrier)");
  -- national_dex's own ids strip everything but letters/digits and
  -- uppercase (confirmed directly against real records: "As One
  -- (Glastrier)" -> ASONEGLASTRIER, "Dauntless Shield" -> DAUNTLESSSHIELD).
  local function abilityIdOf(mon)
    local id = rawAbilityId(mon and mon.ability)
    if not id then return nil end
    if not NGAS_EXEMPT[id] and neutralizingGasActive() then return nil end
    return id
  end
  mod.exports.abilityIdOf = abilityIdOf

  -- The real national_dex behavior record for mon's current ability, or
  -- nil (no ability set, or national_dex has no record for it). A COPY,
  -- like every other national_dex reply -- callers may read but should
  -- never assume mutating it does anything.
  function mod.exports.abilityBehaviorOf(mon)
    local id = abilityIdOf(mon)
    if not id then return nil end
    return nationalDex.exports.abilityById(id)
  end

  ------------------------------------------------------------------
  -- setAbility: the real "no mechanism exists to change a mon's own
  -- ability" gap this whole ability system's own standing TODO named
  -- (Skill Swap/Worry Seed/Entrainment/Gastro Acid as moves; Trace/Mummy/
  -- Wandering Spirit/Receiver/Power of Alchemy as abilities) -- closed
  -- directly rather than re-deferred: abilityIdOf/abilityBehaviorOf both
  -- already re-derive from `mon.ability` LIVE, on every call, and
  -- stats/engine_modern_stats.lua's own real Ability Capsule-equivalent
  -- (ModernStats.toggleHiddenAbility/toggleRegularAbility) already proves
  -- writing a real national_dex display name straight into `mon.ability`
  -- is exactly how this engine expects an ability change to be made --
  -- there was never a missing primitive, only a missing generic entry
  -- point covering an ARBITRARY new ability id (not just the two a
  -- species already knows), which is all this adds.
  --
  -- COMBAT-ONLY STATE, explicit user instruction: every real use of this
  -- (moves and abilities alike) is a battle effect, never a permanent
  -- change -- the mon's own natural (pre-battle) ability is captured into
  -- `mon.naturalAbility` the FIRST time this mon is ever changed this
  -- battle, and restored from there on `battle.battler_switched` (both
  -- the mon leaving AND whichever mon is newly sent out, same dual-clear
  -- shape Stockpile's own switch cleanup already uses) and on
  -- `battle.ended` (covers the still-active mon on either side when the
  -- battle itself just stops, the one case switching out never fires
  -- for). `naturalAbilityCaptured` is a separate boolean guard, not just
  -- `naturalAbility ~= nil`, so a mon with genuinely NO natural ability
  -- restores correctly to "no ability" instead of being treated as
  -- never-captured forever.
  --
  -- BOSS IMMUNITY, explicit user instruction: gated on the SAME
  -- `bossFightHas(battle, "ability")` flag combat/boss_fight.lua already
  -- reserved and documented as "NOT YET ENFORCED ANYWHERE... there is
  -- nothing in this codebase today that would try to change a boss's
  -- ability" -- that flag already existed for exactly this, so this is
  -- wiring the existing reserved gate, not adding a new one.
  mod.exports.setAbility = function(battle, mon, newId)
    if not mon then return false end
    -- Real N-way check (2026-08-28): any enemy-side battler protected,
    -- not just the literal battle.enemy object -- same generalization
    -- combat/boss_fight_status.lua's own fix uses.
    if battle and mod.exports.bossFightHas and mod.exports.bossFightHas(battle, "ability")
        and battle:sideOf(mon) == "enemy" then
      return false
    end
    if not mon.naturalAbilityCaptured then
      mon.naturalAbility = mon.ability
      mon.naturalAbilityCaptured = true
    end
    if newId == nil then
      mon.ability = nil -- Gastro Acid-style suppression: the ability slot goes inert, not swapped
      return nil
    end
    local record = nationalDex.exports.abilityById(newId)
    if not (record and type(record.name) == "string" and record.name ~= "") then return false end
    mon.ability = record.name
    return newId
  end

  local function restoreNaturalAbility(mon)
    if mon and mon.naturalAbilityCaptured then
      mon.ability = mon.naturalAbility
      mon.naturalAbility = nil
      mon.naturalAbilityCaptured = nil
    end
  end
  mod.exports.restoreNaturalAbility = restoreNaturalAbility

  mod.events:on("battle.battler_switched", function(ev)
    if ev then
      restoreNaturalAbility(ev.previous)
      restoreNaturalAbility(ev.battler)
    end
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    restoreNaturalAbility(battle.player)
    restoreNaturalAbility(battle.enemy)
  end)

  mod.log:info("g9-battle-engine-beta: ability_dispatch installed (abilityIdOf, abilityBehaviorOf, setAbility, boss-immune + combat-only)")
end
