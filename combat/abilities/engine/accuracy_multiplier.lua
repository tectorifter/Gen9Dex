-- Dispatch engine for abilities/data/accuracy_multiplier.lua -- Phase 6c
-- of the ability roadmap. Factors are read LIVE from national_dex's own
-- abilityBehaviorOf.
--
-- NEW PRIMITIVE: no accuracy-modifier chain existed anywhere in this mod
-- before this file. Built on `Battle:accuracyRoll`'s own real
-- `"battle.accuracy"` hook (gen2/Battle.lua, confirmed the SAME hook
-- name Gen 1's BattleState:accuracyRoll calls too, same ctx shape both
-- engines) -- the exact real extension point this engine already ships
-- for exactly this purpose, not a new hook invented for this file.
-- registerAccuracyModifier below mirrors combat/modern_combat.lua's own
-- registerDamageModifier shape (id, priority, fn(ctx)->multiplier),
-- installed here since this is the one file that needs it -- a future
-- Phase 6/7/8 ability needing accuracy too should reuse this export
-- rather than wrapping the hook a second time.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "accuracy_multiplier: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  local abilityBehaviorOf = mod.exports.abilityBehaviorOf
  local requestAdjacency = mod.exports.requestAdjacency
  assert(abilityIdOf and abilityBehaviorOf and requestAdjacency,
    "accuracy_multiplier: ability_dispatch.lua and move_targeting.lua must load first")

  local accuracyModifiers = {} -- { {id=, priority=, fn=fn(ctx)->multiplier}, ... }
  local function registerAccuracyModifier(id, priority, fn)
    assert(type(id) == "string" and id ~= "", "accuracy modifier id is required")
    assert(type(fn) == "function", "accuracy modifier must be a function")
    for i, entry in ipairs(accuracyModifiers) do
      if entry.id == id then table.remove(accuracyModifiers, i) break end
    end
    table.insert(accuracyModifiers, { id = id, priority = priority or 0, fn = fn })
    table.sort(accuracyModifiers, function(a, b) return a.priority > b.priority end)
  end
  mod.exports.registerAccuracyModifier = registerAccuracyModifier

  -- factorFor(mon, id) -- the live accuracy_multiplier effect's own
  -- `factor` for this ability, or nil.
  local function factorFor(mon)
    local id = abilityIdOf(mon)
    if not (id and data[id]) then return nil, nil end
    local record = abilityBehaviorOf(mon)
    for _, eff in ipairs(record and record.behaviour and record.behaviour.effects or {}) do
      if eff.kind == "accuracy_multiplier" and eff.factor then return eff.factor, id end
    end
    return nil, nil
  end

  registerAccuracyModifier("compoundeyes", 0, function(ctx)
    local factor, id = factorFor(ctx.user)
    if id == "COMPOUNDEYES" then return factor end
    return 1.0
  end)

  registerAccuracyModifier("hustle_accuracy", 0, function(ctx)
    local factor, id = factorFor(ctx.user)
    if id ~= "HUSTLE" then return 1.0 end
    local info = ctx.moveId and moveById(ctx.moveId)
    if info and info.damageClass == "physical" then return factor end
    return 1.0
  end)

  -- Victory Star: self-inclusive ally scope, confirmed via its own
  -- notes ("Applies to this Pokémon's own moves as well as its
  -- allies'") -- checks the attacker itself first (the common case in
  -- today's 2-battler engine, where requestAdjacency's own allies list
  -- is always empty), then any real adjacent ally.
  registerAccuracyModifier("victorystar", 0, function(ctx)
    local factor, id = factorFor(ctx.user)
    if id == "VICTORYSTAR" then return factor end
    for _, ally in ipairs(requestAdjacency(ctx.battle, ctx.user, nil).allies) do
      local allyFactor, allyId = factorFor(ally)
      if allyId == "VICTORYSTAR" then return allyFactor end
    end
    return 1.0
  end)

  mod.hooks:wrap("battle.accuracy", function(nextFn, ctx)
    -- No Guard (Phase 8, "other" bucket): a real, unconditional
    -- guaranteed hit, not a multiplier -- accuracy AND evasion stages
    -- are both bypassed entirely (confirmed real: "moves used by this
    -- Pokémon, and moves used against it, never miss"), which is a
    -- different shape than anything registerAccuracyModifier can express
    -- (that chain only ever scales ctx.accuracy before the real roll;
    -- No Guard skips the roll outright). Checked first, either side --
    -- returns true directly rather than calling nextFn, matching
    -- Battle:vanillaAccuracyRoll's own real return contract (a plain hit
    -- boolean).
    if (ctx.user and abilityIdOf(ctx.user) == "NOGUARD")
        or (ctx.target and abilityIdOf(ctx.target) == "NOGUARD") then
      return true
    end
    local total = 1.0
    for _, entry in ipairs(accuracyModifiers) do
      total = total * (entry.fn(ctx) or 1.0)
    end
    if total ~= 1.0 then
      ctx.accuracy = math.floor((ctx.accuracy or 0) * total + 0.5)
    end
    return nextFn(ctx)
  end, 0)

  mod.log:info("g9-battle-engine-beta: accuracy_multiplier installed (COMPOUNDEYES, HUSTLE, VICTORYSTAR)")
end
