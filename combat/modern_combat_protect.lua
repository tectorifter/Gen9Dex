-- Protect move logic: genuine greenfield work (confirmed by grepping all of
-- src/battle/ for "protect"/"Protect"/"Detect" -- only unrelated Mist/Light
-- Screen flavor text exists; Gen 1's original ROM never had Protect at all,
-- it was introduced Gen 2).
--
-- Gen-2-only file (this mod's own manifest declares "games": {"gen2"}), so
-- everything here targets gen2/Battle.lua's own API directly rather than
-- Gen 1's BattleState/EffectRegistry -- a real, confirmed bug this file
-- previously had: it was built entirely against the Gen 1 shape
-- (move_effects records with a `perform(ctx)` field, kind = "full",
-- BattleState.performMove) despite never running under anything but Gen 2.
-- Confirmed by direct read of gen2/Battle.lua:1533-1538 -- the only
-- dispatch site for a move's registered effect record reads
-- `effectRecord.run`, called positionally as
-- `run(self, attacker, defender, def, moveId, sureHit)` -- never
-- `.perform`, which the move_effects schema (src/mods/Schemas.lua:1280-
-- 1288) doesn't even define as a field. So every `perform` handler this
-- file registered was silently never invoked in an actual game: PROTECT/
-- DETECT/BATTLE_FORMS_MAXGUARD's own effect always resolved to nothing
-- callable and fell straight through the damage-less path (their power is
-- 0), which is exactly the reported symptom -- no flag ever set, no
-- message, Part B's battle.damage hook always saw an unprotected target.
--
-- Part A: PROTECT already exists in this mod's own data
-- (GalarGmaxDex/moves_new.lua, priority = 4, correct already) as a
-- documented no-op (effect = "NO_ADDITIONAL_EFFECT", functionCode =
-- "ProtectUser" -- functionCode is dead documentation, grepped: nothing in
-- the core engine ever reads it). Registered here as a real move_effects
-- record (kind = "primary", a `run` handler in Gen 2's own calling
-- convention -- the same shape modern_hazards.lua's GALAR_STEALTHROCK_
-- EFFECT/GALAR_TOXICSPIKES_EFFECT already use successfully) and patched
-- onto PROTECT. Effect records are keyed by move id, so this applies
-- identically in wild, trainer, and link battles with no extra wiring --
-- and any future Detect/Endure/Spiky Shield/Baneful Bunker/King's Shield
-- can point their own `effect` field at this exact same id (they're
-- mechanically identical decay chains in every real generation).
--
-- Success-chance formula deliberately stays the modern Showdown "stall"
-- decay (1/3 per consecutive use, capped 1/729) rather than switching to
-- Gen 2's own native halving chain (Effects.protectSucceeds, the formula
-- Battle.MOVE_EFFECTS.EFFECT_PROTECT already uses natively) -- an earlier,
-- separate, already-explained design choice this fix doesn't revisit; only
-- the dispatch/messaging plumbing was actually broken.
--
-- Part B: blocking an INCOMING damaging move against a protected target.
--
-- Wraps battle.damage (the same hook modern_combat.lua already uses) at a
-- HIGHER priority, so it runs first in the chain and can short-circuit
-- straight to typeMult = 0 without ever calling next() -- reusing Gen 2's
-- own existing, already-correct handling for that exact value (confirmed
-- by direct read, gen2/Battle.lua:1124-1140:
-- `normalizeDamageInfo` maps `typeMult` onto `info.effectiveness`, and
-- `if info.effectiveness == 0 then ... "It doesn't affect %s..." ... end`
-- short-circuits before dealDamage is ever called). Same code path a type
-- immunity already uses, so no new message logic is needed here at all --
-- PP/animation/announcement all run completely normally through the
-- untouched native useMove, and only the damage number comes back zeroed.
--
-- Part D: blocking an INCOMING pure status move (Thunder Wave, Toxic, a
-- stat-lowering move) against a protected target -- these never call
-- hitOnce/battle.damage at all, so Part B's hook never sees them. No hook
-- exists for "a primary status effect is about to run" the way
-- battle.damage does for damage, so this wraps Battle:useMove itself --
-- but NOT the naive "block before native runs at all" version: that would
-- skip PP decrement and the "X used Y!" announcement, giving the attacker
-- their move back for free, which is wrong (a Protect-blocked move still
-- costs PP and still gets announced in every real generation, exactly
-- like Part B's reasoning for damaging moves).
--
-- Instead, when the block condition is met, this temporarily swaps
-- Battle.moveEffectRecordFor (gen2/Battle.lua:2703's own lookup function,
-- a plain function on the class table, not per-instance -- the same
-- monkeypatch shape modern_hazards.lua's own header cites this file as
-- having established) for the single native useMove call, substituting a
-- "doesn't affect" stand-in record -- so native's PP/announcement/
-- accuracy-roll logic (useMove's own top half) runs completely unmodified
-- and unduplicated, and only the real record.run(...) that would have
-- applied the effect is swapped out. Restored immediately after, even on
-- error.
return function(mod)
  local Battle = require("src.battle.gen2.Battle")
  local PROTECT_EFFECT_ID = "GMAX_PROTECT_EFFECT"
  local MAX_GUARD_EFFECT_ID = "GMAX_MAX_GUARD_EFFECT"
  local MAX_GUARD_MOVE_ID = "BATTLE_FORMS_MAXGUARD"

  ------------------------------------------------------------------
  -- Part A: Protect's own move -- the real decaying success chain
  -- (Showdown's exact "stall" volatile, matching Bulbapedia's documented
  -- values): 100% on first use or after a break in the chain, 1/3 on the
  -- second consecutive use, 1/9 on the third, and so on, capped at
  -- 1/729. Resets to 100% on failure OR on any turn gap (not used last
  -- turn).
  ------------------------------------------------------------------
  mod.content.move_effects:register(PROTECT_EFFECT_ID, {
    kind = "primary",
    run = function(battle, user)
      local consecutive = user.protectChainTurn == (battle.turnCount or 0) - 1
      local x = (consecutive and user.protectChainX) or 1
      local success = battle:roller()(x) == 0
      if success then
        user.protected = true
        user.protectChainX = math.min(x * 3, 729)
        user.protectChainTurn = battle.turnCount
        battle:emit({ kind = "message",
          text = battle:monName(user) .. " protected itself!" })
      else
        user.protectChainX = nil
        battle:emit({ kind = "message", text = "But it failed!" })
      end
    end,
  })
  mod.content.moves:patch("PROTECT", { effect = PROTECT_EFFECT_ID })
  -- Detect (functionCode "ProtectUser", the same as Protect's own) is
  -- mechanically identical to Protect in every real generation -- same
  -- decaying success chain, same target flag. Phase 3 of the move-effect
  -- completion pipeline: this was the one line missing, moves_new.lua's
  -- own DETECT entry (priority 4, correct already) needed no other change.
  mod.content.moves:patch("DETECT", { effect = PROTECT_EFFECT_ID })

  ------------------------------------------------------------------
  -- Part A2: Max Guard, rebuilt onto this same Protect chain instead of
  -- battle_forms's own original implementation. Confirmed by reading
  -- battle_forms/src/maxmoves.lua directly: its own M.GUARD_EFFECT sets
  -- `user.invulnerable = true` -- the engine's native semi-invulnerability
  -- flag (the same one Fly/Dig use), not a Protect-style flag at all, and
  -- with no concept of a Feint/Z-Move exception or a different rule
  -- against incoming Max/G-Max moves. Explicit user instruction (2026-08-20):
  -- combat sub-effects, including gimmick move interactions, are this
  -- mod's own domain -- so BATTLE_FORMS_MAXGUARD's effect is patched to
  -- point here instead, replacing battle_forms's invulnerable-flag
  -- approach outright rather than layering on top of it (both active at
  -- once would leave the native semi-invulnerability check ALSO blocking
  -- things this new effect intends to let through, e.g. Feint).
  --
  -- Shares Protect's own protectChainTurn/protectChainX counter fields
  -- (real games treat every member of the Protect family -- Protect,
  -- Detect, Max Guard, Spiky Shield, etc. -- as one shared decaying
  -- chain per Pokemon, not a separate counter per move), but sets a
  -- DIFFERENT target flag (maxGuarded, not protected) -- Part B below
  -- reads which flag is set to tell Max Guard's own 100%-blocks-
  -- everything-including-Max-Moves rule apart from plain Protect's
  -- 75%-blocks-Max-Moves rule.
  ------------------------------------------------------------------
  mod.content.move_effects:register(MAX_GUARD_EFFECT_ID, {
    kind = "primary",
    run = function(battle, user)
      mod.log:info("galar_gmax_dex: modern_combat_protect: [diag] Max Guard run() reached")
      local consecutive = user.protectChainTurn == (battle.turnCount or 0) - 1
      local x = (consecutive and user.protectChainX) or 1
      local success = battle:roller()(x) == 0
      if success then
        user.maxGuarded = true
        user.protectChainX = math.min(x * 3, 729)
        user.protectChainTurn = battle.turnCount
        battle:emit({ kind = "message",
          text = battle:monName(user) .. " protected itself!" })
      else
        user.protectChainX = nil
        battle:emit({ kind = "message", text = "But it failed!" })
      end
    end,
  })
  -- priority = 4 set explicitly, not left to patch-merge with
  -- battle_forms's own registration: explicit user instruction after
  -- live testing showed Max Guard's user taking no visible action/turn
  -- at all -- consistent with Max Guard losing its going-first priority
  -- and resolving after the incoming hit already landed instead of
  -- before it. battle_forms's own registerMove call already sets
  -- priority = 4 (src/maxmoves.lua:136) and Registry.lua's op-log/fold
  -- model should compose patches from different mods without one
  -- clobbering the other's fields -- but stating it here removes any
  -- doubt rather than trusting that merge silently, given the live
  -- symptom pointed straight at priority.
  --
  -- Called SYNCHRONOUSLY, right here, not deferred to any event --
  -- confirmed directly (src/mods/Loader.lua:1717 registry:freeze() runs
  -- BEFORE :1728's "mods.loaded" emit) that a mod.content.moves:patch
  -- call from a "mods.loaded" handler hits an already-frozen registry.
  -- A same-day attempt to defer this call there was reverted for exactly
  -- that reason -- it silently no-opped every time (Registry:patch on a
  -- frozen registry throws, and the event dispatcher's own protective
  -- pcall swallowed it with no visible error), confirmed by the Z-Move
  -- heuristic's own patched-count dropping from a real number to 0 and
  -- this block's own diagnostic never printing at all.
  --
  -- The real fix for battle_forms's load order is `battle_forms` now
  -- listed in THIS mod's own manifest.json optional_dependencies (see
  -- that file) -- a real graph edge (Loader.lua:739-749) that makes
  -- battle_forms's entire entry function, including every move it
  -- registers, finish running before this mod's own entry function ever
  -- starts, regardless of the two mods' raw priority numbers. battle_forms
  -- ALSO lists this mod as ITS OWN optional dependency, so this creates a
  -- genuine two-mod cycle -- confirmed the loader breaks exactly this
  -- shape deliberately rather than failing (Loader.lua:766-774,
  -- "optional dependency loop broken at %s", alphabetically-first id
  -- wins) -- "battle_forms" sorts before "g9-battle-engine-beta", so the
  -- cycle resolves in the direction this file's own patch below needs.
  mod.content.moves:patch(MAX_GUARD_MOVE_ID, { effect = MAX_GUARD_EFFECT_ID, priority = 4 })

  -- Diagnostic: confirms both this patch and Registry's own fold
  -- actually landed, since reasoning about it in the abstract hasn't
  -- been reliable enough this session -- read back what the LIVE
  -- resolved record actually holds right after patching.
  do
    local ok, resolved = pcall(function() return mod.content.moves:get(MAX_GUARD_MOVE_ID) end)
    mod.log:info("galar_gmax_dex: modern_combat_protect: [diag] %s resolved as effect=%s priority=%s (ok=%s)",
      MAX_GUARD_MOVE_ID, tostring(ok and resolved and resolved.effect), tostring(ok and resolved and resolved.priority),
      tostring(ok))
  end

  -- "Is this a Max Move or G-Max move" -- explicit user spec: Protect
  -- reduces these to 25% damage (not a full block, unlike every other
  -- damaging move); Max Guard still blocks them entirely. Detected by
  -- battle_forms's own confirmed id convention (src/maxmoves.lua:38,
  -- M.PREFIX = "BATTLE_FORMS_", every Max/G-Max move stem starts with
  -- MAX/GMAX) rather than a hand-maintained id list, since this mod
  -- cannot read battle_forms's own data files directly (sandboxed
  -- mod:read refuses a path outside this mod's own folder) -- excludes
  -- Max Guard's own id specifically, which is a status move, not a
  -- damage-dealing one this rule ever applies to.
  local function isMaxMove(move)
    local id = move and move.id
    return id ~= nil and id ~= MAX_GUARD_MOVE_ID and id:match("^BATTLE_FORMS_G?MAX") ~= nil
  end

  ------------------------------------------------------------------
  -- Part B: block an incoming damaging move against a protected target.
  -- Priority 50, above modern_combat.lua's damage-formula hook (0) --
  -- runs first in the chain. ctx.user ~= ctx.target guards a protected
  -- mon's own follow-up self-targeting moves (Swords Dance, Recover,
  -- using Protect again) from ever being blocked by its own flag.
  --
  -- Explicit user spec, four rules in priority order:
  --   1. move.bypassesProtect (Feint, Z-Moves -- see Part E below for how
  --      Z-Moves get this flag) -- ignores any shield entirely, full
  --      damage, unchanged from before.
  --   2. target.maxGuarded -- 100% block of everything else, Max/G-Max
  --      moves included (Max Guard's whole point: it stops what plain
  --      Protect can't).
  --   3. target.protected + an incoming Max/G-Max move -- NOT a full
  --      block: next(ctx) runs the real formula, then the result is
  --      scaled to 25% (rounded to the nearest whole number, floor+0.5
  --      matching this file's own established rounding elsewhere).
  --   4. target.protected against anything else -- 100% block, unchanged
  --      from before.
  ------------------------------------------------------------------
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local target = ctx.target
    if not (target and target ~= ctx.user) then return next(ctx) end
    if ctx.move and ctx.move.bypassesProtect then return next(ctx) end

    if target.maxGuarded then
      return 0, { crit = false, typeMult = 0 }
    end

    if target.protected then
      -- Unseen Fist / Piercing Drill (Phase 8, other bucket): both real,
      -- confirmed CONTACT-move-specific bypasses of an incoming Protect
      -- (checked against the ATTACKER's own ability, the real direction
      -- -- neither is about the defender). Unseen Fist: full damage,
      -- same as a Max move ignoring a plain Protect entirely never
      -- applies here since Unseen Fist isn't scaled at all. Piercing
      -- Drill: real text is explicit about a 1/4-damage bypass -- reuses
      -- the exact same 25% scale-down/rounding the Max-move branch just
      -- below already established, rather than a second rounding rule.
      local abilityIdOf = mod.exports.abilityIdOf
      local makesContact = mod.exports.makesContact
      local userAbility = abilityIdOf and ctx.user and abilityIdOf(ctx.user)
      local contact = makesContact and ctx.move and makesContact(ctx.move.id, ctx.user)
      if contact and userAbility == "UNSEENFIST" then
        return next(ctx)
      end
      if contact and userAbility == "PIERCINGDRILL" then
        local dmg, info = next(ctx)
        dmg = math.floor((dmg or 0) * 0.25 + 0.5)
        return dmg, info
      end
      if isMaxMove(ctx.move) then
        local dmg, info = next(ctx)
        dmg = math.floor((dmg or 0) * 0.25 + 0.5)
        return dmg, info
      end
      return 0, { crit = false, typeMult = 0 }
    end

    return next(ctx)
  end, 50)

  ------------------------------------------------------------------
  -- Part C: turn-scoped cleanup. Runtime.emit("battle.turn_started", ...)
  -- fires once both sides have chosen and before either acts, before
  -- either battler's action executes -- so clearing here, then Protect's/
  -- Max Guard's own run() (above) re-setting a flag if used again this
  -- turn, always happens in the right order regardless of move order.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local function clear(who)
      if not who then return end
      who.protected = nil
      who.maxGuarded = nil
    end
    clear(battle.player)
    clear(battle.enemy)
  end)

  ------------------------------------------------------------------
  -- Part C2: real, confirmed bug fix (2026-08-28, direct user report --
  -- "max guard and protect uses aren't doing the formula for lower
  -- chance till fail to restore 100% chance of passing"). The decay
  -- chain (protectChainX/protectChainTurn) is stored directly on the
  -- mon's own persistent table, NOT a per-battle volatile -- confirmed
  -- the same real shape this whole session's own established knowledge
  -- already flags repeatedly (Gen 2 mon tables are the persistent party
  -- members, the SAME table across every battle that mon ever fights).
  -- Real Showdown's own equivalent ("stall") is a genuine per-BATTLE
  -- volatile that clears automatically on switch-out and never exists
  -- at all in a fresh battle -- this mod's own fields had no such
  -- clearing anywhere (confirmed, grepped every reference to both
  -- fields in this whole mod: only ever read/written inside this same
  -- file's own two run() handlers above, never reset elsewhere), so a
  -- mon that had decayed down to 1/9 or lower stayed decayed forever
  -- after switching out and back in, or even into a LATER, completely
  -- separate battle -- exactly the reported symptom, "never restores
  -- 100%." Fixed the same real way modern_items.lua's own Ripen/Cheek
  -- Pouch state (ggdLastConsumedItem/ggdConsumedBerryThisBattle) already
  -- resets: on `battle.started` for the WHOLE party (every mon that
  -- might switch in fresh, not just the two currently active) and on
  -- `battle.battler_switched` for whichever mon just left (`ev.previous`
  -- -- the same real field Natural Cure/Regenerator already read for an
  -- identical "the mon that just left" need).
  ------------------------------------------------------------------
  local function clearProtectChain(mon)
    if not mon then return end
    mon.protectChainX = nil
    mon.protectChainTurn = nil
  end
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(battle.party or {}) do clearProtectChain(mon) end
    for _, mon in ipairs(battle.enemyParty or {}) do clearProtectChain(mon) end
  end)
  mod.events:on("battle.battler_switched", function(ev)
    clearProtectChain(ev and ev.previous)
  end)

  ------------------------------------------------------------------
  -- Part E: Z-Moves bypass Protect/Max Guard entirely, same as Feint --
  -- explicit user spec. Unlike Feint (a fixed id already carrying
  -- bypassesProtect = true in this mod's own moves_new.lua), Z-Moves are
  -- ~100 individually-registered ids owned entirely by battle_forms, with
  -- no shared marker field on the registered record to test (confirmed
  -- by reading battle_forms/src/zmoves.lua and speciesz.lua's own
  -- mod.content.moves:register calls directly -- id/name/type/power/
  -- accuracy/pp/effect only, nothing like a `kind`/`zMove` flag) and no
  -- way to read battle_forms's own source data files to enumerate them
  -- properly (same sandboxing limit as isMaxMove above). Best-effort
  -- heuristic instead: every BATTLE_FORMS_-prefixed move that ISN'T a Max/
  -- G-Max move (isMaxMove above) and isn't a Tera Blast variant (a real,
  -- ordinary damaging move Tera just retypes, never Protect-exempt) gets
  -- the flag.
  --
  -- Confirmed bug, fixed here: this originally ran on "mods.loaded",
  -- reasoning that it needed to wait for battle_forms's own moves to be
  -- registered first. Direct read of src/mods/Loader.lua proved that
  -- reasoning backwards -- registry:freeze() (Loader.lua:1465) runs
  -- BEFORE "mods.loaded" is ever emitted (Loader.lua:1476), so every
  -- mod.content.moves:patch call in the original version was silently
  -- throwing "content is frozen after load" inside its own pcall, every
  -- single time -- this whole block was a no-op from the start. The real
  -- fix needs no event wait at all: mod loading is priority-ascending,
  -- ties broken by id (Loader.lua's own orderedIds/_order) -- confirmed
  -- battle_forms's manifest priority is 80, this mod's is 95, so
  -- battle_forms's entire entry function (including every move it
  -- registers) has already finished running by the time this mod's own
  -- entry function -- this line included -- starts. Runs synchronously,
  -- same as every other registration in this file. Logs exactly what it
  -- patched so this heuristic's real coverage is checkable rather than
  -- silently trusted.
  ------------------------------------------------------------------
  do
    -- Whole block pcall-guarded, not just each individual patch() call --
    -- confirmed real risk: if mod.content.moves:each() itself doesn't
    -- exist or throws for any reason, that was previously an UNCAUGHT
    -- error that would abort the rest of this file's install (Part D
    -- below, status-move blocking, never gets wired) and cascade further
    -- (nothing calling this file's install function catches errors
    -- either) -- exactly matching a live symptom of damage AND status
    -- effects both failing to be blocked together, not just Z-Move
    -- bypass being incomplete.
    local runOk, runErr = pcall(function()
      local patched = 0
      for id in mod.content.moves:each() do
        if type(id) == "string" and id:match("^BATTLE_FORMS_")
            and not isMaxMove({ id = id })
            and not id:match("^BATTLE_FORMS_TERA_BLAST") then
          local ok = pcall(function() mod.content.moves:patch(id, { bypassesProtect = true }) end)
          if ok then patched = patched + 1 end
        end
      end
      mod.log:info("galar_gmax_dex: modern_combat_protect: marked %d battle_forms move(s) as Protect/Max-Guard-bypassing (Z-Move heuristic)", patched)
    end)
    if not runOk then
      mod.log:warn("galar_gmax_dex: modern_combat_protect: Z-Move bypass heuristic errored, skipped (%s)", tostring(runErr))
    end
  end

  ------------------------------------------------------------------
  -- Part D: block an incoming pure status move (power == 0, a
  -- record.kind == "primary"/"secondary" effect) against a protected
  -- target. See the file header for why this can't reuse Part B's
  -- battle.damage hook and why it doesn't just skip useMove outright.
  --
  -- Own move/Detect/Max Guard being reapplied is never caught by this:
  -- attacker == defender whenever a mon targets itself, so `defender ~=
  -- attacker` already excludes it without needing to name PROTECT_
  -- EFFECT_ID/MAX_GUARD_EFFECT_ID specifically.
  ------------------------------------------------------------------
  local nativeUseMove = Battle.useMove
  local nativeMoveEffectRecordFor = Battle.moveEffectRecordFor
  function Battle:useMove(attacker, defender, moveId)
    local blockable = defender and defender ~= attacker
      and (defender.protected or defender.maxGuarded)
    if not blockable then
      return nativeUseMove(self, attacker, defender, moveId)
    end
    local ok, def = pcall(function() return self:moveDef(moveId) end)
    if not (ok and def and (def.power or 0) == 0 and not def.bypassesProtect) then
      return nativeUseMove(self, attacker, defender, moveId)
    end
    Battle.moveEffectRecordFor = function(data, effect)
      local real = nativeMoveEffectRecordFor(data, effect)
      if real and (real.kind == "primary" or real.kind == "secondary") then
        return {
          kind = "primary",
          run = function(battle)
            battle:emit({ kind = "message",
              text = "It doesn't affect " .. battle:monName(defender) .. "..." })
          end,
        }
      end
      return real
    end
    local callOk, callErr = pcall(nativeUseMove, self, attacker, defender, moveId)
    Battle.moveEffectRecordFor = nativeMoveEffectRecordFor
    if not callOk then
      mod.log:warn("galar_gmax_dex: modern_combat_protect: status-move block-check errored (%s)",
        tostring(callErr))
      error(callErr, 0)
    end
  end

  mod.log:info("galar_gmax_dex: modern_combat_protect loaded")
end
