-- Phase 3 (part 2) of the move-effect completion pipeline: Metal Burst and
-- Mirror Coat, the two Counter-family stubs (moves_new.lua's METALBURST/
-- MIRRORCOAT, both still effect="NO_ADDITIONAL_EFFECT" going into this
-- file). DETECT's patch lives directly in modern_combat_protect.lua (the
-- identical one-line pattern to that file's own PROTECT patch); FEINT's
-- Protect-bypass is a plain moves_new.lua data field (bypassesProtect),
-- patched onto the live FEINT record by main.lua's wireMovepoolSubEffects
-- -- neither needs a move_effects registration of its own, so neither
-- lives here.
--
-- What COUNTER's real implementation turned out to be (grepped src/battle/
-- MoveEffects.lua and EffectRegistry.lua for "COUNTER" first, per this
-- phase's own instruction, before writing anything): NOT a move_effects
-- record at all -- a hardcoded `if move.id == "COUNTER"` branch inside
-- EffectRegistry.lua's runDamaging (:149-171), reading `battle.lastDamage`,
-- Gen 1's shared wDamage byte -- the LAST damage dealt ANYWHERE in the
-- battle (by either side, from any source), gated only by whether the
-- opponent's last move was itself counterable (Normal/Fighting type,
-- power > 0). No physical/special split exists anywhere in it, and it
-- doesn't reset per turn -- both real, well-known Gen 1 Counter quirks (its
-- own "can counter your OWN last hit" exploitability), not a primitive
-- Metal Burst/Mirror Coat -- which need a genuine "physical or special
-- damage taken THIS turn" split -- can reuse.
--
-- Gen 2 DOES have the real primitive for exactly that split, but it's
-- Gen2-only and unreachable from a mod-registered move_effects record:
-- `defenderState.tookThisTurn`/`tookKind` (gen2/Battle.lua:1201-1202,
-- accumulated per hit inside Battle:dealDamage, cleared at the top of
-- every turn, gen2/Battle.lua:4028-4029) feeds a hardcoded `Effects.COUNTER`
-- table (gen2/Battle.lua:1478, gen2/Effects.lua:219-226) mapping
-- `def.effect == "EFFECT_COUNTER"`/`"EFFECT_MIRROR_COAT"` straight to
-- native dispatch (gen2/Battle.lua:1476-1489) -- entirely bypassing
-- mod.content.move_effects (Gen2's own dispatch, gen2/Battle.lua:1533-1538,
-- only ever reads a record's `.run` field -- the same limitation
-- modern_movepool_damage.lua's own header already established for
-- afterDamage/charge). Confirmed by grepping this engine's own shipped
-- data for the literal ids: no "COUNTER", "MIRRORCOAT", or "METALBURST"
-- move exists anywhere in it -- Gen 2's native Counter/Mirror Coat
-- mechanism is real, correct, tested code with nothing pointing at it yet.
--
-- Deliberately NOT rerouting MIRRORCOAT's effect field at the literal
-- native "EFFECT_MIRROR_COAT" string to pick that mechanism up for free:
-- same cross-generation reference risk modern_movepool_damage.lua's own
-- header already flags for Bounce/Outrage/Eternabeam -- move.effect is
-- validated as f.id("move_effects") against whichever generation's
-- registry is active for that boot, and Gen 1's own registry has no
-- "EFFECT_MIRROR_COAT" id, so a Gen 1 boot's registration would fail
-- outright. A custom GALAR_* id, registered fresh on every boot like every
-- other Phase 1/2 sibling, is the only shape valid on both.
--
-- Known, stated Gen 2 gap (not silently left unmentioned): METALBURST and
-- MIRRORCOAT below are GEN1-ONLY, the same "unwired, not broken" class of
-- gap as Bounce/Outrage/Eternabeam. On a Gen 2 boot these fall through to
-- Gen 2's own native damage path -- but since neither id exists in Gen 2's
-- own native data, that's an ordinary (and near-useless, given the power=1
-- placeholder) hit, not real Metal Burst/Mirror Coat. Gen 2 already has a
-- fully-correct native Mirror Coat sitting unused for exactly the reason
-- above; wiring MIRRORCOAT's Gen2-side data at the real "EFFECT_MIRROR_COAT"
-- id (a second, Gen2-specific registration path, not this file's custom
-- one) and building the Gen4-only Metal Burst into Gen 2's own dispatch/
-- priority table from scratch are both real follow-on work, not attempted
-- here.
--
-- The turn-scoped "damage taken by category" tracker: Gen 1 has no
-- existing primitive for this at all (unlike Protect's own turn-scoped
-- flag, which had a real value worth reusing -- Counter's shared
-- battle.lastDamage, per above, genuinely isn't one). Built here, but out
-- of two REAL existing primitives, not a new hook: `battle.damage_dealt`
-- (already emitted per landed hit by EffectRegistry.lua:285-290 --
-- confirmed zero consumers anywhere in this mod before this file) to
-- observe and accumulate, and the exact same `battle.turn_started` event
-- modern_combat_protect.lua's own Part C already uses to clear per-turn
-- state, in the same way, for the same reason.
--
-- chooseDamage, not perform: EffectRegistry.lua's runDamaging already has
-- a dedicated extension point for exactly this move family --
-- record.chooseDamage, explicitly commented there as "Counter/Super
-- Fang/OHKO/fixed damage" (:172-181) -- and it runs AFTER the normal
-- invulnerability check and accuracy roll (both earlier in runDamaging,
-- ~:104-145), unlike record.perform, which BattleState:performMove
-- dispatches to (:3631-3634) BEFORE either. A perform-shaped handler
-- modeled too literally on Protect's own (a genuinely different case: a
-- power=0, priority-4 status move that never rolls a miss in any real
-- generation) would have silently skipped Metal Burst/Mirror Coat's real
-- accuracy check (evasion, a mid-Fly/Dig target) entirely -- a real
-- behavioral gap, not a style choice, which is why this deviates from a
-- literal perform-shaped read of the plan. A failed chooseDamage returns
-- (nil, message) -- runDamaging's own caller prints it and cancels the
-- move anim on its own (:176-179), so unlike Protect's perform, this needs
-- no ctx.say call itself.
--
-- Protect: chooseDamage bypasses battle:computeDamage entirely (it's a
-- parallel branch inside runDamaging, not a call into it), so it also
-- bypasses modern_combat_protect.lua's own battle.damage hook (that file's
-- Part B) -- re-checked manually here, reusing the exact same "It doesn't
-- affect %s!" message that hook's own typeMult=0 short-circuit produces
-- (EffectRegistry.lua:187-191), so a protected target sees identical
-- failure text regardless of which code path blocked the hit. Neither move
-- sets bypassesProtect (that's Feint-only), but the check mirrors Part B's
-- exact condition shape anyway rather than a narrower one.
--
-- "Original attacker already fainted or switched out" (both moves' real
-- fail condition, per Showdown): stored alongside the accumulated damage
-- is the attacker's own MON table, not the battler slot -- battle.player/
-- battle.enemy are stable per-side tables reused across a switch (only
-- their own `.mon` field changes, confirmed by Pain Split's own
-- userMon/targetMon reads in modern_movepool_damage.lua), so comparing
-- battler identity alone could never detect a mid-battle switch. Requires
-- ctx.target.mon to still be that exact same mon table, with hp > 0.
return function(mod)
  local Damage = require("src.battle.Damage")
  local romText = require("src.core.RomText")

  -- Damage.lua's own categoryOf (Damage.lua:110-124) is a local, not
  -- exported -- this reproduces its exact fallback chain (a move's own
  -- category field first, else Gen 1's type-based split) using the one
  -- piece of it that IS public, Damage.isSpecial, rather than guessing at
  -- a simplified version: a native move (Tackle, Thunderbolt, ...) has no
  -- registered `category` field at all and needs the type fallback to
  -- read correctly here too, not just GalarGmaxDex's own moves.
  local function categoryOf(move)
    if not move then return "physical" end
    if move.category == "physical" or move.category == "special" then
      return move.category
    end
    return Damage.isSpecial(move.type) and "special" or "physical"
  end

  ------------------------------------------------------------------
  -- Accumulate "damage taken this turn, by category" onto whichever
  -- battler got hit -- see file header for why this is built fresh
  -- (nothing in Gen 1 already tracks this) out of two existing primitives
  -- rather than a new hook. Also fires on a Gen 2 boot (gen2/Battle.lua's
  -- own battle.damage_dealt emit, :1241-1252, carries `kind` directly --
  -- used here when present instead of re-deriving it) but is inert there:
  -- see header, chooseDamage below is never read by Gen 2's own dispatch.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target = ev and ev.target
    if not (target and (ev.damage or 0) > 0) then return end
    target.counterTookThisTurn = (target.counterTookThisTurn or 0) + ev.damage
    target.counterTookKind = ev.kind or categoryOf(ev.move)
    target.counterAttackerMon = ev.user and ev.user.mon
  end)

  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local function clear(who)
      if not who then return end
      who.counterTookThisTurn = nil
      who.counterTookKind = nil
      who.counterAttackerMon = nil
    end
    clear(battle.player)
    clear(battle.enemy)
  end)

  -- wantedKind = nil accepts either category (Metal Burst); a string
  -- requires an exact match (Mirror Coat: "special" only).
  local function registerCounterFamily(effectId, numerator, denominator, wantedKind)
    mod.content.move_effects:register(effectId, {
      kind = "full",
      chooseDamage = function(ctx)
        local battle, user, target = ctx.battle, ctx.user, ctx.target
        if target and target ~= user and target.protected
            and not (ctx.move and ctx.move.bypassesProtect) then
          return nil, romText(battle.data, "_DoesntAffectMonText",
            "It doesn't affect\n%s!", ctx.displayName(target))
        end
        local taken = user.counterTookThisTurn or 0
        local rightKind = wantedKind == nil or user.counterTookKind == wantedKind
        local attackerStillOut = target and user.counterAttackerMon == target.mon
          and (target.mon.hp or 0) > 0
        if taken <= 0 or not rightKind or not attackerStillOut then
          return nil, romText(battle.data, "_ButItFailedText", "But, it failed!")
        end
        local dmg = math.max(1, math.floor(taken * numerator / denominator))
        return math.min(65535, dmg), { crit = false, typeMult = 10 }
      end,

      -- THE GEN 2 HALF.  `chooseDamage` above is read by Gen 1's
      -- EffectRegistry and by nothing else -- Gen 2 dispatches a mod's move
      -- effect through Battle.moveEffectRecordFor(...).run and reads no other
      -- field (src/battle/gen2/Battle.lua). So on Gold and Crystal the whole
      -- family above was unreachable, and Metal Burst landed as an ordinary
      -- move. This file's own header recorded that as a hard limit; it is not
      -- one. What the header established is that Gen 2's own COUNTER TABLE
      -- cannot be registered into -- but the state that table reads is just a
      -- volatile, and a mod can read it directly.
      --
      -- `tookThisTurn` / `tookKind` are accumulated per hit inside
      -- Battle:dealDamage and cleared at the top of every turn, on the
      -- volatile of whoever TOOK the damage -- which for a counter move is
      -- the user. Mirrored from the native arm beside it, which does exactly
      -- this for EFFECT_COUNTER / EFFECT_MIRROR_COAT.
      --
      -- GUARDED TO GEN 2 ONLY, and that guard is load-bearing: Gen 1's
      -- EffectRegistry ALSO calls `record.run` for any record whose kind is
      -- not "primary" (EffectRegistry.lua:341), and this one is "full". An
      -- unguarded run would therefore fire on Gen 1 as well, on top of the
      -- chooseDamage that already resolved the move -- countering twice.
      run = function(a, b, c, d, e)
        -- Lazily, for the same reason main.lua's GALAR_TRAP_EFFECT reads it
        -- lazily: this closure runs at battle time, long after
        -- modern_combat.lua publishes it, so no load-order assumption.
        local normalize = mod.exports.normalize
        if not normalize then return {} end
        local n = normalize(a, b, c)
        -- Gen 1 already resolved this move through chooseDamage above.
        if not n.gen2 then return {} end

        local battle, user, target = n.battle, n.user, n.target
        if not (battle and user and target) then return {} end
        local def, moveId = d, e
        local state = battle:volatile(user)
        local taken = state.tookThisTurn or 0
        local rightKind = wantedKind == nil or state.tookKind == wantedKind
        if taken <= 0 or not rightKind then
          battle:markMissed()
          battle:emit({ kind = "message", text = "But it failed!" })
          return {}
        end
        local dmg = math.max(1, math.floor(taken * numerator / denominator))
        battle:dealDamage(user, target, math.min(65535, dmg),
          { move = def, moveId = moveId })
        return {}
      end,
    })
  end

  -- Metal Burst: whichever category landed, 1.5x.
  registerCounterFamily("GALAR_METALBURST_EFFECT", 3, 2, nil)
  -- Mirror Coat: special only, 2x (matches native Gen 1 Counter's own 2x
  -- and Gen 2's real Effects.counterDamage, gen2/Effects.lua:224-226).
  registerCounterFamily("GALAR_MIRRORCOAT_EFFECT", 2, 1, "special")

  mod.log:info("galar_gmax_dex: modern_movepool_counter loaded")
end
