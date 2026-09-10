-- Dispatch engine for abilities/data/parental_bond.lua -- see that
-- file's own header for the real mechanic and the ownership correction
-- behind why this is buildable at all.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "parental_bond: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "parental_bond: ability_dispatch.lua must load first")

  -- Real, confirmed exemptions (see this file's own data header) --
  -- same OHKO id list every other phase this session already uses.
  local OHKO_MOVES = { FISSURE = true, GUILLOTINE = true, HORNDRILL = true, SHEERCOLD = true }

  local function eligibleMove(moveId)
    local ok, info = pcall(moveById, moveId)
    if not (ok and info) then return false end
    if info.damageClass == "status" then return false end
    if (info.power or 0) <= 0 then return false end -- excludes fixed-damage moves (Seismic Toss family) for free
    if (info.maxHits or 0) > 0 then return false end -- already a multi-hit move
    if OHKO_MOVES[info.id or info.strippedId] then return false end
    return true
  end

  local function hpOf(m) local r = m and (m.mon or m); return r and (r.hp or 0) or 0 end

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move = ctx.move
    local user = ctx.user
    if not (data.PARENTALBOND and move and move.id and user and abilityIdOf(user) == "PARENTALBOND"
        and eligibleMove(move.id)) then
      return next(ctx)
    end

    -- Hit 1: the real, full-power hit, exactly as it would resolve
    -- without this ability at all.
    local dmg1, info1 = next(ctx)
    dmg1 = dmg1 or 0

    -- OWNERSHIP: we read the target's own CURRENT hp directly (the
    -- same primitive this mod's own damage-application helpers already
    -- use everywhere else) to decide, ourselves, whether hit 1 alone
    -- would have knocked the target out -- no dependency on the native
    -- caller having already subtracted anything.
    local hpBefore = hpOf(ctx.target)
    if hpBefore > 0 and dmg1 >= hpBefore then
      return dmg1, info1 -- real rule: the first hit fainted the target, no second hit
    end

    -- Hit 2: real 25% power, its own independent pass through the
    -- WHOLE downstream chain (type conversion, STAB, crit roll, type
    -- effectiveness, Protect -- everything below this wrap's own
    -- priority) -- achieved by temporarily scaling the shared move
    -- object's own `.power` field and restoring it immediately after
    -- (even on error), the same swap-and-restore idiom
    -- type_override_moves.lua's own header already established this
    -- same phase.
    local origPower = move.power
    move.power = math.max(1, math.floor((origPower or 0) * 0.25))
    local ok, dmg2, info2 = pcall(next, ctx)
    move.power = origPower
    if not ok then
      mod.log:warn("g9-battle-engine-beta: parental_bond second hit failed: %s", tostring(dmg2))
      return dmg1, info1
    end
    dmg2 = dmg2 or 0

    -- Combined into ONE number/info pair -- this engine's own
    -- battle.damage contract returns exactly one of each per call, so
    -- two mechanically separate hits (real Showdown shows two distinct
    -- animations/messages, and each independently rolls its own
    -- secondary-effect chance) collapse to one combined total and one
    -- combined battle.damage_dealt firing here -- a real, honest
    -- simplification: the AGGREGATE damage is correct, the per-hit
    -- granularity (two messages, two independent secondary-effect
    -- rolls) is not reproduced.
    return dmg1 + dmg2, info1
  end, 210)

  mod.log:info("g9-battle-engine-beta: parental_bond installed (PARENTALBOND)")
end
