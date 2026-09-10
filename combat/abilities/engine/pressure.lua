-- Dispatch engine for abilities/data/pressure.lua -- Phase 8 of the
-- ability roadmap.
--
-- Neither engine has PP deduction as its own standalone, named method --
-- it is one inline statement deep inside a much larger function on both
-- sides (`move.pp = (move.pp or 1) - 1` inside Gen 2's own
-- Battle:useMove; `moveInst.pp = math.max(0, moveInst.pp - 1)` inside Gen
-- 1's own BattleState:performMove), each already guarded by real
-- exclusion conditions (charging/rampaging/rolling/biding/called on Gen
-- 2; continuation/struggle/called/enemyUnlimitedPP on Gen 1) this file
-- has no reason to duplicate. Both are wrapped at their real, whole-
-- function level (the same real choke points this mod's own Electro
-- Shot Gen 1 charge fix and Prankster/Embargo/rampage-lock Gen 2 fixes
-- already prove safe) with a plain BEFORE/AFTER read of the move's own
-- `.pp` field -- if it dropped by exactly 1 (meaning the native
-- deduction branch actually ran this attempt, whatever its own reason),
-- Pressure deducts one more. This observes the real outcome rather than
-- re-implementing the native exclusion logic a second time, so it can
-- never drift out of sync with either engine's own real rules for when
-- PP is and isn't spent.
return function(mod, data)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "pressure: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local abilityIdOf = mod.exports.abilityIdOf
  assert(abilityIdOf, "pressure: ability_dispatch.lua must load first")

  -- Real target archetypes Pressure's extra PP applies to -- excludes
  -- "user"/"users-field" (the holder's own self/side-targeted moves are
  -- explicitly unaffected, confirmed via national_dex's own notes).
  local PRESSURE_TARGETS = {
    ["selected-pokemon"] = true, ["all-opponents"] = true,
    ["opponents-field"] = true, ["all-other-pokemon"] = true,
  }
  local function targetsOpponent(moveId)
    local info = moveById(moveId)
    return info ~= nil and PRESSURE_TARGETS[info.target] == true
  end

  local Battle = require("src.battle.gen2.Battle")
  local nativeUseMovePressure = Battle.useMove
  function Battle:useMove(attacker, defender, moveId)
    local move = attacker and self:findMove(attacker, moveId)
    local ppBefore = move and move.pp
    local result = nativeUseMovePressure(self, attacker, defender, moveId)
    if move and ppBefore and defender and defender ~= attacker and data.PRESSURE
        and abilityIdOf(defender) == "PRESSURE"
        and (move.pp or 0) == ppBefore - 1 and targetsOpponent(moveId) then
      move.pp = math.max(0, move.pp - 1)
    end
    return result
  end

  local BattleState = require("src.battle.BattleState")
  local nativePerformMovePressure = BattleState.performMove
  function BattleState:performMove(user, target, moveInst, isCalled)
    local ppBefore = moveInst and moveInst.pp
    local result = nativePerformMovePressure(self, user, target, moveInst, isCalled)
    if moveInst and ppBefore and target and target ~= user and data.PRESSURE
        and abilityIdOf(target) == "PRESSURE"
        and (moveInst.pp or 0) == ppBefore - 1 and targetsOpponent(moveInst.id) then
      moveInst.pp = math.max(0, moveInst.pp - 1)
    end
    return result
  end

  mod.log:info("g9-battle-engine-beta: pressure installed (PRESSURE, both engines)")
end
