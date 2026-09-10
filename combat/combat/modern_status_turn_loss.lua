-- Real ownership of the paralysis/sleep/freeze turn-loss DECISION,
-- replacing native cartridge-accurate logic with real, current Showdown
-- mechanics -- verified directly against Pokemon Showdown's own real
-- source (data/conditions.ts) before writing any of this, not from
-- memory. Standing project principle (turn_order.lua's own header: "we
-- are the bible and process of combat" -- extended here to status-based
-- turn loss, not just move ordering): the native engine only executes a
-- decision this mod hands it, it never independently decides an outcome
-- via its own RNG. Confirmed BEFORE this file existed that the ported
-- native logic violated this twice over -- not just in ownership, but in
-- accuracy:
--   PARALYSIS: native rolls 63/256 (~24.6%, Gen 1's own byte-based
--     approximation) -- real current rate is exactly 25% (Showdown's own
--     `this.randomChance(1, 4)`).
--   SLEEP: native duration is `rng(1,7)` (Gen 1's own cartridge range)
--     -- real current duration is 1-3 turns lost, uniform (Showdown's
--     own `this.random(2, 5)`, pre-decremented before the first check).
--     Native ALSO always returns "lose the turn" even on the exact turn
--     the mon wakes up -- real current rule lets a mon act immediately
--     on the turn it wakes (Showdown's own bare `return;` -- no value --
--     on the woken branch, vs an explicit `return false` for "still
--     asleep").
--   FREEZE: Gen 1's ported native has NO thaw roll AT ALL (`beforeMove`
--     unconditionally returns "still frozen," confirmed by direct read)
--     -- a Gen 1 battle's frozen mon never thaws on its own under the
--     pre-existing code. Gen 2's own native DOES roll (`Battle
--     .THAW_CHANCE`) but at Gen 2's own cartridge rate, not real current
--     Showdown's exactly 20% (`this.randomChance(1, 5)`).
--
-- Monkeypatches each status's own `beforeMove` (and Sleep's own
-- `onInflict`, for the duration roll) directly -- Gen 1's `Status
-- .RECORDS.PAR/SLP/FRZ`, Gen 2's `Battle.STATUSES.paralyze/sleep/
-- freeze` -- the same surgical, per-status-record pattern already
-- proven safe for Poison Heal/Heatproof/Magic Guard's own residual
-- patches. Each replacement keeps the EXACT return contract the engine
-- already consumes (Gen 1: `(canAct, msgs)`; Gen 2: `canAct` plus its
-- own `battle:emit` calls) -- the engine still just executes a decision
-- handed to it, only the decision itself is now ours.
--
-- Early Bird (abilities/data/*.lua's own Phase 8 deferral list named
-- this as unbuilt) is closed here for free, since it's the exact same
-- code path: real rule (Showdown's own `if (pokemon.hasAbility
-- ('earlybird')) { pokemon.statusState.time--; }`) is a SECOND
-- decrement per turn, halving effective sleep duration.
--
-- Sleep Talk/Snore (real moves usable while asleep, Showdown's own
-- `move.sleepUsable` flag) -- national_dex's own moveFlags has no
-- equivalent flag (confirmed, grepped flags.lua directly), so this is a
-- small, real, necessary hardcoded pair -- the same class of thing
-- CRASH_DAMAGE_MOVES/ROOM_MOVE_FLAG already are, not a violation of the
-- "read live, don't hardcode" discipline (there is nothing to read).
return function(mod)
  local abilityIdOf = mod.exports.abilityIdOf

  local function percentRoll(gen2, battle, chance)
    if gen2 then return battle.random(100) < chance end
    return battle.rng(1, 100) <= chance
  end
  local function rangeRoll(gen2, battle, lo, hi)
    if gen2 then return lo + battle.random(hi - lo + 1) end
    return battle.rng(lo, hi)
  end

  local SLEEP_USABLE_MOVES = { SLEEPTALK = true, SNORE = true }

  ------------------------------------------------------------------
  -- Gen 1
  ------------------------------------------------------------------
  local Status = require("src.battle.Status")

  Status.RECORDS.PAR.beforeMove = function(battler, rng, battle)
    local romText = require("src.core.RomText")
    if percentRoll(false, battle, 25) then
      return false, { romText(battle and battle.data, "_FullyParalyzedText",
        "%s's\nfully paralyzed!", battler.name) }
    end
    return true, {}
  end

  Status.RECORDS.SLP.onInflict = function(battle, target, opts, display)
    target.sleepTurns = rangeRoll(false, battle, 1, 3)
    local romText = require("src.core.RomText")
    return { romText(battle.data, "_FellAsleepText", "%s\nfell asleep!", display) }
  end
  Status.RECORDS.SLP.beforeMove = function(battler, rng, battle)
    local romText = require("src.core.RomText")
    local dec = (abilityIdOf and abilityIdOf(battler) == "EARLYBIRD") and 2 or 1
    battler.sleepTurns = (battler.sleepTurns or 1) - dec
    if battler.sleepTurns <= 0 then
      battler.mon.status = nil
      battler.sleepTurns = nil
      return true, { romText(battle and battle.data, "_WokeUpText", "%s\nwoke up!", battler.name) }
    end
    return false, { romText(battle and battle.data, "_FastAsleepText", "%s\nis fast asleep!", battler.name) }
  end

  Status.RECORDS.FRZ.beforeMove = function(battler, rng, battle)
    local romText = require("src.core.RomText")
    if percentRoll(false, battle, 20) then
      battler.mon.status = nil
      return true, { romText(battle and battle.data, "_ThawedOutText", "%s\nthawed out!", battler.name) }
    end
    return false, { romText(battle and battle.data, "_IsFrozenText", "%s\nis frozen solid!", battler.name) }
  end

  ------------------------------------------------------------------
  -- Gen 2
  ------------------------------------------------------------------
  local Battle = require("src.battle.gen2.Battle")

  Battle.STATUSES.paralyze.beforeMove = function(battle, mon, name)
    if percentRoll(true, battle, 25) then
      battle:emit({ kind = "message", text = name .. "'s fully paralyzed!" })
      return false
    end
    return true
  end

  Battle.STATUSES.sleep.onInflict = function(battle, mon)
    mon.statusTurns = rangeRoll(true, battle, 1, 3)
  end
  Battle.STATUSES.sleep.beforeMove = function(battle, mon, name)
    local dec = (abilityIdOf and abilityIdOf(mon) == "EARLYBIRD") and 2 or 1
    mon.statusTurns = (mon.statusTurns or 1) - dec
    if mon.statusTurns <= 0 then
      mon.status = nil
      mon.statusTurns = nil
      battle:emit({ kind = "message", text = name .. " woke up!" })
      return true
    end
    battle:emit({ kind = "message", text = name .. " is fast asleep!" })
    return false
  end

  Battle.STATUSES.freeze.beforeMove = function(battle, mon, name)
    if percentRoll(true, battle, 20) then
      mon.status = nil
      battle:emit({ kind = "message", text = name .. " thawed out!" })
      return true
    end
    battle:emit({ kind = "message", text = name .. " is frozen solid!" })
    return false
  end

  mod.log:info("g9-battle-engine-beta: modern_status_turn_loss installed (real Gen 9 paralysis 25%%/sleep 1-3 turns/freeze 20%% thaw, both engines, Early Bird wired)")
end
