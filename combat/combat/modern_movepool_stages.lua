-- Phase 1 of the move-effect completion pipeline: wires moves_new.lua's
-- ~60 stat-stage-change stubs (effect="NO_ADDITIONAL_EFFECT" but a
-- functionCode naming a real Raise/Lower/Reset mechanic) to real,
-- Showdown-checked behavior. Split out of modern_combat.lua (whose own
-- header scopes it to "the modern damage formula") rather than grown
-- into it -- ~56 registrations is its own coherent unit, and this file
-- reuses modern_combat.lua's own primitives rather than duplicating them.
--
-- Two storages, on purpose:
--   atk/def/spa/spd: modern_combat.lua's OWN store (mod.exports.
--   changeStage) -- required, not a style choice, because
--   computeModernDamage reads stats out of that exact store and nothing
--   else; writing anywhere else would be silently invisible to damage.
--   speed/accuracy/evasion: modern_combat.lua's store never held these
--   (its own header says so) and computeModernDamage never reads them,
--   so the only storage that's actually CONSULTED by anything is each
--   engine's own native one: Gen 1's who.stages (confirmed read
--   directly by Damage.lua:63,98,100 and TurnOrder.lua:14 for speed/
--   accuracy/evasion/damage-adjacent checks) and Gen 2's
--   self.stages[side] (confirmed read by gen2/Battle.lua's own
--   vanillaAccuracyRoll:2023-2024). changeNativeStage below writes
--   straight to those real primitives -- src.battle.MoveEffects.
--   changeStage for Gen 1, Battle:changeStageAgainstMist for Gen 2 (both
--   pre-existing, already used by the native SPEED_UP2_EFFECT-family
--   ids) -- not a new parallel mechanism.
--
-- Gen 2 message caveat: a move_effects run() handler's RETURN VALUE is
-- never read on Gen 2 (gen2/Battle.lua:1533-1538 calls handler(...) and
-- discards it) -- only battle:emit() calls inside the handler reach the
-- player. Battle:changeStageAgainstMist emits its own real message, so
-- native-routed changes show up fine; store-routed ones (changeStage,
-- above) don't print anything on Gen 2 today -- a pre-existing gap
-- already true of GMAX_AMNESIA_EFFECT/GMAX_GROWTH_EFFECT, not something
-- this file introduces or is trying to fix.
--
-- STALE, CONFIRMED WRONG (2026-08-28, direct user report -- "liquidation
-- move is dealing no damage" -- see the `secondary()` function's own
-- header further down for the full correction): this used to claim
-- damaging-move secondary effects were safe as long as they gen2-guarded
-- (`if n.gen2 then return {} end`) INSIDE run(). They are not -- Gen 2's
-- dispatch calls ANY move_effects record with a .run field BEFORE the
-- damage path and returns immediately once it does, true regardless of
-- what the handler's body does, so that internal guard never had a
-- chance to matter -- Gen 2 had already skipped its own damage
-- computation by the time it ran. Every damaging move ever registered
-- through `secondary()` (29 real moves, not a hypothetical) dealt ZERO
-- damage on Gen 2 until this same pass fixed it by moving off kind=
-- "secondary" entirely. Pure status moves (power == 0, the `primary()`
-- function) were never affected -- there's no damage to pre-empt.
--
-- Chance-based secondaries use the engine's own 0-255 roll convention
-- (already established by native's statDownSide, MoveEffects.lua:136,
-- "33 percent + 1 (85/256)") -- rng(0,255) < N/256, rounded to the
-- nearest integer: 10% -> 26, 20% -> 51, 50% -> 128.
--
-- Left alone, explicitly, NOT guessed at:
--   CURSE (ghost-type-conditional: curses target with recurring damage
--     for a Ghost-type user, HP cost and all, vs. +1 Atk/+1 Def/-1 Spd
--     self otherwise -- a whole new curse-volatile mechanic, not a pure
--     stat change).
--   STOCKPILE (a new stack-counter mechanic Swallow/Spit Up read, not
--     just +1 Def/+1 SpDef).
--   BELLYDRUM (sets Attack straight to +6 at a fixed HP cost with its
--     own fail condition -- Phase 2 territory, recoil/drain/heal-shaped,
--     not a plain delta).
--   FLATTER, SWAGGER (raise a stat AND confuse the target in the same
--     breath -- confusion infliction is Phase 2's "status infliction"
--     bucket; wiring only the stat half would misreport these as fully
--     implemented when half their real effect is still missing).
return function(mod)
  local NativeMoveEffects = require("src.battle.MoveEffects")
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  local changeStage = mod.exports.changeStage
  local normalize = mod.exports.normalize
  local resetStages = mod.exports.resetStages
  local bossStatsDropBlocked = mod.exports.bossStatsDropBlocked
  local isGen2Battle = mod.exports.isGen2Battle
  assert(changeStage and normalize and resetStages and bossStatsDropBlocked and isGen2Battle,
    "modern_movepool_stages: combat/modern_combat.lua must load first")

  -- See file header. `n` is already-normalized ({battle,user,target,gen2}
  -- from modern_combat.lua's normalize); `who` is whichever side (n.user
  -- or n.target) is having the stat changed, `fromEnemy` only matters on
  -- Gen 1 (Gen 2's changeStageAgainstMist derives the same Mist gate
  -- itself from who ~= n.user).
  --
  -- Boss-fight "statsDrop" protection checked FIRST, ahead of either
  -- native branch: this is the exact gap this file's own header already
  -- flags for Substitute (native changeStageAgainstMist/NativeMoveEffects
  -- .changeStage have no protection hooks of their own at all) -- the
  -- same reasoning applies here, so the check has to live at this call
  -- site rather than inside either native function. See modern_combat
  -- .lua's own bossStatsDropBlocked header for the full rule.
  local function changeNativeStage(n, who, stat, delta, fromEnemy)
    if bossStatsDropBlocked(n.battle, who, delta) then
      return { romText(n.battle.data, "_NothingHappenedText", "Nothing happened!") }
    end
    if n.gen2 then
      n.battle:changeStageAgainstMist(n.user, who, stat, delta)
      return {}
    end
    return NativeMoveEffects.changeStage(n.battle, who, stat, delta, fromEnemy)
  end

  -- fromEnemy derives the same way registerStatEffect's targetsSelf
  -- param already implies it: a self-change is never hostile; a
  -- target-directed change is hostile (Mist/Substitute-gated) only when
  -- it's a drop, never when it's a buff (e.g. Decorate raising a
  -- target's stats is not something Mist should block).
  local function applyChange(n, ch)
    local who = ch.self and n.user or n.target
    local fromEnemy = (not ch.self) and ch.delta < 0
    if ch.native then
      return changeNativeStage(n, who, ch.stat, ch.delta, fromEnemy)
    end
    return changeStage(n.battle, who, ch.stat, ch.delta, fromEnemy, n.gen2)
  end

  -- Guaranteed stat change(s) on a pure status move (power == 0) --
  -- kind="primary" fires it whole and unconditionally on both engines
  -- (BattleState.lua's own pure-status-move block on Gen 1, the
  -- unconditional moveEffectRecordFor dispatch on Gen 2), same shape as
  -- GMAX_AMNESIA_EFFECT/GMAX_GROWTH_EFFECT above. accuracyChecked=true
  -- whenever any change is target-directed (BattleState.lua:3637-3650
  -- only rolls a miss at all when this is set -- confirmed established
  -- precedent, modern_status_effects.lua's GMAX_ATTRACT/TAUNT/TORMENT_
  -- EFFECT, all target-directed) -- a self-only buff leaves it unset,
  -- since ctx.target is always the opponent regardless of who the
  -- effect actually reads, and rolling a "miss" against the opponent's
  -- evasion for the user's OWN buff would be wrong.
  local function primary(effectId, changes)
    local targetDirected = false
    for _, ch in ipairs(changes) do
      if not ch.self then targetDirected = true end
    end
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      accuracyChecked = targetDirected or nil,
      run = function(a, b, c)
        local n = normalize(a, b, c)
        local out = {}
        for _, ch in ipairs(changes) do
          for _, m in ipairs(applyChange(n, ch)) do out[#out + 1] = m end
        end
        return out
      end,
    })
  end

  -- Secondary stat change(s) on a damaging move (power > 0).
  --
  -- REAL, CONFIRMED BUG FIXED HERE (2026-08-28, direct user report --
  -- "liquidation move is dealing no damage"): this function used to
  -- register `kind = "secondary"` with a real `run` field and guard Gen 2
  -- INSIDE that handler (`if n.gen2 then return {} end`) -- but Gen 2's
  -- own real dispatch (gen2/Battle.lua:1533-1538) calls ANY move_effects
  -- record with a `.run` field BEFORE its own damage path and returns
  -- immediately once it does, true regardless of what the handler's body
  -- does -- the exact same real gotcha modern_hazards.lua's own Rapid Spin
  -- section already found and fixed. An internal Gen-2 guard never had a
  -- chance to matter: Gen 2 had already skipped its own damage computation
  -- by the time that guard ran. Every one of this helper's real callers
  -- (Liquidation, Crunch, Close Combat, Superpower, Flash Cannon, Energy
  -- Ball, Bug Buzz, Rock Tomb, Rock Smash, Play Rough, Spirit Break,
  -- Struggle Bug, Leaf Storm, Ancient Power, Acid Spray, Apple Acid,
  -- Breaking Swipe, Bulldoze, Drum Beating, Fire Lash, Flame Charge, Grav
  -- Apple, Hammer Arm, Lunge, Metal Claw, Power-Up Punch, Razor Shell,
  -- Steel Wing -- confirmed, every single move ever registered through
  -- this function) dealt ZERO damage on Gen 2 -- a real, systemic bug
  -- across this whole file, not just the one move reported.
  --
  -- Fixed the exact same way Rapid Spin already was: `kind = "full"` (no
  -- run field at all -- invisible to that dispatch check on both engines,
  -- confirmed via EffectRegistry.runDamaging being nil-safe on every stage
  -- field) for real, ordinary damage on both generations, and the stat
  -- change wired through `battle.damage_dealt` instead (confirmed
  -- identical payload on both engines, fires only AFTER a landed,
  -- non-zero hit -- exactly "the hit actually landed and dealt damage,"
  -- the same real condition the old kind="secondary" dispatch used). One
  -- shared listener below (not one per call), keyed by the move's own
  -- real `effect` field via SECONDARY_STAT_EFFECTS.
  --
  -- This also correctly ENABLES the stat-change half on Gen 2 for the
  -- first time: the old code's own `if n.gen2 then return {} end` had
  -- deliberately disabled it there as an honest scope limit (this file's
  -- own header, "damaging-move secondary effects ALWAYS gen2-guard") --
  -- moot now that battle.damage_dealt is a real, correct, both-engines
  -- dispatch point, so Gen 2 gets the real chance-based stat drop for the
  -- first time too, not just a damage fix.
  --
  -- Message display is ALSO fixed as a side effect: applyChange's own
  -- return value is a message-string array (changeStage/changeNativeStage
  -- both return strings, never emit themselves) that the OLD run()-based
  -- dispatch only ever displayed on Gen 1 (this file's own header, "Gen 2
  -- message caveat" -- Gen 2's dispatch discards a handler's return value
  -- entirely). This listener explicitly `battle:emit`s every returned
  -- string itself, so the message now shows on BOTH engines instead of
  -- silently only Gen 1.
  --
  -- chance255 is the move's real percentage out of 256, nil for a
  -- genuinely unconditional secondary. Self-targeted secondaries (Close
  -- Combat, Leaf Storm, Superpower) apply even on a KOing hit here (no
  -- `target.mon.hp > 0`-style gate on this new dispatch path) -- arguably
  -- MORE correct than the old EffectRegistry-gated behavior for a
  -- self-drop, not a regression.
  local SECONDARY_STAT_EFFECTS = {} -- effectId -> {changes=, chance255=}
  local function secondary(effectId, changes, chance255)
    mod.content.move_effects:register(effectId, { kind = "full" })
    SECONDARY_STAT_EFFECTS[effectId] = { changes = changes, chance255 = chance255 }
  end
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local move = ev and ev.move
    local effectId = move and move.effect
    local entry = effectId and SECONDARY_STAT_EFFECTS[effectId]
    if not (battle and entry and ev.user and ev.target and (ev.damage or 0) > 0) then return end
    if entry.chance255 and battle.rng(0, 255) >= entry.chance255 then return end
    local n = { battle = battle, user = ev.user, target = ev.target, gen2 = isGen2Battle(battle) }
    for _, ch in ipairs(entry.changes) do
      for _, m in ipairs(applyChange(n, ch)) do
        battle:emit({ kind = "message", text = m })
      end
    end
  end)

  ------------------------------------------------------------------
  -- Pure status moves (guaranteed, primary)
  ------------------------------------------------------------------
  primary("GMAX_AROMATICMIST_EFFECT", { { stat = "spd", delta = 1 } })
  primary("GMAX_BULKUP_EFFECT", { { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 } })
  primary("GMAX_CALMMIND_EFFECT", { { self = true, stat = "spa", delta = 1 }, { self = true, stat = "spd", delta = 1 } })
  -- Charge: +1 SpDef self is the only part wired -- doubling the next
  -- Electric move's power is a separate volatile this phase doesn't add.
  primary("GMAX_CHARGE_EFFECT", { { self = true, stat = "spd", delta = 1 } })
  primary("GMAX_CHARM_EFFECT", { { stat = "attack", delta = -2 } })
  primary("GMAX_COIL_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 },
    { self = true, stat = "accuracy", delta = 1, native = true },
  })
  primary("GMAX_CONFIDE_EFFECT", { { stat = "spa", delta = -1 } })
  primary("GMAX_COSMICPOWER_EFFECT", { { self = true, stat = "defense", delta = 1 }, { self = true, stat = "spd", delta = 1 } })
  primary("GMAX_COTTONGUARD_EFFECT", { { self = true, stat = "defense", delta = 3 } })
  primary("GMAX_COTTONSPORE_EFFECT", { { stat = "speed", delta = -2, native = true } })
  -- Decorate raises the TARGET's own stats -- beneficial, not hostile
  -- (applyChange's fromEnemy rule already keeps Mist from blocking it).
  primary("GMAX_DECORATE_EFFECT", { { stat = "attack", delta = 2 }, { stat = "spa", delta = 2 } })
  primary("GMAX_DRAGONDANCE_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "speed", delta = 1, native = true },
  })
  primary("GMAX_EERIEIMPULSE_EFFECT", { { stat = "spa", delta = -2 } })
  primary("GMAX_FAKETEARS_EFFECT", { { stat = "spd", delta = -2 } })
  primary("GMAX_HONECLAWS_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "accuracy", delta = 1, native = true },
  })
  primary("GMAX_IRONDEFENSE_EFFECT", { { self = true, stat = "defense", delta = 2 } })
  primary("GMAX_METALSOUND_EFFECT", { { stat = "spd", delta = -2 } })
  primary("GMAX_NASTYPLOT_EFFECT", { { self = true, stat = "spa", delta = 2 } })
  primary("GMAX_NOBLEROAR_EFFECT", { { stat = "attack", delta = -1 }, { stat = "spa", delta = -1 } })
  -- Play Nice's real distinguishing trait (vs. plain LowerTargetAttack1)
  -- is bypassing Substitute while still respecting Mist -- changeStage
  -- couples both checks together, so that split isn't expressible here;
  -- approximated as a normal Mist+Substitute-gated -1 Atk instead of
  -- guessing at a bespoke carve-out.
  primary("GMAX_PLAYNICE_EFFECT", { { stat = "attack", delta = -1 } })
  primary("GMAX_ROCKPOLISH_EFFECT", { { self = true, stat = "speed", delta = 2, native = true } })
  primary("GMAX_SCARYFACE_EFFECT", { { stat = "speed", delta = -2, native = true } })
  primary("GMAX_SHIFTGEAR_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "speed", delta = 2, native = true },
  })
  primary("GMAX_SWEETSCENT_EFFECT", { { stat = "evasion", delta = -2, native = true } })
  -- Tar Shot: -1 Speed only -- doubling Fire-move damage taken is a
  -- separate volatile flag this phase doesn't add.
  primary("GMAX_TARSHOT_EFFECT", { { stat = "speed", delta = -1, native = true } })
  primary("GMAX_TEARFULLOOK_EFFECT", { { stat = "attack", delta = -1 }, { stat = "spa", delta = -1 } })

  ------------------------------------------------------------------
  -- Damaging moves, secondary stat effects
  ------------------------------------------------------------------
  secondary("GMAX_ACIDSPRAY_EFFECT", { { stat = "spd", delta = -2 } }) -- 100%
  -- Ancient Power: 10% to raise ALL FIVE non-HP stats (incl. Speed) by 1.
  secondary("GMAX_ANCIENTPOWER_EFFECT", {
    { self = true, stat = "attack", delta = 1 }, { self = true, stat = "defense", delta = 1 },
    { self = true, stat = "spa", delta = 1 }, { self = true, stat = "spd", delta = 1 },
    { self = true, stat = "speed", delta = 1, native = true },
  }, 26)
  secondary("GMAX_APPLEACID_EFFECT", { { stat = "spd", delta = -1 } }) -- 100%
  secondary("GMAX_BREAKINGSWIPE_EFFECT", { { stat = "attack", delta = -1 } }) -- 100%
  secondary("GMAX_BUGBUZZ_EFFECT", { { stat = "spd", delta = -1 } }, 26) -- 10%
  -- Bulldoze: 100% -1 Speed target -- grassy-terrain power reduction not
  -- modeled (this mod's terrain support is separate/unbuilt).
  secondary("GMAX_BULLDOZE_EFFECT", { { stat = "speed", delta = -1, native = true } })
  secondary("GMAX_CLOSECOMBAT_EFFECT", { { self = true, stat = "defense", delta = -1 }, { self = true, stat = "spd", delta = -1 } }) -- 100%, self
  secondary("GMAX_CRUNCH_EFFECT", { { stat = "defense", delta = -1 } }, 51) -- 20%
  secondary("GMAX_DRUMBEATING_EFFECT", { { stat = "speed", delta = -1, native = true } }) -- 100%
  secondary("GMAX_ENERGYBALL_EFFECT", { { stat = "spd", delta = -1 } }, 26) -- 10%
  secondary("GMAX_FIRELASH_EFFECT", { { stat = "defense", delta = -1 } }) -- 100%
  secondary("GMAX_FLAMECHARGE_EFFECT", { { self = true, stat = "speed", delta = 1, native = true } }) -- 100%, self
  secondary("GMAX_FLASHCANNON_EFFECT", { { stat = "spd", delta = -1 } }, 26) -- 10%
  -- Grav Apple: 100% -1 Def target -- the Gravity-field power boost is a
  -- separate, unbuilt field-state mechanic.
  secondary("GMAX_GRAVAPPLE_EFFECT", { { stat = "defense", delta = -1 } })
  secondary("GMAX_HAMMERARM_EFFECT", { { self = true, stat = "speed", delta = -1, native = true } }) -- 100%, self
  secondary("GMAX_LEAFSTORM_EFFECT", { { self = true, stat = "spa", delta = -2 } }) -- 100%, self
  secondary("GMAX_LEAFTORNADO_EFFECT", { { stat = "accuracy", delta = -1, native = true } }, 128) -- 50%
  secondary("GMAX_LIQUIDATION_EFFECT", { { stat = "defense", delta = -1 } }, 51) -- 20%
  secondary("GMAX_LUNGE_EFFECT", { { stat = "attack", delta = -1 } }) -- 100%
  secondary("GMAX_METALCLAW_EFFECT", { { self = true, stat = "attack", delta = 1 } }, 26) -- 10%
  secondary("GMAX_PLAYROUGH_EFFECT", { { stat = "attack", delta = -1 } }, 26) -- 10%
  secondary("GMAX_POWERUPPUNCH_EFFECT", { { self = true, stat = "attack", delta = 1 } }) -- 100%
  secondary("GMAX_RAZORSHELL_EFFECT", { { stat = "defense", delta = -1 } }, 128) -- 50%
  secondary("GMAX_ROCKSMASH_EFFECT", { { stat = "defense", delta = -1 } }, 128) -- 50%
  secondary("GMAX_ROCKTOMB_EFFECT", { { stat = "speed", delta = -1, native = true } }) -- 100%
  secondary("GMAX_SPIRITBREAK_EFFECT", { { stat = "spa", delta = -1 } }) -- 100%
  secondary("GMAX_STEELWING_EFFECT", { { self = true, stat = "defense", delta = 1 } }, 26) -- 10%
  secondary("GMAX_STRUGGLEBUG_EFFECT", { { stat = "spa", delta = -1 } }) -- 100%
  secondary("GMAX_SUPERPOWER_EFFECT", { { self = true, stat = "attack", delta = -1 }, { self = true, stat = "defense", delta = -1 } }) -- 100%, self

  ------------------------------------------------------------------
  -- Clear Smog: wipes the TARGET's stat stages entirely (all 7 boost
  -- keys, Showdown's clearBoosts()) -- own store's atk/def/spa/spd via
  -- resetStages (gen2-aware), native who.stages.{speed,accuracy,evasion}
  -- directly (Gen 1's storage -- a Gen 2 raw mon has no .stages, so the
  -- guard skips it there; Gen 2's speed/evasion live in battle.stages
  -- [side], out of scope for this wipe, same as changeNativeStage).
  --
  -- Round 15: converted from kind="secondary"+run to kind="full" + a
  -- battle.damage_dealt listener. Clear Smog is a DAMAGING move (power
  -- 50), so the old shape hit the SAME systemic Gen-2 zero-damage bug
  -- this file's secondary() header documents (Gen 2's dispatch calls
  -- ANY move_effects record with a .run field before its own damage
  -- path and returns -- an internal `if n.gen2 then return {} end` guard
  -- never mattered because damage was already skipped). This listener
  -- runs AFTER a landed non-zero hit on BOTH engines, and enables the
  -- stat wipe on Gen 2 for the first time (the old handler was a
  -- hard no-op there), mirroring the secondary() migration above.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GMAX_CLEARSMOG_EFFECT", { kind = "full" })
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local move = ev and ev.move
    if not (battle and move and move.effect == "GMAX_CLEARSMOG_EFFECT") then return end
    if (ev.damage or 0) <= 0 then return end
    local target = ev and ev.target
    if not target then return end
    local gen2 = isGen2Battle(battle)
    -- Boss-fight "statsDrop" protection: Clear Smog ZEROES every stage
    -- rather than applying a signed delta, so it never reaches either
    -- of bossStatsDropBlocked's own call sites (changeStage/
    -- changeNativeStage) -- confirmed real gap, this mod's own
    -- research this session. Stripping the boss's own positive boosts
    -- down to 0 is a worsening exactly like any other drop (the
    -- dominant real use of this move against a boss), so the whole
    -- effect is blocked outright against a protected target rather
    -- than trying to selectively keep only the "cures an existing
    -- debuff" half.
    if target == battle.enemy and mod.exports.bossFightHas
        and mod.exports.bossFightHas(battle, "statsDrop") then
      battle:emit({ kind = "message", text = romText(battle.data, "_NothingHappenedText", "Nothing happened!") })
      return
    end
    local changed = resetStages(battle, target, gen2)
    if target.stages then
      for _, stat in ipairs({ "speed", "accuracy", "evasion" }) do
        if (target.stages[stat] or 0) ~= 0 then
          target.stages[stat] = nil
          changed = true
        end
      end
    end
    if not changed then
      battle:emit({ kind = "message", text = romText(battle.data, "_NothingHappenedText", "Nothing happened!") })
      return
    end
    local name = target.isPlayer and target.name or Strings("Enemy %s", target.name)
    battle:emit({ kind = "message", text = Strings("%s's stat\nchanges were\nremoved!", name) })
  end)

  mod.log:info("galar_gmax_dex: modern_movepool_stages loaded")
end
