-- g9-battle-engine-beta -- forked from g9-battle-engine (2026-08-20),
-- combat engine only: species/evolutions/typing, movepool, Gigantamax
-- moves/forms, and the full modern damage/status/weather/hazards/items
-- combat pipeline. Deliberately owns NONE of g9-battle-engine's asset
-- handling -- no battle sprites, no overworld sprites, no wild-spawn
-- engine, no follower engine, no party icons. Those stay g9-battle-
-- engine's job; this fork exists so combat-engine work never has to
-- touch (or wait on) any of that. If you're looking for that half, see
-- the sibling g9-battle-engine mod instead.
--
-- Phase 1 registers every species national_dex reports (the base-stat/
-- type/dex source of truth now -- explicit user decision), with
-- evolutions bound in from species_evolutions.lua (national_dex's own
-- evolutions field ships empty).
--
-- Phase 2 (wireMovepoolSubEffects/patchLearnsets below) replaces Phase 1's
-- placeholder { "TACKLE" } moveset with each species' real level-up
-- learnset. See wireMovepoolSubEffects's own header for how move
-- completeness is judged -- entirely off national_dex's own live data,
-- no static per-move triage file. Base move data itself is always
-- national_dex's alone, never registered by this mod.
-- combat/learnset_ownership.lua (national_dex's own unfiltered movesets)
-- is the real, current learnset source -- the old combat/learnsets_data
-- .lua self-authored table this comment used to point at has been
-- deleted, it had been dead/unreferenced for a while already.
--
-- Two evolution triggers this batch needs don't exist in the base engine
-- and are built here, scoped to just what this mod needs:
--   * HAPPINESS (Pichu->Pikachu, Munchlax->Snorlax): a minimal friendship
--     counter, mirroring kanto-ascendant's own FRIENDSHIP method
--     (johto.lua) but without a day/night split, since neither evolution
--     needs one. Approximated: gains happiness after any battle rather
--     than tracking the real games' precise per-action deltas, since this
--     engine exposes no such granularity to hook.
--   * A generic consumable-item evolution hook, generalizing Gorochu's
--     one-off Thunder Tear pattern (gorochu.lua's installItemEffect) to
--     any number of item/species pairs, for the 11 new items this batch
--     introduces (2 Apples, 2 Scrolls, 7 Sweets). Milcery's evolution is
--     PBS "HoldItem" (hold + level up); approximated here as consumable
--     use instead, since there is no held-item mechanic to check against.

-- Sibling-file loader: identical to kanto-ascendant's own main.lua
-- loadSibling helper. mod:read() goes through the loader filesystem (so
-- this works the same for an installed directory, a zip, or Modkit's
-- virtual validation FS). Plain require() only resolves the engine's own
-- src.* module tree, not a mod's own sibling files.
--
-- Previously had a debug.getinfo(1, "S").source + loadfile() fallback
-- for a plain filesystem entry point. Both debug and loadfile were
-- removed from the mod sandbox in gen1recomp's Aug 2026 mod-sandboxing
-- release ("grandmas kitchen") -- debug.getinfo alone threw
-- unconditionally at load time (attempt to index global 'debug', a nil
-- value), which is the fatal error this fix addresses. mod:read() was
-- always the primary path and is confirmed sufficient on its own per
-- this same comment's own claim above, so the fallback is dropped
-- rather than reworked -- there is no sandboxed replacement for
-- loadfile's own-arbitrary-path use, only for mod:read's own-folder one.
local function loadSibling(mod, filename)
  local body, readErr = mod:read(filename)
  assert(body, readErr)
  local chunk, err = loadstring(body, "@" .. mod.path .. "/" .. filename)
  assert(chunk, err)
  return chunk()
end

local TYPE_ID_TRANSLATION = {
  PSYCHIC = "PSYCHIC_TYPE",
}

local function engineTypeId(pbsType)
  return TYPE_ID_TRANSLATION[pbsType] or pbsType
end

-- [g9-battle-engine-beta] Party-menu icon art (TEMPLATE_FOR_TYPE,
-- SPECIAL_TEMPLATE, iconPath, installBigPartyIcons/Gen2) removed entirely
-- -- this fork owns combat only. See g9-battle-engine for icon/sprite art.

-- =============================================================================
-- Phase 2: movepool effects
-- =============================================================================
-- Flinch/confusion chance read LIVE off national_dex's own moveById
-- record on every landed hit (see installMovepoolEffects's own header) --
-- no per-chance move_effect registration of any kind anymore, just the
-- one unconditional GALAR_TRAP_EFFECT.
--
-- BUGFIX (this session, reported: "flinched pokemon can't act ever
-- again"): the original version of Flinch/Confuse registered
-- kind="secondary" with a single-argument `run = function(ctx)` -- no
-- normalize(a,b,c) bridge, the same gotcha modern_hazards.lua's own
-- header already documents for Rapid Spin: Gen 2's dispatch calls ANY
-- move_effects record with a `.run` field via `handler(self, attacker,
-- defender, def, moveId, sureHit)` -- SIX positional args, not one ctx
-- table -- BEFORE its own damage path, and returns immediately
-- (gen2/Battle.lua:1533-1538). A single-param `function(ctx)` silently
-- captures `self` (the raw Battle instance, which has no `.target` field
-- -- confirmed, zero `self.target =` assignments anywhere in gen2/
-- Battle.lua) as `ctx`, so `ctx.target` was always nil on Gen 2: the
-- roll never ran, the flag never got set, AND -- because the dispatch
-- returns unconditionally right after calling the handler -- the move
-- dealt NO DAMAGE and skipped whatever turn-resolution bookkeeping
-- normally follows a landed hit. That is almost certainly the actual
-- shape of the reported bug (a Gen 2 target that got hit by a flinch-
-- chance move never receiving its "turn completed" step reads as
-- "can't act ever again," not literally as an uncleared flag), on top
-- of silently killing damage for every flinch/confuse-chance move on
-- Gen 2.
--
-- Fixed the same way every other on-hit side effect in this project
-- already is (Rapid Spin, Knock Off, Covet, ... -- combat/
-- modern_hazards.lua, combat/modern_items.lua): kind="full" with NO run
-- field (so damage always proceeds normally on both engines), and the
-- actual roll+flag-set moves to a separate battle.damage_dealt listener,
-- confirmed identical payload shape on both engines and fired only
-- AFTER a landed, non-immune hit.
--
-- Storage location differs by generation -- confirmed directly against
-- this mod's OWN existing gigantamax/gimmick_dynamax.lua
-- clearDynamaxVolatiles, which already draws this exact distinction:
-- Gen 1 keeps flinched/confusedTurns directly on the battler
-- (who.flinched, who.confusedTurns); Gen 2 keeps the equivalents inside
-- battle:volatile(mon) (vol.flinched, vol.confuseCount -- note the
-- different field NAME too, not just location, matching gen2/Battle
-- .lua's own read site at line ~912/921). Writing target.flinched = true
-- unconditionally (the original bug) never touched the place Gen 2
-- actually reads.
--
-- GALAR_TRAP_EFFECT is NOT touched here -- same underlying dispatch bug,
-- but Gen 2 already has a real, separate, WORKING native trap mechanic
-- (mon.wrapCount / EFFECT_TRAP_TARGET, gen2/Battle.lua:1769-1785,
-- confirmed this session) that this effect was never wired to and would
-- need a deliberate design call (route through wrapCount vs. keep its
-- own state), not a same-shape patch. Left as a separately flagged,
-- known-broken-on-Gen-2 issue.
--
-- Duration values (confusedTurns, 2-5 turns) are reasonable
-- approximations, not confirmed exact -- this engine's own real formula
-- was not found in any reference source; unchanged by this fix.
--
-- FULLY MIGRATED off moves_new.lua (2026-08-26): flinch/confusion chance
-- read LIVE from national_dex's own moveById record (flinchChance,
-- ailment=="confusion"+ailmentChance) for EVERY landed hit, not from a
-- precomputed table built from this mod's own static data. This also
-- means no per-move GALAR_FLINCH_EFFECT_<chance>/GALAR_CONFUSE_EFFECT_
-- <chance> registration is needed at all anymore -- the listener reacts
-- to the real move id directly, independent of whatever that move's own
-- registered `effect` field says. Strictly more general than the old
-- approach too: it now applies to EVERY move in national_dex's full
-- roster (any native Gen 1/2 move with a real flinch/confusion chance,
-- not just the 179 this mod's own moves_new.lua happened to cover).
local function installMovepoolEffects(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById,
    "installMovepoolEffects: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById

  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target
    local user = ev and ev.user
    local damage = ev and ev.damage
    if not (battle and moveId and target) then return end
    local ok, info = pcall(moveById, moveId)
    if not (ok and info) then return end
    local flinchChance = (info.flinchChance or 0) > 0 and info.flinchChance or nil
    local confuseChance = (info.ailment == "confusion" and (info.ailmentChance or 0) > 0)
      and info.ailmentChance or nil
    -- Generic secondary status (poison/burn/paralysis/freeze/sleep) --
    -- confusion is handled separately above (a volatile, not a major
    -- status). Always opponent-directed: no real move self-inflicts a
    -- status via its own secondary chance. STANDARD_AILMENT maps
    -- national_dex's own canonical spelling to each engine's real,
    -- confirmed status-string convention (see this mod's own
    -- NATIONAL_DEX_API_REFERENCE.md -- Gen 1 codes vs Gen 2 words,
    -- neither matching national_dex's own spelling directly).
    -- toxic (badly poisoned) is its own real status, not "poison" --
    -- Gen 1's StatusRegistry.inflict takes it via opts.toxic=true on the
    -- SAME "PSN" code (confirmed real, src/battle/Status.lua's own PSN
    -- record: `if opts.toxic then target.toxicCounter = 1 ... end`);
    -- Gen 2 has a genuinely separate status word for it ("toxic", not
    -- "poison" -- confirmed real, gen2/Battle.lua's own Battle.STATUSES
    -- .toxic). isToxic below threads that through.
    local STANDARD_AILMENT = {
      poison = { gen1 = "PSN", gen2 = "poison" }, burn = { gen1 = "BRN", gen2 = "burn" },
      paralysis = { gen1 = "PAR", gen2 = "paralyze" }, freeze = { gen1 = "FRZ", gen2 = "freeze" },
      sleep = { gen1 = "SLP", gen2 = "sleep" },
      toxic = { gen1 = "PSN", gen2 = "toxic", isToxic = true },
    }
    -- TOXIC's own real move record carries ailment="poison" (confirmed
    -- via direct national_dex dump), not "toxic" -- a real, confirmed
    -- data inconsistency against Malignant Chain's own correctly-tagged
    -- "toxic" ailment for the identical real mechanic -- so this one
    -- move id needs an explicit override rather than trusting the
    -- ailment field alone. Every other move's own real ailment value is
    -- still read live, unconditionally.
    local ailmentKey = (moveId == "TOXIC") and "toxic" or info.ailment
    local ailmentCodes = STANDARD_AILMENT[ailmentKey]
    local ailmentChance = (ailmentCodes and (info.ailmentChance or 0) > 0) and info.ailmentChance
      or (ailmentCodes and moveId == "TOXIC" and 100) or nil
    -- Generic secondary stat change. Direction (self vs opponent) has no
    -- structured field at all in national_dex's own data -- a real,
    -- confirmed PokeAPI limitation, not something this mod failed to
    -- read -- but the prose `shortEffect` text reliably says "the
    -- user's"/"the target's" (verified against Overheat/Superpower/
    -- Close Combat/Fleur Cannon/V-create -- self -- vs Acid/Mud Shot --
    -- opponent -- before writing this), so direction is still read live,
    -- not hardcoded per move.
    local STAT_KEY = { attack = "attack", defense = "defense",
      ["special-attack"] = "spa", ["special-defense"] = "spd",
      speed = "speed", accuracy = "accuracy", evasion = "evasion" }
    local statChance = ((info.statChance or 0) > 0 and #(info.statChanges or {}) > 0)
      and info.statChance or nil
    -- national_dex's own prose text uses a curly apostrophe (U+2019),
    -- not a straight one -- confirmed by direct dump, not assumed --
    -- checked for both defensively in case a future shard mixes them.
    local function saysUsers(text)
      return text:find("user's") ~= nil or text:find("user\226\128\153s") ~= nil
    end
    local function saysTargets(text)
      return text:find("target's") ~= nil or text:find("target\226\128\153s") ~= nil
    end
    local shortEffect = info.shortEffect or ""
    local statSelfDirected = statChance and saysUsers(shortEffect) and not saysTargets(shortEffect)
    -- Generic drain/recoil -- positive `drain` heals the user a fraction
    -- of the damage just dealt, negative is recoil (self-damage). Gated
    -- on this gen's own real modeled flag (gen1EffectModeled/
    -- gen2EffectModeled): when true, this move's real behavior already
    -- runs natively for THIS gen (Absorb/Mega Drain/Giga Drain/Leech
    -- Life/Dream Eater's own drain included) -- applying again here
    -- would double it. When false, nothing else handles it for this gen
    -- (confirmed: no remaining mod-patched drain/recoil effect exists
    -- anywhere in this codebase as of this migration -- the two that
    -- used to, GALAR_RECOIL_EFFECT_3/2 and GALAR_DRAIN_EFFECT_75, are
    -- retired, see combat/modern_movepool_damage.lua's own header).
    local drainPercent = (info.drain or 0) ~= 0 and info.drain or nil
    if not (flinchChance or confuseChance or ailmentChance or statChance or drainPercent) then return end
    local applyOk, err = pcall(function()
      -- isGen2Battle is looked up lazily (not hoisted to a local at the
      -- top of this file) because installMovepoolEffects runs during
      -- Phase 2, before combat/modern_combat.lua (Phase 6+) has loaded
      -- and populated mod.exports -- this closure only runs later,
      -- during a real battle, by which point every mod has finished
      -- loading.
      local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)
      -- RNG convention genuinely differs by engine, confirmed directly:
      -- Gen 1's battle.rng(a, b) (BattleState.lua:596, `love.math.random
      -- (a, b)`) is inclusive-both-ends. Gen 2 has NO .rng field at all
      -- (confirmed, zero matches in gen2/Battle.lua) -- its real
      -- primitive is battle.random(n), a single-arg roll returning
      -- 0..n-1 (gen2/Battle.lua:220 `self.random = opts.random or
      -- function(n) return rand(nil, n) end`), and every native Gen 2
      -- percent-chance check uses exactly `rand(self.random, 100) <
      -- chance` (e.g. gen2/Battle.lua:1815/1821/1850) -- battle.random
      -- (100) < chance here mirrors that same, real, established idiom.
      local function percentRoll(chance)
        if gen2 then return battle.random(100) < chance end
        return battle.rng(1, 100) <= chance
      end
      local function rangeRoll(lo, hi)
        if gen2 then return lo + battle.random(hi - lo + 1) end
        return battle.rng(lo, hi)
      end
      -- Phase 3a (abilities/engine/status_immunity.lua): INNERFOCUS/
      -- OWNTEMPO gates, looked up lazily for the same reason isGen2Battle
      -- above is -- this closure only runs during a real battle, by which
      -- point status_immunity.lua has finished loading regardless of
      -- install order.
      local hasStatusImmunity = mod.exports.hasStatusImmunity
      -- Real, confirmed double-application guard, added after an initial
      -- pass missed it (caught by direct review, not assumed correct):
      -- this gen's own real modeled flag. When true, THIS move's real
      -- effect already runs natively for THIS gen (a real EFFECT_X_HIT-
      -- style handler, confirmed by the earlier move-completeness audit
      -- excluding exactly these moves from needing new work at all) --
      -- ailment/statChange must NOT also roll independently on top of
      -- that, the same reasoning already applied to drain below. Flinch/
      -- confusion are exempt from this gate on purpose: national_dex's
      -- own gen1Effect/gen2Effect ids never model flinch/confusion chance
      -- at all (confirmed earlier this session, the original reason this
      -- listener was built generic in the first place), so there is
      -- nothing native for those two to collide with.
      local modeled = gen2 and info.gen2EffectModeled or ((not gen2) and info.gen1EffectModeled)
      -- Phase 7 (prevent bucket): Sheer Force/Shield Dust -- both real
      -- "the secondary/extra effects of [these] moves never happen"
      -- abilities, and this generic listener (flinch/ailment/confuse/
      -- stat-change) is the exact real definition of "secondary effect"
      -- for every move that reaches it -- not drain/recoil, which is the
      -- move's own primary mechanic, not a chance-based extra (real Sheer
      -- Force, confirmed via Showdown source, leaves draining moves'
      -- drain untouched). Sheer Force is the attacking side (its own
      -- separate +30% power boost is a damage_dealt_multiplier-kind
      -- effect, a different phase's own bucket, not built here); Shield
      -- Dust is the defending side.
      local abilityIdOf = mod.exports.abilityIdOf
      local secondarySuppressed = abilityIdOf
        and ((user and abilityIdOf(user) == "SHEERFORCE") or (target and abilityIdOf(target) == "SHIELDDUST"))
      if secondarySuppressed then
        flinchChance, confuseChance, ailmentChance, statChance = nil, nil, nil, nil
      end
      -- Phase 8: Serene Grace -- doubles the SAME real secondary-effect
      -- pool this listener already owns (flinch/ailment/confuse/stat-
      -- change), the attacking side, capped at 100 so a doubled 60%+
      -- chance never rolls against an out-of-range denominator. Real,
      -- confirmed exclusion (Showdown source + national_dex's own notes):
      -- Secret Power's own terrain-dependent secondary is explicitly
      -- unaffected -- excluded by move id rather than guessed silently
      -- correct.
      if abilityIdOf and user and moveId ~= "SECRETPOWER" and abilityIdOf(user) == "SERENEGRACE" then
        if flinchChance then flinchChance = math.min(100, flinchChance * 2) end
        if confuseChance then confuseChance = math.min(100, confuseChance * 2) end
        if ailmentChance then ailmentChance = math.min(100, ailmentChance * 2) end
        if statChance then statChance = math.min(100, statChance * 2) end
      end
      if flinchChance and percentRoll(flinchChance)
          and not (hasStatusImmunity and hasStatusImmunity(target, "flinch", battle)) then
        if gen2 then
          battle:volatile(target).flinched = true
        else
          target.flinched = true
        end
      end
      if confuseChance and percentRoll(confuseChance)
          and not (hasStatusImmunity and hasStatusImmunity(target, "confusion", battle)) then
        if gen2 then
          local vol = battle:volatile(target)
          if not vol.confuseCount then vol.confuseCount = rangeRoll(2, 5) end
        elseif not target.confusedTurns then
          target.confusedTurns = rangeRoll(2, 5)
        end
      end
      -- Generic secondary status (poison/burn/paralysis/freeze/sleep) --
      -- always opponent-directed, reuses the exact primitives Phase 0/3
      -- already made generic and dual-gen-aware: StatusRegistry.inflict
      -- (Gen 1, with opts.secondary+opts.moveType so its own real
      -- same-type-can't-be-secondary-inflicted rule applies for free)
      -- and Battle:applyStatus (Gen 2). Both already respect ability
      -- immunity (status_immunity.lua wraps these same functions) and
      -- the one-status-at-a-time rule natively -- nothing to re-check
      -- here.
      if ailmentChance and not modeled and percentRoll(ailmentChance) then
        if gen2 then
          battle:applyStatus(target, ailmentCodes.gen2, moveId)
        else
          local StatusRegistry = require("src.battle.StatusRegistry")
          StatusRegistry.inflict(battle, target, ailmentCodes.gen1,
            { secondary = true, moveType = info.type, source = moveId, toxic = ailmentCodes.isToxic })
        end
      end
      -- Generic secondary stat change -- reuses changeStage (Phase 0's
      -- own shared primitive, Contrary/Simple-aware since Phase 8) for
      -- attack/defense/spa/spd, and Gen 2's native
      -- changeStageAgainstMist for speed/accuracy/evasion -- the exact
      -- same NATIVE_STATS split abilities/engine/switchin_stat_change
      -- .lua's own header already documents and this file's own
      -- STAT_KEY mirrors. Silently skipped (not guessed) when the prose
      -- text names neither "user's" nor "target's", or names both --
      -- a wrong direction is a real gameplay bug, an unbuilt effect is
      -- just an honest gap.
      if statChance and not modeled and percentRoll(statChance) and statSelfDirected ~= nil then
        local changeStage = mod.exports.changeStage
        -- NATIVE_STATS (speed/accuracy/evasion): combat/modern_combat
        -- .lua's own changeStage store (confirmed by direct read of its
        -- ensureStageState) only ever tracks attack/defense/spa/spd --
        -- writing "speed" through it would be recorded nowhere anything
        -- reads back, a silent no-op. Gen 2 has a real, proven route for
        -- these three (Battle:changeStageAgainstMist, the same one
        -- abilities/engine/switchin_stat_change.lua's own NATIVE_STATS
        -- branch already uses).
        --
        -- Gen 1 CLOSED (2026-08-27) -- an earlier pass here claimed no
        -- confirmed store existed; that was wrong, found by checking the
        -- wrong file (BattleState.lua) and stopping instead of also
        -- checking Damage.lua, the actual accuracy-formula consumer.
        -- Real, confirmed, direct field: `mon.stages.speed`/`.accuracy`/
        -- `.evasion` (src/battle/Damage.lua:88-94 reads
        -- `attacker.stages.speed`, :121-122 reads `attacker.stages
        -- .accuracy`/`defender.stages.evasion` directly) -- a plain,
        -- clamped -6..6 number per mon, exactly the same shape Gen 2's
        -- own native stage table already is. Written directly here,
        -- gated by the same boss-fight statsDrop protection changeStage
        -- itself already checks (bossStatsDropBlocked) -- Mist's own
        -- check is NOT replicated here (that logic is private to
        -- modern_combat.lua's own closure, not exported, and Mist
        -- blocking a hostile speed/accuracy/evasion drop specifically is
        -- a narrower edge case than the boss-protection rule) -- a
        -- smaller, named simplification, not a silent gap.
        local NATIVE_STATS = { speed = true, accuracy = true, evasion = true }
        for _, sc in ipairs(info.statChanges or {}) do
          local statKey = STAT_KEY[sc.stat]
          if statKey and sc.change and changeStage then
            local who = statSelfDirected and user or target
            local fromEnemy = not statSelfDirected
            if who then
              if NATIVE_STATS[statKey] then
                -- Real Foresight/Miracle Eye rule: blocks the TARGET's
                -- own future evasion raises while active (the "current
                -- boost reset to 0" half lives in combat/modern_status_
                -- volatiles.lua's own Foresight/Miracle Eye handlers).
                local evasionBlocked = statKey == "evasion" and sc.change > 0
                  and (who.foresighted or who.miracleEyed)
                -- Phase 7 (prevent bucket): Clear Body/Full Metal Body/
                -- White Smoke/Hyper Cutter/Big Pecks/Keen Eye/Mind's Eye/
                -- Flower Veil's real "can't have this stat lowered by an
                -- opponent" family, same shared definition Gen 2's own
                -- changeStageAgainstMist wrap (stage_change_transform.lua)
                -- already uses -- Gen 1 has no Mist-equivalent check to
                -- piggyback on here (see this block's own pre-existing
                -- note above), so this is checked directly.
                local statDropBlockedByAbility = mod.exports.statDropBlockedByAbility
                local abilityBlocked = fromEnemy and sc.change < 0 and statDropBlockedByAbility
                  and statDropBlockedByAbility(who, gen2, statKey)
                if evasionBlocked or abilityBlocked then
                  -- no-op
                elseif gen2 then
                  battle:changeStageAgainstMist(user, who, statKey, sc.change)
                elseif not (mod.exports.bossStatsDropBlocked and mod.exports.bossStatsDropBlocked(battle, who, sc.change)) then
                  who.stages = who.stages or {}
                  who.stages[statKey] = math.max(-6, math.min(6, (who.stages[statKey] or 0) + sc.change))
                end
              else
                changeStage(battle, who, statKey, sc.change, fromEnemy, gen2)
              end
            end
          end
        end
      end
      if drainPercent and (damage or 0) > 0 and user then
        -- Reuses the SAME `modeled` flag computed once above (flinch's
        -- own comment) rather than a second, redundant computation.
        if not modeled then
          local m = user.mon or user
          local maxHp = m.stats and m.stats.hp
          local amount = math.max(1, math.floor(damage * math.abs(drainPercent) / 100))
          if drainPercent > 0 then
            if maxHp then m.hp = math.min(maxHp, (m.hp or 0) + amount) end
          else
            -- Real recoil immunities: Rock Head (blocks recoil
            -- unconditionally, no other effect to this ability) and
            -- Magic Guard (abilities/engine/damage_immunity.lua's own
            -- indirect-damage scope, extended here -- recoil isn't
            -- direct move damage to an opponent, the same real rule
            -- that already covers status residual/sand chip).
            local abilityIdOf = mod.exports.abilityIdOf
            local userAbility = abilityIdOf and abilityIdOf(user)
            if userAbility ~= "ROCKHEAD" and userAbility ~= "MAGICGUARD" then
              m.hp = math.max(0, (m.hp or 0) - amount)
            end
          end
        end
      end
    end)
    if not applyOk then
      mod.log:warn("galar_gmax_dex: installMovepoolEffects: flinch/confuse failed: %s",
        tostring(err))
    end
  end)

  -- Unconditional registration, genuinely independent of any per-move
  -- data -- only SANDTOMB's own live record gets patched to point at it
  -- (see wireMovepoolSubEffects below).
  -- Real Gen 2 dispatch bug fixed 2026-08-27, same shape as the flinch/
  -- confuse bug this file's own header already documents: a single-
  -- param `function(ctx)` silently captured Gen 2's own raw Battle
  -- instance (which has no `.target`) as `ctx`, so this never actually
  -- did anything on Gen 2. Bridged through normalize() now, same as
  -- every other dual-gen handler in this file.
  --
  -- Gen 2 half REBUILT ENTIRELY, not just bridged: confirmed by direct
  -- source read that Gen 2 already has a complete, real, working trap
  -- mechanic of its own (Battle:tickWrap -- real 1/16 max HP chip per
  -- turn, switchLocked/runRefused pins, breakTrapsOnSend cleanup -- ALL
  -- already implemented and consumed correctly, gen2/Battle.lua). Its
  -- own trigger (`def.effect == "EFFECT_TRAP_TARGET"`) never fires for
  -- these moves because national_dex's own base registry assigns them
  -- plain EFFECT_NORMAL_HIT instead (confirmed directly, registry_gen2
  -- .lua) -- rather than fight that string match, this writes the exact
  -- same real fields Battle:tickWrap and friends already consume
  -- (`wrapCount`/`wrapMove`/`wrapMoveId`, via battle:volatile) directly.
  -- We decide a target is now trapped; the engine's own pre-existing
  -- machinery does everything downstream of that decision, exactly the
  -- "native only executes what it's told" split this session's own
  -- combat/modern_status_turn_loss.lua already established.
  mod.content.move_effects:register("GALAR_TRAP_EFFECT", {
    kind = "secondary",
    -- normalize(a,b,c) deliberately drops the move id (confirmed by
    -- direct read of its own definition -- returns only battle/user/
    -- target/gen2), and Gen 2's real six-positional-arg dispatch shape
    -- (self, attacker, defender, def, moveId, sureHit) means a
    -- 3-param function signature silently never receives arg 5 at
    -- all -- both real traps for this handler, not guessed around.
    run = function(a, b, c, d, e)
      -- Read off mod.exports HERE rather than named bare. `normalize` is a
      -- local inside combat/modern_combat.lua, published as
      -- mod.exports.normalize -- so a bare `normalize(...)` in this file is a
      -- GLOBAL read: nil, and it raises the moment a GALAR_TRAP_EFFECT move is
      -- used. Reported from a real battle as "main.lua:492: attempt to call
      -- global 'normalize' (a nil value)". Every other consumer already does
      -- this (combat/modern_hazards.lua:94); this one site was missed. Read
      -- inside `run` so no load-order assumption is made.
      local normalize = mod.exports.normalize
      if not normalize then return {} end
      local n = normalize(a, b, c)
      if not n.target then return {} end
      local moveId = n.gen2 and e or (a.move and a.move.id)
      if n.gen2 then
        local state = n.battle:volatile(n.target)
        if not state.wrapCount and (state.substitute or 0) <= 0 then
          state.wrapCount = n.battle.random(2) + 4 -- 4-5 turns, real modern duration
          state.wrapMove = moveId
          state.wrapMoveId = moveId
        end
      else
        -- Approximated duration (4-5 turns); real Gen 1 Bind/Wrap use a
        -- per-turn release roll this engine's equivalent wasn't confirmed.
        n.target.trappingTurns = n.battle.rng(4, 5)
        n.target.boundTurns = n.target.trappingTurns
        n.target.trapMove = moveId
      end
      return {}
    end,
  })
end

-- bypassesProtect (Feint's own flag, Phase 3 of the move-effect
-- completion pipeline) -- a plain data flag, not schema-declared on
-- R.moves (Schemas.lua:824-846) but preserved anyway by that schema's
-- own record-mode leniency (same "unknown top-level fields ride through"
-- behavior modern_movepool_damage.lua's header already confirmed for
-- R.move_effects); modern_combat_protect.lua's battle.damage hook reads
-- it off the live move record, patched on by wireMovepoolSubEffects
-- below rather than registered as part of a full move entry. national_
-- dex has no equivalent field -- this mod invented it, it belongs here
-- as a small hardcoded map, not a file.
local BYPASSES_PROTECT = { FEINT = true }

-- Every move whose real custom effect handler (registered elsewhere in
-- this mod, with REAL run/afterDamage/charge logic -- verified one by
-- one, not assumed) depends on ITS OWN move record's `effect` field
-- actually pointing at that handler. This table is EXACTLY what used to
-- be carried silently by moves_new.lua's own per-move `effect` field,
-- copied onto the live record by the old generic wireMovepoolSubEffects
-- loop -- removing that loop without this table would have silently
-- broken every one of these (confirmed real regression caught and fixed
-- in the same session it was introduced: re-audited every mod.content.
-- move_effects:register call in this codebase after the fact, checked
-- each one's actual body for real logic vs. an empty {kind="full"}
-- stub-audit marker -- the empty ones (Acrobatics/Venoshock/Assurance/
-- Heat Crash/Heavy Slam/Power Trip/Flail/Endeavor/Twister/Blizzard/
-- Rapid Spin) need NO patch at all: their real mechanic runs
-- unconditionally off ctx.move.id inside a registerDamageModifier entry
-- or a battle.damage_dealt listener, never through this field -- and two
-- more (GGD_MAXGUARD_EFFECT, GMAX_CUDDLE_EFFECT) belong to moves this mod
-- or gmax_moves.lua already registers/patches directly, with no
-- national_dex record at all, so they were never in scope here).
local CUSTOM_EFFECT_PATCH = {
  -- main.lua's own GALAR_TRAP_EFFECT (installMovepoolEffects above) --
  -- every real trap move (ailment="trap" on national_dex), not just
  -- Sand Tomb, now that the Gen 2 dispatch bug is fixed
  -- Metal Burst. combat/modern_movepool_counter.lua registers
  -- GALAR_METALBURST_EFFECT in full and nothing pointed at it, so the move
  -- kept national_dex's EFFECT_NORMAL_HIT and the handler was unreachable.
  METALBURST = "GALAR_METALBURST_EFFECT",
  SANDTOMB = "GALAR_TRAP_EFFECT",
  BIND = "GALAR_TRAP_EFFECT",
  WRAP = "GALAR_TRAP_EFFECT",
  CLAMP = "GALAR_TRAP_EFFECT",
  FIRE_SPIN = "GALAR_TRAP_EFFECT",
  WHIRLPOOL = "GALAR_TRAP_EFFECT",
  THUNDERCAGE = "GALAR_TRAP_EFFECT",
  SNAPTRAP = "GALAR_TRAP_EFFECT",
  MAGMASTORM = "GALAR_TRAP_EFFECT",
  INFESTATION = "GALAR_TRAP_EFFECT",
  -- combat/modern_status_volatiles.lua -- real Showdown-verified bespoke
  -- volatiles (Leech Seed, Nightmare, Ingrain, Yawn, Disable, Embargo,
  -- Heal Block/Psychic Noise, Throat Chop, Perish Song, Foresight/
  -- Miracle Eye/Odor Sleuth, Smack Down/Thousand Arrows, Telekinesis,
  -- Uproar). Odor Sleuth reuses Foresight's own real mechanic (Ghost-
  -- immunity negation); Thousand Arrows reuses Smack Down's (Flying-
  -- immunity-to-Ground negation) -- both genuinely share the identical
  -- real effect, confirmed against national_dex's own prose text, not
  -- duplicated code.
  LEECH_SEED = "GALAR_LEECHSEED_EFFECT",
  SAPPYSEED = "GALAR_LEECHSEED_EFFECT",
  NIGHTMARE = "GALAR_NIGHTMARE_EFFECT",
  INGRAIN = "GALAR_INGRAIN_EFFECT",
  YAWN = "GALAR_YAWN_EFFECT",
  DISABLE = "GALAR_DISABLE_EFFECT",
  EMBARGO = "GALAR_EMBARGO_EFFECT",
  HEALBLOCK = "GALAR_HEALBLOCK_EFFECT",
  PSYCHICNOISE = "GALAR_PSYCHICNOISE_EFFECT",
  THROATCHOP = "GALAR_THROATCHOP_EFFECT",
  PERISHSONG = "GALAR_PERISHSONG_EFFECT",
  FORESIGHT = "GALAR_FORESIGHT_EFFECT",
  ODORSLEUTH = "GALAR_FORESIGHT_EFFECT",
  MIRACLEEYE = "GALAR_MIRACLEEYE_EFFECT",
  SMACKDOWN = "GALAR_SMACKDOWN_EFFECT",
  THOUSANDARROWS = "GALAR_SMACKDOWN_EFFECT",
  TELEKINESIS = "GALAR_TELEKINESIS_EFFECT",
  UPROAR = "GALAR_UPROAR_EFFECT",
  ELECTROSHOT = "GALAR_ELECTROSHOT_EFFECT",
  STOCKPILE = "GALAR_STOCKPILE_EFFECT",
  SWALLOW = "GALAR_SWALLOW_EFFECT",
  -- SPITUP is NOT here -- it needs no custom .effect at all, wired
  -- entirely through registerPowerOverride + a battle.damage_dealt
  -- listener instead (see combat/modern_status_volatiles.lua's own
  -- Stockpile/Swallow/Spit Up section for why).
  -- Raging Fury shares Outrage's own exact real mechanic (2-3 turn
  -- rampage lock, then self-confuse) -- reused directly, not
  -- duplicated. Same Gen 2 honest gap as Outrage itself (see combat/
  -- modern_movepool_damage.lua's own header for why).
  RAGINGFURY = "GALAR_OUTRAGE_EFFECT",
  -- combat/modern_weather.lua
  RAINDANCE = "GALAR_RAINDANCE_EFFECT",
  SUNNYDAY = "GALAR_SUNNYDAY_EFFECT",
  SANDSTORM = "GALAR_SANDSTORM_EFFECT",
  SNOWSCAPE = "GALAR_SNOWSCAPE_EFFECT",
  SOLARBEAM = "GALAR_SOLARBEAM_EFFECT",
  -- combat/modern_movepool_damage.lua
  -- DRAININGKISS's own GALAR_DRAIN_EFFECT_75 patch retired 2026-08-27 --
  -- superseded by installGenericDrainRecoil's live `drain` field read
  -- (see this file's own header), which is also dual-gen-correct where
  -- that one wasn't.
  HEALPULSE = "GALAR_HEALPULSE_EFFECT",
  LIFEDEW = "GALAR_LIFEDEW_EFFECT",
  SYNTHESIS = "GALAR_SYNTHESIS_EFFECT",
  MOONLIGHT = "GALAR_MOONLIGHT_EFFECT",
  MORNINGSUN = "GALAR_MORNINGSUN_EFFECT",
  SHOREUP = "GALAR_SHOREUP_EFFECT",
  FLORALHEALING = "GALAR_FLORALHEALING_EFFECT",
  PURIFY = "GALAR_PURIFY_EFFECT",
  LUNARBLESSING = "GALAR_LUNARBLESSING_EFFECT",
  PAINSPLIT = "GALAR_PAINSPLIT_EFFECT",
  BOUNCE = "GALAR_BOUNCE_EFFECT",
  OUTRAGE = "GALAR_OUTRAGE_EFFECT",
  ETERNABEAM = "GALAR_ETERNABEAM_EFFECT",
  -- combat/modern_movepool_status.lua
  FLATTER = "GMAX_FLATTER_EFFECT",
  SWAGGER = "GMAX_SWAGGER_EFFECT",
  -- combat/modern_status_effects.lua
  ATTRACT = "GMAX_ATTRACT_EFFECT",
  TAUNT = "GMAX_TAUNT_EFFECT",
  TORMENT = "GMAX_TORMENT_EFFECT",
  -- combat/modern_hazards.lua
  STEALTHROCK = "GALAR_STEALTHROCK_EFFECT",
  TOXICSPIKES = "GALAR_TOXICSPIKES_EFFECT",
  STICKYWEB = "GALAR_STICKYWEB_EFFECT",
  -- combat/modern_ability_change_moves.lua
  SKILLSWAP = "GALAR_SKILLSWAP_EFFECT",
  WORRYSEED = "GALAR_WORRYSEED_EFFECT",
  ENTRAINMENT = "GALAR_ENTRAINMENT_EFFECT",
  GASTROACID = "GALAR_GASTROACID_EFFECT",
  -- combat/modern_movepool_stages.lua -- primary() (pure status moves)
  AROMATICMIST = "GMAX_AROMATICMIST_EFFECT",
  BULKUP = "GMAX_BULKUP_EFFECT",
  CALMMIND = "GMAX_CALMMIND_EFFECT",
  CHARGE = "GMAX_CHARGE_EFFECT",
  CHARM = "GMAX_CHARM_EFFECT",
  COIL = "GMAX_COIL_EFFECT",
  CONFIDE = "GMAX_CONFIDE_EFFECT",
  COSMICPOWER = "GMAX_COSMICPOWER_EFFECT",
  COTTONGUARD = "GMAX_COTTONGUARD_EFFECT",
  COTTONSPORE = "GMAX_COTTONSPORE_EFFECT",
  DECORATE = "GMAX_DECORATE_EFFECT",
  DRAGONDANCE = "GMAX_DRAGONDANCE_EFFECT",
  EERIEIMPULSE = "GMAX_EERIEIMPULSE_EFFECT",
  FAKETEARS = "GMAX_FAKETEARS_EFFECT",
  HONECLAWS = "GMAX_HONECLAWS_EFFECT",
  IRONDEFENSE = "GMAX_IRONDEFENSE_EFFECT",
  METALSOUND = "GMAX_METALSOUND_EFFECT",
  NASTYPLOT = "GMAX_NASTYPLOT_EFFECT",
  NOBLEROAR = "GMAX_NOBLEROAR_EFFECT",
  PLAYNICE = "GMAX_PLAYNICE_EFFECT",
  ROCKPOLISH = "GMAX_ROCKPOLISH_EFFECT",
  SCARYFACE = "GMAX_SCARYFACE_EFFECT",
  SHIFTGEAR = "GMAX_SHIFTGEAR_EFFECT",
  SWEETSCENT = "GMAX_SWEETSCENT_EFFECT",
  TARSHOT = "GMAX_TARSHOT_EFFECT",
  TEARFULLOOK = "GMAX_TEARFULLOOK_EFFECT",
  -- combat/modern_movepool_stages.lua -- secondary() (damaging moves)
  ACIDSPRAY = "GMAX_ACIDSPRAY_EFFECT",
  ANCIENTPOWER = "GMAX_ANCIENTPOWER_EFFECT",
  APPLEACID = "GMAX_APPLEACID_EFFECT",
  BREAKINGSWIPE = "GMAX_BREAKINGSWIPE_EFFECT",
  BUGBUZZ = "GMAX_BUGBUZZ_EFFECT",
  BULLDOZE = "GMAX_BULLDOZE_EFFECT",
  CLOSECOMBAT = "GMAX_CLOSECOMBAT_EFFECT",
  CRUNCH = "GMAX_CRUNCH_EFFECT",
  DRUMBEATING = "GMAX_DRUMBEATING_EFFECT",
  ENERGYBALL = "GMAX_ENERGYBALL_EFFECT",
  FIRELASH = "GMAX_FIRELASH_EFFECT",
  FLAMECHARGE = "GMAX_FLAMECHARGE_EFFECT",
  FLASHCANNON = "GMAX_FLASHCANNON_EFFECT",
  GRAVAPPLE = "GMAX_GRAVAPPLE_EFFECT",
  HAMMERARM = "GMAX_HAMMERARM_EFFECT",
  LEAFSTORM = "GMAX_LEAFSTORM_EFFECT",
  LEAFTORNADO = "GMAX_LEAFTORNADO_EFFECT",
  LIQUIDATION = "GMAX_LIQUIDATION_EFFECT",
  LUNGE = "GMAX_LUNGE_EFFECT",
  METALCLAW = "GMAX_METALCLAW_EFFECT",
  PLAYROUGH = "GMAX_PLAYROUGH_EFFECT",
  POWERUPPUNCH = "GMAX_POWERUPPUNCH_EFFECT",
  RAZORSHELL = "GMAX_RAZORSHELL_EFFECT",
  ROCKSMASH = "GMAX_ROCKSMASH_EFFECT",
  ROCKTOMB = "GMAX_ROCKTOMB_EFFECT",
  SPIRITBREAK = "GMAX_SPIRITBREAK_EFFECT",
  STEELWING = "GMAX_STEELWING_EFFECT",
  STRUGGLEBUG = "GMAX_STRUGGLEBUG_EFFECT",
  SUPERPOWER = "GMAX_SUPERPOWER_EFFECT",
  -- combat/modern_movepool_stages.lua -- Clear Smog (its own registration)
  CLEARSMOG = "GMAX_CLEARSMOG_EFFECT",
}

-- Completeness, read ENTIRELY from national_dex's own modern fields --
-- no hardcoded per-move exemption list at all (confirmed directly:
-- Feint and Round, the two moves that used to need a special-cased
-- exemption under the old PBS-functionCode model, both come back
-- completely empty on every one of these fields already -- neither
-- "bypasses Protect" nor "doubles-only ally bonus" is a secondary-effect
-- TYPE national_dex's schema tracks at all, so there was never anything
-- here for them to be stubbed on in the first place).
--
-- flinchChance / confusion / multiHit are each handled GENERICALLY for
-- every move in the whole roster now (installMovepoolEffects reads
-- flinch/confusion live; this file's own wireMovepoolSubEffects derives
-- and patches multiHit live) -- a move needing ONLY one of those three
-- is complete with zero registration of its own. Anything else (a real
-- non-confusion ailment, a stat change, drain, healing, or a multi-turn
-- charge) needs a REAL custom effect actually registered and patched
-- onto the live record by some file in this mod -- confirmed this
-- already happens for e.g. Protect/Detect (modern_combat_protect.lua)
-- and Trick Room (combat/trick_room.lua), both picked up here for free
-- since this reads the LIVE record, not a static snapshot.
local function isMoveDataComplete(liveRecord)
  if not liveRecord then return false end
  local hasAilment = liveRecord.ailment and liveRecord.ailment ~= "none"
  local isConfusion = liveRecord.ailment == "confusion"
  local hasStatChange = #(liveRecord.statChanges or {}) > 0
  local hasDrain = (liveRecord.drain or 0) ~= 0
  local hasHeal = (liveRecord.healing or 0) ~= 0
  local hasMultiTurn = (liveRecord.minTurns or 0) > 0 or (liveRecord.maxTurns or 0) > 0
  local needsCustomEngineering = (hasAilment and not isConfusion)
    or hasStatChange or hasDrain or hasHeal or hasMultiTurn
  if not needsCustomEngineering then return true end
  return liveRecord.effect ~= nil and liveRecord.effect ~= "NO_ADDITIONAL_EFFECT"
end

-- STANDING RULE, explicit and repeated user instruction: this mod NEVER
-- registers a move, full stop -- no mod.content.moves:register/:override
-- call writes base move data (name/type/category/power/accuracy/pp/
-- priority) anywhere in this codebase. national_dex is the sole source
-- for that data, unconditionally, for its entire roster. Confirmed
-- exhaustively (2026-08-26, diffed every id, not sampled): all 179 ids
-- this mod used to register already exist as full, real records in
-- national_dex's own catalogue (764 total moves) -- registering/
-- overriding them was pure, harmful duplication of data national_dex
-- already owns, not a gap-filling measure.
--
-- moves_new.lua ITSELF is gone too (2026-08-26) -- its last three
-- legitimate (non-registration) uses are all replaced with live national
-- _dex reads: flinch/confuse chance (installMovepoolEffects above),
-- highCrit/multiHit (derived below from national_dex's own critRate/
-- minHits/maxHits), and move-completeness classification (isMoveDataComplete
-- above, reading national_dex's own modern fields directly). Applied
-- uniformly across national_dex's ENTIRE roster now, not just the 179
-- ids this mod's own old data file happened to cover.
local function wireMovepoolSubEffects(mod)
  installMovepoolEffects(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById
      and nationalDex.exports.listMoves,
    "wireMovepoolSubEffects: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local patched = 0
  for _, id in ipairs(nationalDex.exports.listMoves()) do
    if mod.content.moves:get(id) then
      local ok, info = pcall(moveById, id)
      if ok and info then
        local patch = {}
        if BYPASSES_PROTECT[id] then patch.bypassesProtect = true end
        if CUSTOM_EFFECT_PATCH[id] then patch.effect = CUSTOM_EFFECT_PATCH[id] end
        -- critRate is the number of +1 crit-stage bumps the move itself
        -- grants (confirmed: Cross Poison critRate=1, a real high-crit
        -- move; Axe Kick/Baddy Bad critRate=0, ordinary) -- >=1 maps onto
        -- this engine's own boolean highCrit field.
        if (info.critRate or 0) >= 1 then patch.highCrit = true end
        -- multiHit: a fixed count (minHits==maxHits, e.g. Double Hit's
        -- 2-2) is just that count twice; the real 2-5 range (Bullet Seed,
        -- Rock Blast, Double Iron Bash) is the well-known, generation-
        -- independent 3/8·3/8·1/8·1/8 weighted distribution -- confirmed
        -- directly against national_dex's OWN effect text for these
        -- moves ("Has a 3/8 chance each to hit 2 or 3 times, and a 1/8
        -- chance each to hit 4 or 5 times"), not guessed. Any other
        -- min/max combination this roster doesn't currently use falls
        -- through to an unweighted flat range rather than silently
        -- guessing a distribution with no confirmed source.
        local minHits, maxHits = info.minHits or 0, info.maxHits or 0
        if minHits > 0 and maxHits > 0 then
          if minHits == maxHits then
            patch.multiHit = { minHits, minHits }
          elseif minHits == 2 and maxHits == 5 then
            patch.multiHit = { 2, 2, 2, 3, 3, 3, 4, 5 }
          else
            local range = {}
            for n = minHits, maxHits do range[#range + 1] = n end
            patch.multiHit = range
          end
        end
        if next(patch) then
          mod.content.moves:patch(id, patch)
          patched = patched + 1
        end
      end
    end
  end
  return patched
end

-- =============================================================================
-- Phase 3: Gigantamax moves -- fed to dynamax, not registered here
-- =============================================================================
-- dynamax now owns both the actual move registration (mod.content.moves)
-- and the species -> move Gigantamax substitution rule (computeMaxMoveId's
-- own type-matching check) -- see dynamax/main.lua's "Gigantamax moves"
-- section. This mod's job is just handing over its own data: the 32 new
-- moves' definitions (gmax_moves.lua) and which species uses which move
-- (gmax_data.lua's own gmaxMove field, already used for dex text/height
-- too). Registration is skipped entirely if dynamax isn't loaded -- the
-- whole Gigantamax mechanic is inert without it either way, same
-- reasoning installGmaxAssetPacks's own reapplyGmaxSprites already
-- applies to sprites below.
local function installGigantamaxMoves(mod, gmaxMovesData, gmaxData)
  local dynamaxMod = mod.find("dynamax")
  if not (dynamaxMod and dynamaxMod.exports and dynamaxMod.exports.registerGmaxMoves
      and dynamaxMod.exports.setGigantamaxMove) then
    mod.log:warn("galar_gmax_dex: dynamax not loaded; Gigantamax moves (and the whole Gigantamax mechanic) are inactive")
    return 0
  end
  -- gmax_moves.lua keeps PBS's own type spelling too (e.g. "PSYCHIC" for
  -- GMAXGRAVITAS) -- translated into a fresh table here before handing it
  -- to dynamax, the same engineTypeId helper applied elsewhere, rather
  -- than mutating the loaded gmax_moves.lua table in place. Gigantamax
  -- moves are genuinely this mod's own invented content -- no national_dex
  -- equivalent exists for them at all, so registering them here (unlike
  -- the Phase 2 sub-effect-only approach above) is correct, not a
  -- violation of the "never register a move" rule, which is specifically
  -- about moves national_dex already owns. This mod is responsible for
  -- feeding dynamax engine-ready
  -- data; dynamax trusts what it's given rather than knowing about
  -- PBS-specific naming quirks itself.
  local translatedMoves = {}
  for id, def in pairs(gmaxMovesData) do
    local entry = {}
    for field, value in pairs(def) do entry[field] = value end
    entry.type = engineTypeId(entry.type)
    translatedMoves[id] = entry
  end
  local registered = dynamaxMod.exports.registerGmaxMoves(translatedMoves)
  for _, id in ipairs(gmaxData.order) do
    local species = gmaxData.species[id]
    if species and species.gmaxMove then
      dynamaxMod.exports.setGigantamaxMove(id, species.gmaxMove)
    end
  end
  return registered
end

-- =============================================================================
-- Phase 3: Gigantamax sprite asset packs -- toggle + extension point
-- =============================================================================
-- No real Gigantamax art exists yet (Phase 4 only ever slices each
-- species' *normal* battle sprite from Pokemon_Back_Front -- a distinct,
-- oversized Gigantamax look is a separate, later asset drop, same as the
-- real games treat it). This mod owns WHICH art feeds dynamax's own
-- mod.exports.setDynamaxSprite(speciesId, def) -- confirmed real,
-- documented in dynamax's main.lua -- not how it's drawn or animated.
--
--   - Built-in "placeholder" behavior (always available, needs no pack
--     registered): do nothing, so the species keeps its ordinary battle
--     sprite while Dynamaxed. Dynamax's own scale-up animation already
--     reads correctly with this -- only the unique look is missing.
--   - mod.exports.registerGmaxAssetPack(packId, resolverFn) lets a future,
--     separate graphics mod plug in real art with zero changes to this
--     mod's own code. resolverFn(speciesId) returns a sprite def (the
--     same {image=...} / {frames=...,fps=...} shape setDynamaxSprite
--     already accepts) or nil to fall through to the placeholder.
--   - mod.exports.setActiveGmaxAssetPack(packId) selects which registered
--     pack is live.
--   - The "gmax_custom_art" option is the actual toggle: off always forces
--     the placeholder, regardless of what's registered -- e.g. to compare
--     against a pack, or while a pack is still a known-broken draft.
-- Since dynamax's own DYNAMAX_SPRITES table is a one-time write (read
-- directly off mon.species at battle time, not re-checked against
-- options live), toggling either the option or the active pack only
-- takes effect after reapplyGmaxSprites runs again -- called once at
-- load and again on save.loaded, the same re-apply-on-load convention
-- gorochu.lua's own migrate() uses.
-- [g9-battle-engine-beta] Gigantamax/battle sprite asset-pack toggles
-- (installGmaxAssetPacks, installSpriteAssetPacks, installRestingScaleOverride,
-- installGen2BattlePicPositionFix) removed entirely -- this fork owns combat
-- only, no sprite/asset handling of any kind. See g9-battle-engine for those.

-- =============================================================================
-- Move name display -- shrink-to-fit for names longer than the classic box
-- =============================================================================
-- Real English move names run longer than the short Spanish text this pack
-- used before (e.g. "High Horsepower", "Psychic Terrain" are 14-15 chars),
-- past the classic move-list box's confirmed ~13-character budget: the box
-- is drawn at tile (4,12) 16x6, names start at column 6 (x=48), confirmed
-- via src/battle/BattleState.lua's real drawTextArea -- moveSelect branch
-- (`Font.draw(def.name, 48, 96 + i * 8)`), with the box's own right border
-- at column 19 (x=152), leaving 104px = 13 chars at the native 8px-per-char
-- fixed-width font.
--
-- This is base-engine UI code, not something this mod owns, so it's
-- reached the same way dynamax's own mod reaches drawBattlerPic: wrap the
-- real method (BattleState:drawTextArea, confirmed a real top-level method,
-- not an inline block), call the vanilla draw first, then -- only for
-- names that would actually overflow -- erase just that row's text cell
-- (the same "paint white first" idiom drawTextArea's own moveSelect branch
-- already uses for the border-cell redraws) and redraw at a shrunk scale.
-- Font.draw/Font.drawCode take no scale parameter (confirmed: plain
-- love.graphics.draw(image, quad, x, y) calls) -- scaling is done via a
-- love.graphics transform anchored at the text's own top-left, not a
-- per-glyph change, so short names that already fit are left at the
-- vanilla draw's normal size untouched.

-- [g9-battle-engine-beta] installPlayerSpriteSide/installSpriteAnimation
-- (battle sprite animation), installOverworldSpriteProvider/
-- installWildDrawOverride (overworld sprites), installBigPartyIcons/
-- installBigPartyIconsGen2 (sprite-based party icons) removed entirely --
-- same reason as above.

-- [g9-battle-engine-beta] These three were originally declared right
-- next to installBigPartyIcons/Gen2 (sprite-based party icons, removed)
-- purely by file-position coincidence -- they belong to
-- installMoveNameDisplay below, not to anything sprite-related, and got
-- swept up in that removal by mistake (confirmed live: "attempt to
-- perform arithmetic on global 'MOVE_LIST_TEXT_RIGHT' (a nil value)" on
-- boot). Restored here, unchanged from the source mod.
local MOVE_LIST_TEXT_X = 48
local MOVE_LIST_TEXT_RIGHT = 152 -- box's own right border column (19*8)
local MOVE_LIST_ROW_HEIGHT = 8

local function installMoveNameDisplay(mod)
  local BattleState = require("src.battle.BattleState")
  if BattleState.__galarMoveNameWrapped then return end
  BattleState.__galarMoveNameWrapped = true

  local Font = require("src.render.Font")
  local availableWidth = MOVE_LIST_TEXT_RIGHT - MOVE_LIST_TEXT_X

  local vanillaDrawTextArea = BattleState.drawTextArea
  function BattleState:drawTextArea()
    local result = vanillaDrawTextArea(self)
    if self.phase == "moveSelect" and self.player and self.player.curMoves then
      for i, mv in ipairs(self.player.curMoves) do
        local def = mv.id and self.data.moves[mv.id]
        local name = def and def.name
        if name then
          local width = Font.width(name)
          if width > availableWidth then
            local y = 96 + i * MOVE_LIST_ROW_HEIGHT
            -- erase the vanilla-drawn full-size text before redrawing
            -- smaller, same "wipe to box white" idiom used elsewhere in
            -- this exact function for the border-cell redraws
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("fill", MOVE_LIST_TEXT_X, y,
              availableWidth, MOVE_LIST_ROW_HEIGHT)
            love.graphics.setColor(0, 0, 0, 1)
            local scale = availableWidth / width
            love.graphics.push()
            love.graphics.translate(MOVE_LIST_TEXT_X, y)
            love.graphics.scale(scale, scale)
            Font.draw(name, 0, 0)
            love.graphics.pop()
          end
        end
      end
    end
    return result
  end
end

local HAPPINESS_EVOLUTION_THRESHOLD = 220
local HAPPINESS_BATTLE_GAIN = 3

local function installHappinessEvolution(mod)
  mod.content.evolution_methods:register("HAPPINESS", {
    check = function(_, mon, _, trigger)
      return trigger.kind == "levelup"
        and (mon.happiness or 0) >= HAPPINESS_EVOLUTION_THRESHOLD
    end,
    describe = function() return "High friendship" end,
  })

  -- Approximated: any completed battle nudges the active mon's happiness
  -- up a little, regardless of outcome. The real games track many finer
  -- deltas (steps walked, level-ups, berries, fainting) this engine has
  -- no equivalent hooks for.
  mod.events:on("battle.ended", function(ev)
    local mon = ev and ev.battle and ev.battle.player and ev.battle.player.mon
    if mon and mon.hp and mon.hp > 0 then
      mon.happiness = math.min(255, (mon.happiness or 70) + HAPPINESS_BATTLE_GAIN)
    end
  end)
end

-- Generalizes gorochu.lua's installItemEffect (one item -> one species) to
-- any number of item ids. On use, looks up the target's *live* registered
-- species evolutions table (not our own local copy) for a method="ITEM"
-- entry matching the used item, so later patches to that table (by this
-- mod or another) are respected.
local function installEvolutionItems(mod, itemIds)
  local ok, ItemEffects = pcall(require, "src.inventory.ItemEffects")
  if not (ok and ItemEffects and type(ItemEffects.use) == "function"
      and type(ItemEffects.needsTarget) == "function") then
    mod.log:warn("galar_gmax_dex: could not hook ItemEffects; new evolution items will not function")
    return false
  end
  local key = "__galarGmaxDexEvolutionItems"
  local holder = rawget(ItemEffects, key)
  if holder then
    for id in pairs(itemIds) do holder.items[id] = true end
    return true
  end
  holder = {
    items = {},
    use = ItemEffects.use,
    needsTarget = ItemEffects.needsTarget,
  }
  for id in pairs(itemIds) do holder.items[id] = true end

  ItemEffects.needsTarget = function(itemId, itemDef)
    if holder.items[itemId] then return true end
    return holder.needsTarget(itemId, itemDef)
  end
  ItemEffects.use = function(data, save, itemId, target, battle, ...)
    if not holder.items[itemId] then
      return holder.use(data, save, itemId, target, battle, ...)
    end
    if battle then
      return "failed", { "It can't be used\nin battle." }
    end
    local species = target and data and data.pokemon
      and data.pokemon[target.species]
    local matchedSpecies
    for _, evo in ipairs(species and species.evolutions or {}) do
      if evo.method == "ITEM" and evo.item == itemId then
        matchedSpecies = evo.species
        break
      end
    end
    if not matchedSpecies then
      return "failed", { "It won't have\nany effect." }
    end
    return "consumed", nil, { evolveTo = matchedSpecies }
  end
  rawset(ItemEffects, key, holder)
  return true
end

-- Converts the derived-field pair postgame_species.lua also uses:
-- heightM -> {heightFt, heightIn}, weightKg -> weight (decipounds, the
-- same *22.0462262 scaling that formula uses so a Bulbasaur-style 6.9kg
-- entry lands on the same "15.2" display value convention).
local function derivedHeightWeight(heightM, weightKg)
  local totalInches = math.floor((heightM or 0) * 39.3700787 + 0.5)
  return {
    heightFt = math.floor(totalInches / 12),
    heightIn = totalInches % 12,
    weight = math.floor((weightKg or 10) * 22.0462262 + 0.5),
  }
end

-- =============================================================================
-- W1/F1 tuning + test options (Start menu -> MOD MENUS -> G9 DEX)
-- =============================================================================
-- Testing W1 (wild spawns) and F1 (follower) meant editing constants and
-- restarting every time, with no way to compare behaviors live.
--
-- Two real, separately-confirmed pieces, read from actual source rather
-- than assumed (an earlier version of this guessed at a "ui.options.rows"
-- hook that isn't what either of these files actually use):
--
-- 1. mod.options:define(schema) is the entire data-layer integration.
--    ManagerState:schemaFor/buildOptionRows/setOption
--    (src/mods/ManagerState.lua ~865-958) is a complete, already-working
--    generic options screen for ANY mod with a defined schema -- display,
--    cycling, persistence (game.save.options.modOptions + loader.
--    modOptions), and it emits "mod.options_changed" itself on every
--    change, the exact event overworld_spawns.lua/overworld_followers.lua
--    listen for. gen1_modern_ui's own settings work this exact same way
--    (its main.lua: mod.options:define(optionSchema), nothing else for
--    UI) -- confirmed by reading it directly.
--
-- 2. The Start Menu entry point: gen1_modern_ui's main.lua (~2632-2735)
--    wraps "ui.start_menu.items" at priority 90 and groups every item any
--    OTHER mod added via that SAME hook under one "MOD MENUS" row --
--    plain object-identity diffing against what was already in `items`
--    before its own wrapper ran, no mod-id field required. FOLLOWERS_EX's
--    own Start Menu shortcut ("FLL EX") uses this identical hook at
--    default priority. So the fix is: add ONE item to "ui.start_menu.
--    items" at default priority (below gen1_modern_ui's 90, so our
--    addition is already present by the time its next(...) call collects
--    everything to group) that opens the native mod list -- gen1_modern_ui
--    then automatically folds it under MOD MENUS for us; no custom
--    grouping/menu code needed on this side at all.
--
-- [g9-battle-engine-beta] The classic_encounters suppression hook
-- (mod.hooks:wrap("encounter.roll", ...)) is removed here -- it existed
-- ONLY to stop the vanilla step-based encounter roll from double-firing
-- alongside g9-battle-engine's own W1 visible wild-spawn engine, which
-- this fork doesn't have. Without W1 present, that hook would suppress
-- EVERY classic encounter by default (classic_encounters itself defaults
-- OFF) -- an active regression, not harmless dead code, so it's removed
-- rather than left in place. Vanilla's own step-based encounter roll is
-- untouched here and remains fully active.
local function installDebugOptions(mod)
  local schema = loadSibling(mod, "options.lua")
  mod.options:define(schema)

  -- Default priority (below gen1_modern_ui's 90) is load-bearing, not
  -- incidental: it puts this item in the list gen1_modern_ui's own
  -- next(game, items) call collects, so its grouping pass sees and folds
  -- it under MOD MENUS. Opens the native mod list (same call the Start
  -- Menu's own built-in "MODS" row makes, src/ui/StartMenu.lua ~108) --
  -- jumps straight to THIS mod's own options screen instead of landing on
  -- the general mod list first. Confirmed both pieces directly rather than
  -- assumed: StateStack:push(state) calls state:enter() automatically
  -- (src/core/StateStack.lua ~18), and ManagerState:enter() never touches
  -- self.screen (only self.status/self.byId/self.banner, ManagerState.lua
  -- ~182-198) -- so pushing first, then calling :openOptions, is safe and
  -- does not get clobbered by enter()'s own setup. openOptions/schemaFor/
  -- buildOptionRows only ever read m.id off the stand-in table (m.path is
  -- only a fallback for a mod that never called mod.options:define,
  -- ManagerState.lua ~847-863) and the options screen's own :draw()
  -- (~1176-1185) never references self.currentMod at all -- so a minimal
  -- { id = mod.id } is everything openOptions needs here.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    items = next(game, items) or items
    table.insert(items, {
      label = "G9 DEX",
      onSelect = function()
        local ManagerState = require("src.mods.ManagerState")
        local state = ManagerState.new(game)
        game.stack:push(state)
        state:openOptions({ id = mod.id })
      end,
    })
    return items
  end)

  mod.log:info("galar_gmax_dex: options registered (Start -> MOD MENUS -> G9 DEX -> our options directly)")
end

return function(mod)
  -- src.pokemon.ModernStats / src.pokemon.MoveCategory used to be files
  -- hand-added directly to the engine tree (src/pokemon/), because a
  -- normal require("src.pokemon.X") only ever resolves against the
  -- running game's OWN src/ tree, never a mod's sandboxed folder -- that
  -- worked fine against this project's own dev checkout, but meant the
  -- mod silently depended on an engine fork: a stock/release build (no
  -- hand-added files) crashed on the very first require(), confirmed live
  -- ("module 'src.pokemon.ModernStats' not found"). The engine tree is
  -- meant to stay stock -- both files now live here instead
  -- (engine_modern_stats.lua/engine_move_category.lua).
  --
  -- Previously registered into package.preload so every existing
  -- require("src.pokemon.ModernStats")/require("src.pokemon.MoveCategory")
  -- call site kept working unchanged. package (all of it, not just
  -- io/os/love.filesystem) was removed from the mod sandbox in
  -- gen1recomp's Aug 2026 mod-sandboxing release ("grandmas kitchen") --
  -- confirmed every consumer of these two require() calls is one of this
  -- mod's OWN files (grepped the whole tree: no other mod or engine call
  -- site references src.pokemon.ModernStats/MoveCategory), so this is
  -- fully within our control to rewire. Replacement channel is
  -- mod.exports -- the sandbox announcement's own explicit replacement
  -- for "passing data to another mod/file through a global" -- loaded
  -- once here (singleton, matching require()'s real caching semantics)
  -- and read directly by every consumer instead of require(...).
  mod.exports.ModernStats = mod.exports.ModernStats or loadSibling(mod, "stats/engine_modern_stats.lua")
  mod.exports.MoveCategory = mod.exports.MoveCategory or loadSibling(mod, "combat/engine_move_category.lua")
  local installSaveScrub = loadSibling(mod, "stats/save_scrub.lua")
  installSaveScrub(mod)

  -- Wild encounters get fresh, DV-independent modern IVs/EVs the moment
  -- BattleState.newWild builds them -- see wild_modern_ivs.lua for the
  -- full reasoning. Needs ModernStats resolvable (package.preload just
  -- above), so this stays right after installSaveScrub.
  local installWildModernIvs = loadSibling(mod, "stats/wild_modern_ivs.lua")
  installWildModernIvs(mod)

  -- Trainer mons: an open provider API other mods can feed real modern
  -- stats through (mod.exports.registerTrainerStatsProvider), falling back
  -- to the DV/stat-exp conversion system when none is registered for a
  -- given mon -- see trainer_modern_stats.lua for the full reasoning.
  local installTrainerModernStats = loadSibling(mod, "stats/trainer_modern_stats.lua")
  installTrainerModernStats(mod)

  -- Gen 2 (Gold): a separate implementation from the two installs above --
  -- no shared BattleState/newWild/newTrainer with Gen 1, see
  -- gen2_modern_stats.lua's own header. Uses
  -- mod.exports.resolveTrainerSpec, just registered above, so this stays
  -- after installTrainerModernStats.
  local installGen2ModernStats = loadSibling(mod, "stats/gen2_modern_stats.lua")
  installGen2ModernStats(mod)

  -- Gym leader / Elite Four / Champion / Red team replacement -- TEMPORARILY
  -- DISABLED, explicit user report: "after this update we are getting
  -- silent crash" immediately following this feature landing. Files left
  -- in place (overworld/gym_trainer_teams.lua, overworld/
  -- install_gym_trainer_teams.lua) -- this is the call site alone,
  -- commented out rather than deleted, so re-enabling once the actual
  -- crash cause is found is a one-line change, not a rebuild.
  local gymTrainerTeams = loadSibling(mod, "overworld/gym_trainer_teams.lua")
  local installGymTrainerTeams = loadSibling(mod, "overworld/install_gym_trainer_teams.lua")
  installGymTrainerTeams(mod, gymTrainerTeams)

  -- EV yield on faint: every mon that gains EXP from a KO gains that
  -- species' national_dex EV yield too -- listens to battle.exp_gained,
  -- same event name/compatible payload in both generations, so one file
  -- covers both -- see ev_yield_on_faint.lua for the full reasoning. Purely
  -- event-driven (no install-time species/state dependency beyond
  -- ModernStats being resolvable), so ordering relative to the installs
  -- above doesn't matter beyond happening after package.preload is set up.
  local installEvYieldOnFaint = loadSibling(mod, "stats/ev_yield_on_faint.lua")
  installEvYieldOnFaint(mod)

  -- Confirmed real, previously-unfixed bug: national_dex never sets
  -- baseExp on any species it registers, which floors EXP gain to
  -- exactly 1 for every affected species (src/battle/Experience.lua's
  -- own math.max(1, exp) floor) -- see reapply_national_dex_stats.lua's
  -- own header for the full root-cause chain and the BST-approximation
  -- this patches in. Runs here (species should already be registered by
  -- national_dex, a hard dependency, by the time GalarGmaxDex's own
  -- main.lua executes) and re-syncs on save.loaded/mod.options_changed,
  -- explicit user instruction: "we need a reapply stats too."
  local realBaseExpData = loadSibling(mod, "stats/base_exp_data.lua")
  local installReapplyNationalDexStats = loadSibling(mod, "stats/reapply_national_dex_stats.lua")
  installReapplyNationalDexStats(mod, realBaseExpData)

  -- Registered unconditionally, before the species-registration gate
  -- below: the options screen is a completely independent concern from
  -- whether modern_type_framework happens to be loaded, and should still
  -- work (or at least still exist to explain what's off) even if that
  -- check fails.
  installDebugOptions(mod)

  if not mod.content.type_chart:get("STEEL") then
    mod.log:error("galar_gmax_dex: modern_type_framework is not loaded; skipping species registration")
    return false
  end

  -- Phase 1 species registration used to carry its own stat/type/dex data
  -- AND actually register each species (species_data.lua's species={}
  -- table, 51 species, via mod.content.pokemon:register). Both retired --
  -- explicit user correction: this mod is a CONSUMER of species
  -- existence, never a co-registrant. National_dex (or the base engine,
  -- for the cart-native roster) is who actually calls :register() for a
  -- given species; calling it a second time throws ("pokemon already
  -- registered: BULBASAUR", confirmed live -- src/mods/Registry.lua's
  -- register is create-only, no upsert). species_data.lua's other two
  -- roles split into their own files: custom_sprite_species.lua (the pure
  -- id list, for the sprite-fallback-safety phase below, which has
  -- nothing to do with where stat data comes from) and
  -- species_evolutions.lua (evolutions + evolution items, for all 1025
  -- national-dex species -- confirmed national_dex's own `evolutions`
  -- field is unpopulated for every record, see that file's own header --
  -- so THIS is the one thing worth patching onto whatever's already
  -- registered, native or national_dex-sourced alike).
  local speciesEvolutions = loadSibling(mod, "species/species_evolutions.lua")

  installHappinessEvolution(mod)
  -- Must run before the evolutions-patching loop below actually matters
  -- (schema cross-validation is a post-merge pass, but registering these
  -- alongside HAPPINESS keeps every evolution_methods registration in one
  -- place) -- see exotic_evolution_stubs.lua for why this is required for
  -- the mod to load at all, not just nice-to-have.
  local installExoticEvolutionStubs = loadSibling(mod, "species/exotic_evolution_stubs.lua")
  installExoticEvolutionStubs(mod)

  local itemIds = {}
  for id, def in pairs(speciesEvolutions.items) do
    mod.content.items:register(id, {
      id = id, name = def.name, price = def.price or 0,
      tossable = true, needsTarget = true,
    })
    itemIds[id] = true
  end
  installEvolutionItems(mod, itemIds)

  -- Patch evolutions onto whatever's already registered -- skip (not
  -- error) a species nothing has registered yet, e.g. national_dex
  -- absent/disabled and the species isn't cart-native either. Gracefully
  -- degraded, not a hard requirement: unlike the old registration-owning
  -- design, this mod no longer needs national_dex present to do SOMETHING
  -- useful (evolutions for the native roster still patch in fine).
  --
  -- Per-ROW filtering too, not just per-species: an evolution row's own
  -- `species` (the evolution TARGET) is just as much an f.id("pokemon")
  -- reference as this loop's own source-species check -- Schemas.lua's
  -- crossValidate treats an unresolved target exactly the same as an
  -- unresolved evolution_methods id (a blocking "unresolved reference"
  -- error, confirmed live). A source species can be perfectly real and
  -- registered while one of ITS evolution targets isn't yet (e.g.
  -- national_dex not installed, or a newer species it doesn't cover) --
  -- dropping only the unresolvable ROW keeps every other real evolution
  -- on that same mon intact instead of losing the whole species' list
  -- over one bad branch.
  -- Gen 2's pokemon record schema (Schemas.lua's gen2Fields for R.pokemon)
  -- shapes an evolution row differently from Gen 1's -- confirmed by
  -- reading it directly: the target-species key is `into`, not `species`
  -- (Gen 1's key), and `species` isn't a recognized field at all under
  -- Gen 2 -- patching a Gen1-shaped row onto a Gen 2 boot fails schema
  -- validation ("unknown field" + "missing required field (pokemon id)"
  -- for every affected species, confirmed live). `method`/`level`/`item`
  -- are the same key names both shapes; Gen 2 also has optional
  -- `time`/`comparison` fields this pass has no source data for, so
  -- they're simply omitted (same "phased honest, not silently wrong"
  -- treatment already used for the 23 custom items/exotic methods).
  local GameVersion = require("src.core.GameVersion")
  local isGen2Boot = GameVersion.generation(GameVersion.get()) == 2

  local patchedEvolutions, skippedSpecies, droppedRows = 0, 0, 0
  for id, evoList in pairs(speciesEvolutions.evolutions) do
    if mod.content.pokemon:get(id) then
      local resolvable = {}
      for _, evo in ipairs(evoList) do
        if mod.content.pokemon:get(evo.species) then
          if isGen2Boot then
            resolvable[#resolvable + 1] = {
              method = evo.method, into = evo.species,
              level = evo.level, item = evo.item,
            }
          else
            resolvable[#resolvable + 1] = evo
          end
        else
          droppedRows = droppedRows + 1
        end
      end
      mod.content.pokemon:patch(id, { evolutions = resolvable })
      patchedEvolutions = patchedEvolutions + 1
    else
      skippedSpecies = skippedSpecies + 1
    end
  end
  mod.log:info(
    "galar_gmax_dex: patched evolutions onto %d species (%d species skipped unregistered, %d rows dropped for an unregistered target) (Phase 1)",
    patchedEvolutions, skippedSpecies, droppedRows)

  -- ------- Phase 2: movepool sub-effects -------
  -- national_dex registers every one of these moves' base data already --
  -- this mod never does (see wireMovepoolSubEffects's own header for the
  -- full standing rule). No moves_new.lua load at all anymore -- everything
  -- below reads national_dex live.
  local movesPatched = wireMovepoolSubEffects(mod)
  -- Exported so combat/learnset_ownership.lua's usability gate reads the
  -- SAME completeness check wireMovepoolSubEffects itself uses, not a second
  -- copy -- confirmed drift bug caught this session: learnset_ownership.lua
  -- had its own independent inline duplicate of this logic, which would
  -- have kept blocking moves from ever being taught even after they became
  -- genuinely complete.
  mod.exports.isMoveDataComplete = isMoveDataComplete

  -- Learnset ownership switch (explicit user decision, this session):
  -- national_dex is the canonical "what can this species learn" source
  -- (its unfiltered movesFull/movesByMethod, not its own filtered
  -- learnset/levelMoves field -- see learnset_ownership.lua's own header
  -- for why that field's filtering can't reflect this mod's own
  -- completeness); GalarGmaxDex gates USABILITY on its own move-effect
  -- completeness, now judged entirely off the live registry (see
  -- learnset_ownership.lua's own header for the full migration).
  local installLearnsetOwnership = loadSibling(mod, "combat/learnset_ownership.lua")
  local learnsetOwnership = installLearnsetOwnership(mod)
  learnsetOwnership.reapplyLearnsets()
  -- TEMPORARILY DISABLED (2026-08-19, spawn-diagnostic session): same
  -- "content is frozen after load" crash as reapplySpritePacks above --
  -- reapplyLearnsets also calls mod.content.pokemon:patch(...) from a
  -- post-boot event. Disabled to stop log noise while diagnosing spawn
  -- hook compatibility; re-enable afterward, real fix still needed.
  -- mod.events:on("save.loaded", learnsetOwnership.reapplyLearnsets)
  -- mod.events:on("mod.options_changed", learnsetOwnership.reapplyLearnsets)

  mod.log:info("galar_gmax_dex: patched sub-effects onto %d moves (Phase 2, no base data registered)", movesPatched)

  -- ------- Phase 3: Gigantamax moves and forms -------
  -- TEMPORARILY DISABLED (2026-08-20, explicit user instruction, removing
  -- all custom combat scenes): Gigantamax's only in-battle trigger was
  -- GimmickRing (mod.exports.gimmickRing, defined by the now-removed
  -- combat/custom_battle_scene.lua) -- with that gone, registering these
  -- moves fed nothing reachable. Kept on disk, not deleted
  -- (gigantamax/gmax_moves.lua, gigantamax/gmax_data.lua,
  -- gigantamax/gimmick_dynamax.lua all still exist unchanged) -- explicit
  -- user instruction: keep this logic and the HP-increase handling
  -- (inside gimmick_dynamax.lua) until proper hooks into whichever other
  -- mod now owns Gigantamax activation are defined, then re-enable both
  -- this block and the Phase 14 install below.
  -- local gmaxMovesData = loadSibling(mod, "gigantamax/gmax_moves.lua")
  -- local gmaxData = loadSibling(mod, "gigantamax/gmax_data.lua")
  -- mod.exports.gmaxData = gmaxData
  -- local gmaxMovesRegistered = installGigantamaxMoves(mod, gmaxMovesData, gmaxData)
  -- mod.log:info(
  --   "galar_gmax_dex: fed %d Gigantamax moves to dynamax for %d/%d species (Phase 3)",
  --   gmaxMovesRegistered, #gmaxData.order, #gmaxData.order)

  -- Dynamax Level / Gigantamax Factor: storage + public API only (explicit
  -- user scope, 2026-08-20) -- no activation, no HP writes, no ownership
  -- of battle_forms's own gimmick mechanics. gmax_data.lua's roster is
  -- loaded fresh here (independent of the disabled block above) purely
  -- as the base-species reference for isGigantamaxEligibleSpecies. See
  -- gigantamax/dynamax_state.lua's own header for the full grounding.
  local gmaxDataForDynamaxState = loadSibling(mod, "gigantamax/gmax_data.lua")
  local installDynamaxState = loadSibling(mod, "gigantamax/dynamax_state.lua")
  installDynamaxState(mod, gmaxDataForDynamaxState)

  -- Tera Type: storage + public API only, same scope discipline as Dynamax
  -- Level/Gigantamax Factor above -- no activation, battle_forms's own
  -- Terastallization menu/item/registry slot untouched. See
  -- gigantamax/tera_state.lua's own header for the full grounding.
  local installTeraState = loadSibling(mod, "gigantamax/tera_state.lua")
  installTeraState(mod)

  -- [g9-battle-engine-beta] Phase 3's Gigantamax ASSET pack call, Phase 4
  -- (battle sprites), Phase 5 (overworld sprite provider + party icons),
  -- Phase 6 (wild encounter area placements), Phase 7 (native overworld
  -- wild-spawn engine), Phase 8 (native follower engine), and Phase 9
  -- (Dramatic Shape voxel billboards) all removed entirely -- this fork owns
  -- combat only. See g9-battle-engine for asset/spawn/sprite/follower handling.

  installMoveNameDisplay(mod)

  -- ------- Phase 10: modern stats display -------
  -- Sp.Atk/Sp.Def, IVs, EVs, Nature, Ability, Item, Tera Type, Dynamax
  -- Level, and per-move category, added to the party submenu ("MODERN")
  -- and to gen1_modern_ui's own modern-styled list rendering when that mod
  -- is present. See modern_stats_screen.lua's own header for why this is
  -- a party-submenu screen rather than a SummaryMenu edit.
  local installModernStatsScreen = loadSibling(mod, "stats/modern_stats_screen.lua")
  installModernStatsScreen(mod)

  -- Dev Tools > DEVSTATS: an opt-in ("dev_tools" option, OFF by default)
  -- diagnostic party-submenu screen -- ability/nature/Tera/Dynamax/
  -- Gigantamax Factor/real combat stats plus full EV/IV distribution.
  -- Loaded right after modern_stats_screen.lua since it reuses the exact
  -- same wide-UI-surface technique and mod.exports.ModernStats -- see
  -- stats/dev_stats_screen.lua's own header for the full grounding.
  local installDevStatsScreen = loadSibling(mod, "stats/dev_stats_screen.lua")
  installDevStatsScreen(mod)

  -- ------- Phase 11: native modern combat formulas -------
  -- Replaces an earlier live Showdown/Node bridge (TCP process + async
  -- protocol) that proved fragile across a real process boundary (a
  -- respawn race, a missing "end" message handler, a Node-side team-
  -- validation crash). This ports the FORMULAS natively into Lua instead,
  -- hooked through the engine's own sanctioned battle.damage extension
  -- point (BattleState:computeDamage, src/battle/BattleState.lua) rather
  -- than a raw monkey-patch -- no async wait state, no protocol, no
  -- separate process. Applies to every battle (wild, trainer, link), not
  -- just wild ones.
  -- Gen 9 Showdown-accurate primitives (damage/heal/faint/status/
  -- volatile/boost/chance) -- the verb set the new national_dex-
  -- moveById-driven combat mode is built from. No dependency on
  -- anything else in this file; loaded first among the combat/ installs
  -- purely so anything after it can consume mod.exports.ShowdownPrimitives.
  -- See combat/showdown_primitives.lua's own header for the full
  -- grounding and the standing "native stays the storage substrate,
  -- this owns the rules" split.
  local installShowdownPrimitives = loadSibling(mod, "combat/showdown_primitives.lua")
  installShowdownPrimitives(mod)

  -- The generic "this mon's own side switches out mid-move, battle keeps
  -- going" primitive (mod.exports.requestSwitch/registerSwitchAiChooser) --
  -- U-turn/Volt Switch are its first real callers (below), but per explicit
  -- user decision this is meant to be the same entrypoint any future
  -- ability/item effect reaches for too. No dependency on anything else in
  -- this file; loaded here, right after ShowdownPrimitives, so every real
  -- move-effect install below can consume mod.exports.requestSwitch. The
  -- vanilla-scene bridge (switch-request event -> real party pick ->
  -- Battle:switch) has no dependency the other way -- installed alongside
  -- for grouping. See combat/switch_primitives.lua's own header for the
  -- full grounding, including why this mod stays entirely self-contained
  -- (no gen1recomp-dev engine source edits anywhere in it).
  local installSwitchPrimitives = loadSibling(mod, "combat/switch_primitives.lua")
  installSwitchPrimitives(mod)
  local installSwitchVanillaBridge = loadSibling(mod, "combat/switch_vanilla_bridge.lua")
  installSwitchVanillaBridge(mod)

  -- Shared "does the setter hold the duration-extending item" primitive --
  -- weather (below), Trick Room, and the new terrain system (further down)
  -- all resolve their own real duration through this one function rather
  -- than three copies of the same 5-vs-8 check. No dependency on anything
  -- else in this file; loaded here so every real field-effect install
  -- below can consume mod.exports.resolveFieldDuration. See combat/
  -- field_duration.lua's own header for the full grounding.
  local installFieldDuration = loadSibling(mod, "combat/field_duration.lua")
  installFieldDuration(mod)

  -- The ability-execution primitive (mod.exports.abilityIdOf/
  -- abilityBehaviorOf) -- this mod's first real integration of
  -- national_dex's ability data into actual battle behavior. Only needs
  -- national_dex (a hard dependency, already loaded), so it can sit here,
  -- ahead of modern_combat.lua, ready for anything below to consume. See
  -- abilities/ability_dispatch.lua's own header for the full grounding,
  -- including the explicit user directive that every ability engine file
  -- keeps its data (abilities/data/*.lua, pure tables) and its dispatch
  -- logic (abilities/engine/*.lua) in entirely separate files.
  local installAbilityDispatch = loadSibling(mod, "abilities/ability_dispatch.lua")
  installAbilityDispatch(mod)

  -- Interaction memory (recordInteraction/lastInteractionAgainst) --
  -- explicit user design, the real primitive Mirror Armor (Phase 8,
  -- other bucket) needs without threading a new parameter through
  -- changeStage's own signature. Sits here, ahead of modern_combat.lua,
  -- so changeStage's own Mirror Armor check and every recorder below
  -- can capture it as a plain local.
  local installInteractionMemory = loadSibling(mod, "combat/interaction_memory.lua")
  installInteractionMemory(mod)

  local installModernCombat = loadSibling(mod, "combat/modern_combat.lua")
  installModernCombat(mod)

  -- Legacy move takeover -- explicit user directive: classic fixed-
  -- damage/OHKO moves must route through the same battle.damage hook
  -- chain every other move already does, not bypass it. No dependency
  -- on any other file in this mod (works via native monkeypatch +
  -- Runtime.call directly), so it's safe to install this early.
  local installLegacyMoveTakeover = loadSibling(mod, "combat/legacy_move_takeover.lua")
  installLegacyMoveTakeover(mod)

  -- Move targeting resolver -- moved up here (ahead of ANY switch_in
  -- ability engine) because abilities/engine/switchin_stat_change.lua's
  -- own foes-scope switch_in abilities (Intimidate) need this file's
  -- mod.exports.requestAdjacency, the same "g9.request_adjacency" hook
  -- moves use, generalized to ability triggers -- see combat/
  -- MULTI_BATTLE_HOOKS.md's own Targeting section for the full contract.
  -- Only needs modern_combat.lua (installed just above) and
  -- src/mods/Runtime.lua (a hard engine dependency, always present), so
  -- this is safe to load this early.
  local installMoveTargeting = loadSibling(mod, "combat/move_targeting.lua")
  installMoveTargeting(mod)

  -- Boss-fight protection flags (mod.exports.setBossFightProtections/
  -- bossFightHas) -- loaded right after modern_combat.lua since several
  -- of its own primitives (setWeather/canSetWeather, changeStage/
  -- bossStatsDropBlocked) read bossFightHas, but every read is lazy
  -- (inside a function body, not hoisted at install time), so this is
  -- about readability, not a real ordering requirement. See combat/
  -- boss_fight.lua's own header for the full flag list and where each
  -- one's actual enforcement lives.
  local installBossFight = loadSibling(mod, "combat/boss_fight.lua")
  installBossFight(mod)

  -- hardStatus/softStatus/antiDrain halves of the boss-fight protection
  -- set -- grouped in their own file since none of the three has an
  -- existing primitive-owning file the way weather/terrain/type do. See
  -- combat/boss_fight_status.lua's own header for the full grounding,
  -- including why its confusion listener needs an explicit priority
  -- rather than trusting load order.
  local installBossFightStatus = loadSibling(mod, "combat/boss_fight_status.lua")
  installBossFightStatus(mod)

  -- The first real wired abilities: Intimidate/Intrepid Sword/Dauntless
  -- Shield/Supersweet Syrup, all switch_in + kind="stat_change" in
  -- national_dex's own data. Consumes modern_combat.lua's changeStage
  -- (installed just above) and ability_dispatch.lua's abilityIdOf
  -- (installed above that). See abilities/engine/switchin_stat_change.lua's
  -- own header for the full grounding and why every other switch_in
  -- ability was left out of this first pass.
  local statChangeSwitchinData = loadSibling(mod, "abilities/data/stat_change_switchin.lua")
  local installSwitchinStatChange = loadSibling(mod, "abilities/engine/switchin_stat_change.lua")
  installSwitchinStatChange(mod, statChangeSwitchinData)
  local installModernCombatProtect = loadSibling(mod, "combat/modern_combat_protect.lua")
  installModernCombatProtect(mod)

  -- Phase 3 of the ability roadmap: status/type immunity. See each
  -- engine file's own header for the full grounding -- status_immunity
  -- must load after move_targeting.lua (Sweet Veil's ally check reuses
  -- requestAdjacency); type_immunity must load after modern_combat_
  -- protect.lua's own "battle.damage" wrap so a protected target's
  -- absorb ability correctly never triggers (priority ordering handles
  -- this at call time, not install time, but installing after keeps the
  -- wrap-chain's own priority comment legible against real load order).
  local statusImmunityData = loadSibling(mod, "abilities/data/status_immunity.lua")
  local installStatusImmunity = loadSibling(mod, "abilities/engine/status_immunity.lua")
  installStatusImmunity(mod, statusImmunityData)
  -- Real ownership of the paralysis/sleep/freeze turn-loss DECISION
  -- (standing "we are the bible of combat" principle, extended from
  -- move ordering to status-based turn loss) -- see that file's own
  -- header for the full grounding, including the real Showdown-source-
  -- verified corrections this makes over the ported native logic.
  -- Loaded here (after status_immunity.lua, for abilityIdOf's Early
  -- Bird check) rather than back with the rest of installMovepoolEffects
  -- -- this is real ability-adjacent combat-ownership work, not movepool
  -- wiring.
  local installStatusTurnLoss = loadSibling(mod, "combat/modern_status_turn_loss.lua")
  installStatusTurnLoss(mod)
  local typeImmunityData = loadSibling(mod, "abilities/data/type_immunity.lua")
  local installTypeImmunity = loadSibling(mod, "abilities/engine/type_immunity.lua")
  installTypeImmunity(mod, typeImmunityData)

  -- Gym Badge Buff (combat/gym_badge_buff.lua) -- loads BEFORE
  -- stat_multiplier.lua below, on purpose: real Gold/Silver badge boosts
  -- are intrinsic to the party's own stat value (a cartridge-level bonus,
  -- not a Gen 3+ ability multiplier), so this needs to be the INNERMOST
  -- Battle:battleStat layer -- applied first, to the raw stat -- with
  -- ability multipliers composing on TOP of the badge-boosted number
  -- once stat_multiplier.lua wraps this file's own already-wrapped
  -- version next. Reversing this order would apply an ability multiplier
  -- to the un-boosted stat, then a flat badge bonus on top of THAT
  -- already-multiplied number -- the wrong layering.
  local installGymBadgeBuff = loadSibling(mod, "combat/gym_badge_buff.lua")
  installGymBadgeBuff(mod)

  -- Phase 4 of the ability roadmap: stat_multiplier. Loads after
  -- status_immunity.lua (reuses its canonicalStatusOf for Flare Boost/
  -- Toxic Boost's own status check) -- see that engine file's own header
  -- for the full grounding, including why this wraps Battle:battleStat
  -- directly rather than any of this mod's existing damage-modifier
  -- chains.
  local statMultiplierData = loadSibling(mod, "abilities/data/stat_multiplier.lua")
  local installStatMultiplier = loadSibling(mod, "abilities/engine/stat_multiplier.lua")
  installStatMultiplier(mod, statMultiplierData)
  -- Terastallization's own combat mechanics (STAB fix, Stellar defense/
  -- economy, Tera Blast's Stellar variant) -- consumes modern_combat.lua's
  -- exports, must load after it. See combat/modern_tera.lua's own header.
  local installModernTera = loadSibling(mod, "combat/modern_tera.lua")
  installModernTera(mod)

  -- Type override: the generic "this mon's own current type changes mid-
  -- battle" primitive (mod.exports.setMonTypes, the TYPE_CHANGE_SOURCES
  -- dictionary) -- Soak/Magic Powder/Burn Up/etc. are its first real
  -- callers (below), but per explicit user decision this is meant to be
  -- the same entrypoint a future ability (Protean/Libero/Color Change)
  -- reaches for too. Consumes modern_tera.lua's own originalTypesOf,
  -- installed just above. See combat/type_override_primitives.lua's own
  -- header for the full grounding, including why this is a distinct
  -- system from Terastallization.
  local installTypeOverridePrimitives = loadSibling(mod, "combat/type_override_primitives.lua")
  installTypeOverridePrimitives(mod)

  -- Protean/Libero (on_move_used) and Color Change (on_damaged) --
  -- consumes type_override_primitives.lua's setMonTypes/canChangeType/
  -- once-per-switch-in tracking, all installed just above. See abilities/
  -- engine/onmove_type_change.lua and abilities/engine/
  -- ondamage_type_change.lua's own headers for the full grounding.
  local typeChangeOnMoveData = loadSibling(mod, "abilities/data/type_change_onmove.lua")
  local installOnMoveTypeChange = loadSibling(mod, "abilities/engine/onmove_type_change.lua")
  installOnMoveTypeChange(mod, typeChangeOnMoveData)
  local typeChangeOnDamageData = loadSibling(mod, "abilities/data/type_change_ondamage.lua")
  local installOnDamageTypeChange = loadSibling(mod, "abilities/engine/ondamage_type_change.lua")
  installOnDamageTypeChange(mod, typeChangeOnDamageData)

  -- Phase 1.8: Multitype/Forecast/Mimicry -- the "passive, derived-type"
  -- family, a structurally different shape from Protean/Libero/Color
  -- Change above (those are discrete-trigger; these three compute their
  -- type continuously, or in Multitype's case once at switch-in, from
  -- live item/weather/terrain state rather than reacting to one move/
  -- damage event). No dependency on modern_weather.lua/modern_terrain.lua
  -- actually being loaded by this point -- each engine's own asserts only
  -- need type_override_primitives.lua/modern_combat.lua/ability_dispatch
  -- .lua (all already loaded above); their event listeners are lazy and
  -- only ever run during a real battle, by which point every mod has
  -- finished loading. See each file's own header for its full grounding.
  local multitypeSwitchinData = loadSibling(mod, "abilities/data/multitype_switchin.lua")
  local installSwitchinMultitype = loadSibling(mod, "abilities/engine/switchin_multitype.lua")
  installSwitchinMultitype(mod, multitypeSwitchinData)
  local forecastWeatherData = loadSibling(mod, "abilities/data/forecast_weather.lua")
  local installForecastWeather = loadSibling(mod, "abilities/engine/forecast_weather.lua")
  installForecastWeather(mod, forecastWeatherData)
  local mimicryTerrainData = loadSibling(mod, "abilities/data/mimicry_terrain.lua")
  local installMimicryTerrain = loadSibling(mod, "abilities/engine/mimicry_terrain.lua")
  installMimicryTerrain(mod, mimicryTerrainData)

  -- Phase 2: damage_dealt_multiplier/damage_taken_multiplier abilities --
  -- consumes modern_combat.lua's registerDamageModifier/
  -- registerPostEffectivenessModifier (installed above) and ability_
  -- dispatch.lua's abilityIdOf/abilityBehaviorOf. See abilities/engine/
  -- damage_multiplier.lua's own header for the full grounding, including
  -- the placeholder move-flag data relayed to national_dex's own dev.
  local damageMultiplierData = loadSibling(mod, "abilities/data/damage_multiplier.lua")
  local installDamageMultiplier = loadSibling(mod, "abilities/engine/damage_multiplier.lua")
  installDamageMultiplier(mod, damageMultiplierData)

  -- Turn order: Gen 9/Showdown-accurate priority + Speed + Trick-Room-
  -- aware + random-tie comparator, replacing gen2/Battle.lua's own native
  -- one via the battle.turn_order hook. No dependency on modern_combat.lua's
  -- own exports, load position here is just for grouping with the rest of
  -- combat/. See combat/turn_order.lua's own header and
  -- combat/MULTI_BATTLE_HOOKS.md for the full grounding.
  local installTurnOrder = loadSibling(mod, "combat/turn_order.lua")
  installTurnOrder(mod)

  -- Phase 5 of the ability roadmap: priority_change. Loads right after
  -- turn_order.lua (needs its registerPriorityModifier) -- see that
  -- engine file's own header for the full grounding, including the real
  -- Gen 7+ Prankster/Dark-type immunity it also wires.
  local priorityChangeData = loadSibling(mod, "abilities/data/priority_change.lua")
  local installPriorityChange = loadSibling(mod, "abilities/engine/priority_change.lua")
  installPriorityChange(mod, priorityChangeData)

  -- Phase 6 of the ability roadmap: heal / crit_change /
  -- accuracy_multiplier. See each engine file's own header for the full
  -- grounding -- three genuinely separate real primitives (turn-end
  -- residual + poison-residual replacement for heal, the existing
  -- registerCritStageModifier chain for crit_change, and a brand new
  -- registerAccuracyModifier chain built on Battle:accuracyRoll's own
  -- real "battle.accuracy" hook for accuracy_multiplier).
  local healData = loadSibling(mod, "abilities/data/heal.lua")
  local installHeal = loadSibling(mod, "abilities/engine/heal.lua")
  installHeal(mod, healData)
  local critChangeData = loadSibling(mod, "abilities/data/crit_change.lua")
  local installCritChange = loadSibling(mod, "abilities/engine/crit_change.lua")
  installCritChange(mod, critChangeData)
  local accuracyMultiplierData = loadSibling(mod, "abilities/data/accuracy_multiplier.lua")
  local installAccuracyMultiplier = loadSibling(mod, "abilities/engine/accuracy_multiplier.lua")
  installAccuracyMultiplier(mod, accuracyMultiplierData)

  -- Phase 8a of the ability roadmap ("other" bucket, first batch --
  -- 122 abilities total, far larger than any prior bucket, so this is
  -- a curated first pass, not the whole thing). See each engine file's
  -- own header for the full grounding.
  local stageChangeTransformData = loadSibling(mod, "abilities/data/stage_change_transform.lua")
  local installStageChangeTransform = loadSibling(mod, "abilities/engine/stage_change_transform.lua")
  installStageChangeTransform(mod, stageChangeTransformData)
  local damageImmunityData = loadSibling(mod, "abilities/data/damage_immunity.lua")
  local installDamageImmunity = loadSibling(mod, "abilities/engine/damage_immunity.lua")
  installDamageImmunity(mod, damageImmunityData)
  local statusCureData = loadSibling(mod, "abilities/data/status_cure.lua")
  local installStatusCure = loadSibling(mod, "abilities/engine/status_cure.lua")
  installStatusCure(mod, statusCureData)
  local contactRetaliationData = loadSibling(mod, "abilities/data/contact_retaliation.lua")
  local installContactRetaliation = loadSibling(mod, "abilities/engine/contact_retaliation.lua")
  installContactRetaliation(mod, contactRetaliationData)

  -- Real Showdown-verified logic for the bespoke "no flag covers this"
  -- moves (Leech Seed, Nightmare, Ingrain, Yawn, Disable, Embargo,
  -- Heal Block/Psychic Noise, Throat Chop, Perish Song, Foresight/
  -- Miracle Eye/Odor Sleuth, Smack Down/Thousand Arrows, Telekinesis,
  -- Uproar, Dire Claw/Tri Attack) -- see that file's own header for the
  -- full grounding, verified against Showdown's own real source
  -- directly, not from memory.
  local installStatusVolatiles = loadSibling(mod, "combat/modern_status_volatiles.lua")
  installStatusVolatiles(mod)

  -- Trick Room's own real activation -- fills the exact gap
  -- combat/turn_order.lua's own header flags ("always false today"),
  -- with no dependency the other way around: this just writes
  -- battle.trickRoomActive, which that file already reads. See
  -- combat/trick_room.lua's own header for the full grounding.
  local installTrickRoom = loadSibling(mod, "combat/trick_room.lua")
  installTrickRoom(mod)

  -- Phase 1 of the move-effect completion pipeline: stat-stage-change
  -- stubs wired to modern_combat.lua's changeStage primitive via their own
  -- hardcoded GMAX_*_EFFECT registrations + move patches -- no runtime
  -- dependency on moves_new.lua, which was only ever this file's original
  -- discovery source for which moves needed this. Split into its own
  -- sibling file rather than grown into modern_combat.lua (~56
  -- registrations) -- see that file's own header for the full grounding.
  -- Must load after modern_combat.lua (consumes its exports).
  local installModernMovepoolStages = loadSibling(mod, "combat/modern_movepool_stages.lua")
  installModernMovepoolStages(mod)

  -- Phase 2 of the move-effect completion pipeline: status-infliction
  -- stubs (burn/paralyze/poison secondaries, Flatter/Swagger's combined
  -- stat+confuse) and recoil/drain/heal/two-turn-charge stubs. Two
  -- siblings, not one -- see each file's own header for why the two
  -- buckets need different move_effects record shapes (kind="secondary"+
  -- run vs. kind="full"+afterDamage/charge). Both load after
  -- modern_movepool_stages.lua for load-order consistency, though only
  -- modern_movepool_status.lua/modern_movepool_damage.lua's primary
  -- heals actually need modern_combat.lua's exports.
  local installModernMovepoolStatus = loadSibling(mod, "combat/modern_movepool_status.lua")
  installModernMovepoolStatus(mod)
  local installModernMovepoolDamage = loadSibling(mod, "combat/modern_movepool_damage.lua")
  installModernMovepoolDamage(mod)

  -- Phase 3 of the move-effect completion pipeline: Metal Burst/Mirror
  -- Coat (Detect's patch lives in modern_combat_protect.lua itself, next
  -- to its own PROTECT patch; Feint's bypassesProtect is plain moves_new
  -- .lua data, patched onto the live FEINT record by wireMovepoolSubEffects
  -- above -- neither needs this file). Loaded after modern_combat_protect.lua
  -- (installed above) so its
  -- target.protected checks see a real flag either way, though load order
  -- between the two doesn't actually matter here -- both only read/write
  -- battler fields at battle time, never at load time.
  local installModernMovepoolCounter = loadSibling(mod, "combat/modern_movepool_counter.lua")
  installModernMovepoolCounter(mod)

  -- Volatile statuses native combat never had a mechanic for at all:
  -- Attract, Taunt, Torment (plus the move data that makes Gen 2's own
  -- already-complete Encore mechanism reachable for the first time) --
  -- see modern_status_effects.lua's own header for the full per-engine
  -- enforcement-touch-point grounding.
  local installModernStatusEffects = loadSibling(mod, "combat/modern_status_effects.lua")
  installModernStatusEffects(mod)

  -- The inflict_status kind bucket (16 real abilities) -- never touched
  -- by any earlier ability phase despite the roadmap otherwise covering
  -- 6 of the 8 real-count-weighted buckets by this point. Must load
  -- here, right after combat/modern_status_effects.lua (reuses its own
  -- real tryAttract primitive for Cute Charm, just exported) -- an
  -- earlier position in this file's own sequence would have asserted
  -- before that export existed.
  local inflictStatusData = loadSibling(mod, "abilities/data/inflict_status.lua")
  local installInflictStatus = loadSibling(mod, "abilities/engine/inflict_status.lua")
  installInflictStatus(mod, inflictStatusData)

  -- Phase 7 (`prevent` bucket, 43 real abilities) -- first real batch,
  -- 24 built this pass (plus 4 credited that were already built
  -- incidentally under earlier phases: ROCKHEAD/recoil-block in this
  -- file's own generic drain handler above, DESOLATELAND/PRIMORDIALSEA's
  -- Water/Fire move-fail gate in abilities/engine/switchin_primal_
  -- weather.lua, POISONHEAL's residual replacement in abilities/engine/
  -- heal.lua). Each engine file documents its own real primitive; see
  -- PROGRESS.md for the full per-ability breakdown and the real,
  -- honestly-named remainder. Priority-fail needs turn_order.lua's own
  -- movePriority (loaded well above); trap/misc need modern_combat.lua's
  -- curTypesOf/changeStage and ability_dispatch.lua's abilityIdOf, both
  -- also already loaded by this point.
  local preventPriorityFailData = loadSibling(mod, "abilities/data/prevent_priority_fail.lua")
  local installPreventPriorityFail = loadSibling(mod, "abilities/engine/prevent_priority_fail.lua")
  installPreventPriorityFail(mod, preventPriorityFailData)

  local trapAbilitiesData = loadSibling(mod, "abilities/data/trap_abilities.lua")
  local installTrapAbilities = loadSibling(mod, "abilities/engine/trap_abilities.lua")
  installTrapAbilities(mod, trapAbilitiesData)

  local preventMiscData = loadSibling(mod, "abilities/data/prevent_misc.lua")
  local installPreventMisc = loadSibling(mod, "abilities/engine/prevent_misc.lua")
  installPreventMisc(mod, preventMiscData)

  -- Phase 7 completion pass (2026-08-28): AROMAVEIL, GOODASGOLD, KLUTZ/
  -- LONGREACH/STICKYHOLD/UNNERVE-family (all wired directly into their
  -- own real primitive's file -- modern_items.lua, contact_retaliation
  -- .lua, ability_copy.lua, inflict_status.lua -- no separate install
  -- call needed), DISGUISE (abilities/data/damage_immunity.lua, already
  -- installed above). STALWART confirmed a real no-op (no move-
  -- redirection mechanic exists anywhere in this engine).
  local aromaVeilData = loadSibling(mod, "abilities/data/aroma_veil.lua")
  local installAromaVeil = loadSibling(mod, "abilities/engine/aroma_veil.lua")
  installAromaVeil(mod, aromaVeilData)

  local goodAsGoldData = loadSibling(mod, "abilities/data/good_as_gold.lua")
  local installGoodAsGold = loadSibling(mod, "abilities/engine/good_as_gold.lua")
  installGoodAsGold(mod, goodAsGoldData)

  local longReachData = loadSibling(mod, "abilities/data/long_reach.lua")
  local installLongReach = loadSibling(mod, "abilities/engine/long_reach.lua")
  installLongReach(mod, longReachData)

  -- Phase 8 (`other` bucket) -- first real batch after Phase 7. Pressure
  -- needs national_dex's own moveById (loaded first thing) and
  -- ability_dispatch.lua's abilityIdOf (loaded well above); ability_copy
  -- additionally needs setAbility (same file) and turn_order.lua's
  -- orderSwitchInMons (also already loaded); the ability-changing MOVES
  -- need setAbility too, plus this file's own normalize/displayNameFor
  -- exports.
  local pressureData = loadSibling(mod, "abilities/data/pressure.lua")
  local installPressure = loadSibling(mod, "abilities/engine/pressure.lua")
  installPressure(mod, pressureData)

  local abilityCopyData = loadSibling(mod, "abilities/data/ability_copy.lua")
  local installAbilityCopy = loadSibling(mod, "abilities/engine/ability_copy.lua")
  installAbilityCopy(mod, abilityCopyData)

  local installAbilityChangeMoves = loadSibling(mod, "combat/modern_ability_change_moves.lua")
  installAbilityChangeMoves(mod)

  -- Self-switch moves (U-turn, Volt Switch) -- consumes
  -- mod.exports.requestSwitch, installed above; see
  -- combat/modern_switch_moves.lua's own header for why this wraps
  -- Battle:useMove rather than acting straight from its own
  -- battle.damage_dealt listener.
  local installModernSwitchMoves = loadSibling(mod, "combat/modern_switch_moves.lua")
  installModernSwitchMoves(mod)

  -- Terrain: Electric/Grassy/Misty/Psychic -- consumes modern_combat.lua's
  -- curTypesOf/registerDamageModifier and field_duration.lua's
  -- resolveFieldDuration, both installed above. See combat/
  -- modern_terrain.lua's own header for the full grounding.
  local installModernTerrain = loadSibling(mod, "combat/modern_terrain.lua")
  installModernTerrain(mod)

  -- Electric/Grassy/Misty/Psychic Surge + Hadron Engine's terrain half --
  -- consumes modern_terrain.lua's own mod.exports.setTerrain (extracted
  -- from its move starters just above, specifically so this engine could
  -- reuse it) and ability_dispatch.lua's abilityIdOf. See abilities/
  -- engine/switchin_terrain.lua's own header for the full grounding.
  local terrainSwitchinData = loadSibling(mod, "abilities/data/terrain_switchin.lua")
  local installSwitchinTerrain = loadSibling(mod, "abilities/engine/switchin_terrain.lua")
  installSwitchinTerrain(mod, terrainSwitchinData)

  -- change_type moves (Soak, Magic Powder, Conversion, Reflect Type,
  -- Camouflage, Burn Up, Double Shock) -- consumes mod.exports.
  -- setMonTypes (type_override_primitives.lua, installed above) and
  -- battle.terrain (modern_terrain.lua, installed just above). See
  -- combat/modern_type_change_moves.lua's own header for the full
  -- grounding.
  local installModernTypeChangeMoves = loadSibling(mod, "combat/modern_type_change_moves.lua")
  installModernTypeChangeMoves(mod)

  -- Phase 4 of the move-effect completion pipeline: weather (Rain Dance/
  -- Sunny Day/Sandstorm/Snowscape, Thunder/Blizzard's accuracy exception,
  -- Solar Beam's Sun charge-skip, Sand's end-of-turn chip). Weather STATE
  -- and the Sun/Rain damage modifier live in modern_combat.lua itself
  -- (see that file's own header); this sibling owns the wiring. Loaded
  -- after modern_status_effects.lua for load-order consistency with the
  -- rest of this pipeline, and before gimmick_dynamax.lua so its Solar
  -- Beam performMove wrap sits inside (native-ward of) Max Guard's own.
  local installModernWeather = loadSibling(mod, "combat/modern_weather.lua")
  installModernWeather(mod)

  -- Drizzle/Drought/Snow Warning + Orichalcum Pulse's weather half --
  -- consumes modern_weather.lua's own setWeather/currentWeather and
  -- ability_dispatch.lua's abilityIdOf. See abilities/engine/
  -- switchin_weather.lua's own header for the full grounding, including
  -- why Desolate Land/Primordial Sea/Delta Stream are deliberately not
  -- here yet (Phase 1.5, explicit user decision).
  local weatherSwitchinData = loadSibling(mod, "abilities/data/weather_switchin.lua")
  local installSwitchinWeather = loadSibling(mod, "abilities/engine/switchin_weather.lua")
  installSwitchinWeather(mod, weatherSwitchinData)

  -- Phase 1.5: Desolate Land/Primordial Sea/Delta Stream ("primal"
  -- weather) -- irreplaceable, indefinite duration, ends when the setting
  -- Pokemon leaves the field, plus Desolate Land/Primordial Sea's own
  -- Water/Fire move-fail gate and Delta Stream's type-effectiveness cap.
  -- A deliberately separate engine file from switchin_weather.lua just
  -- above -- the mechanics genuinely differ (see that file's own header
  -- for the full grounding), not a copy-paste split. Consumes modern_
  -- weather.lua's own setWeather/currentWeather/canSetWeather (installed
  -- just above) and ability_dispatch.lua's abilityIdOf/abilityBehaviorOf.
  local primalWeatherSwitchinData = loadSibling(mod, "abilities/data/primal_weather_switchin.lua")
  local installSwitchinPrimalWeather = loadSibling(mod, "abilities/engine/switchin_primal_weather.lua")
  installSwitchinPrimalWeather(mod, primalWeatherSwitchinData)

  -- Part B Phase 5, first batch: entry hazards (Stealth Rock, Toxic
  -- Spikes, Rapid Spin). Same load-order requirement as modern_weather.lua
  -- above -- consumes modern_combat.lua's normalize/displayNameFor/
  -- curTypesOf/isGen2Battle exports -- so stays after it; order relative
  -- to modern_weather.lua itself doesn't matter (independent field state).
  local installModernHazards = loadSibling(mod, "combat/modern_hazards.lua")
  installModernHazards(mod)

  -- Part B Phase 5, second batch: item-interaction moves (Fling, Knock
  -- Off, Covet, Incinerate, Bug Bite, Pluck, Recycle, Belch). Same
  -- modern_combat.lua load-order requirement as modern_hazards.lua above.
  local installModernItems = loadSibling(mod, "combat/modern_items.lua")
  installModernItems(mod)

  -- New item-implementation phase (2026-08-28, explicit directive: "we
  -- override item behavior for native items, always, imperative, in
  -- terms of combat"). Phase 1: auditing/overriding the held items Gen 2
  -- already has real ROM-driven combat behavior for, against real
  -- Pokemon Showdown Gen 9 logic -- see that file's own header for the
  -- full per-item grounding. Needs modern_items.lua's own itemOf export
  -- (just above), modern_combat.lua's registerCritStageModifier, and
  -- accuracy_multiplier.lua's registerAccuracyModifier (both loaded
  -- earlier).
  local installModernHeldItems = loadSibling(mod, "combat/modern_held_items.lua")
  installModernHeldItems(mod)

  -- Held items Phase 2 (2026-08-28, explicit directive: "start with non
  -- consumables first"): Choice Band/Specs/Scarf, Life Orb, Assault
  -- Vest, Eviolite, Expert Belt, Rocky Helmet, Black Sludge, Light Clay,
  -- Quick Powder, Iron Ball, Lagging Tail, Full Incense, Deep Sea Tooth/
  -- Scale, Soul Dew, the three Sinnoh orbs (all newly registered items,
  -- no cart precedent), plus Light Ball/Thick Club/Metal Powder's own
  -- previously-unwired real native combat effect. Also fixes a real
  -- dead-code bug in modern_held_items.lua's own Phase 1 type-boost fix
  -- -- see that file's own header for the correction. Needs modern_items
  -- .lua's itemOf (just above), modern_combat.lua's
  -- registerDamageModifier/registerPostEffectivenessModifier/
  -- resolvedTypeMult, and combat/turn_order.lua's own
  -- registerPriorityModifier (loaded well above).
  local installModernHeldItemsPhase2 = loadSibling(mod, "combat/modern_held_items_phase2.lua")
  installModernHeldItemsPhase2(mod)

  -- Phase 8 ("other" bucket): Skill Link -- Gen 1 only, see that file's
  -- own header for the real scope split.
  local skillLinkData = loadSibling(mod, "abilities/data/skill_link.lua")
  local installSkillLink = loadSibling(mod, "abilities/engine/skill_link.lua")
  installSkillLink(mod, skillLinkData)

  -- Phase 8 ("other" bucket), consolidated batch: Bad Dreams, Cursed
  -- Body, Anticipation, Forewarn, Wonder Skin, Screen Cleaner, Toxic
  -- Debris. Needs modern_hazards.lua's own hazardsFor export (Toxic
  -- Debris) and accuracy_multiplier.lua's own registerAccuracyModifier
  -- export (Wonder Skin), both already loaded above.
  local otherMiscData = loadSibling(mod, "abilities/data/other_misc.lua")
  local installOtherMisc = loadSibling(mod, "abilities/engine/other_misc.lua")
  installOtherMisc(mod, otherMiscData)

  -- Phase 8 ("other" bucket): the item-interaction family (Frisk,
  -- Magician, Pickpocket, Harvest) -- Ripen/Cheek Pouch are built
  -- directly inside modern_items.lua itself, see that file's own header.
  -- Needs modern_items.lua's own itemOf/isUnremovable exports (just
  -- above) and long_reach.lua's own makesContact export (loaded earlier
  -- in Phase 7's own batch).
  local itemInteractionData = loadSibling(mod, "abilities/data/item_interaction.lua")
  local installItemInteraction = loadSibling(mod, "abilities/engine/item_interaction.lua")
  installItemInteraction(mod, itemInteractionData)

  -- Phase 8 ("other" bucket): the switch/priority family (Download,
  -- Moody, Curious Medicine, Costar, Beast Boost, Supreme Overlord,
  -- Stall, Quick Draw). Needs modern_combat.lua's own newly-exported
  -- stagesFor/sideOfWho/rawStat (this batch's own additions, right
  -- alongside changeStage/registerDamageModifier) and turn_order.lua's
  -- registerPriorityModifier.
  local switchPriorityMiscData = loadSibling(mod, "abilities/data/switch_priority_misc.lua")
  local installSwitchPriorityMisc = loadSibling(mod, "abilities/engine/switch_priority_misc.lua")
  installSwitchPriorityMisc(mod, switchPriorityMiscData)

  -- Phase 8 ("other" bucket), a small second batch: Perish Body, Punk
  -- Rock.
  local otherMisc2Data = loadSibling(mod, "abilities/data/other_misc2.lua")
  local installOtherMisc2 = loadSibling(mod, "abilities/engine/other_misc2.lua")
  installOtherMisc2(mod, otherMisc2Data)

  -- Phase 8 ("other" bucket), continuing into the previously-deferred
  -- complex remainder per explicit user direction (out-of-scope items
  -- confirmed: form-changing abilities and single-species gimmicks,
  -- both owned by battle_forms).
  local truantData = loadSibling(mod, "abilities/data/truant.lua")
  local installTruant = loadSibling(mod, "abilities/engine/truant.lua")
  installTruant(mod, truantData)

  local magicBounceData = loadSibling(mod, "abilities/data/magic_bounce.lua")
  local installMagicBounce = loadSibling(mod, "abilities/engine/magic_bounce.lua")
  installMagicBounce(mod, magicBounceData)

  local dancerData = loadSibling(mod, "abilities/data/dancer.lua")
  local installDancer = loadSibling(mod, "abilities/engine/dancer.lua")
  installDancer(mod, dancerData)

  local emergencyExitData = loadSibling(mod, "abilities/data/emergency_exit.lua")
  local installEmergencyExit = loadSibling(mod, "abilities/engine/emergency_exit.lua")
  installEmergencyExit(mod, emergencyExitData)

  local typeOverrideMovesData = loadSibling(mod, "abilities/data/type_override_moves.lua")
  local installTypeOverrideMoves = loadSibling(mod, "abilities/engine/type_override_moves.lua")
  installTypeOverrideMoves(mod, typeOverrideMovesData)

  -- Parental Bond -- wraps battle.damage at a priority ABOVE
  -- type_override_moves.lua's own 200, so each of its two independent
  -- hits re-enters that wrap (and everything else below it) on its own.
  local parentalBondData = loadSibling(mod, "abilities/data/parental_bond.lua")
  local installParentalBond = loadSibling(mod, "abilities/engine/parental_bond.lua")
  installParentalBond(mod, parentalBondData)

  -- Form-changing abilities' own real combat effects, transformation
  -- side explicitly out of scope (explicit user directive). Needs
  -- combat/modern_tera.lua, type_override_primitives.lua, modern_items
  -- .lua, and modern_terrain.lua, all already loaded above.
  local formCombatEffectsData = loadSibling(mod, "abilities/data/form_combat_effects.lua")
  local installFormCombatEffects = loadSibling(mod, "abilities/engine/form_combat_effects.lua")
  installFormCombatEffects(mod, formCombatEffectsData)

  -- Shared theme/panel primitives (colors, panel(), printText(), cursor,
  -- HP bar) -- one module so battle and every menu screen below read as
  -- one coherent UI instead of per-screen one-off looks.
  local UiTheme = loadSibling(mod, "ui/ui_theme.lua")

  -- [g9-battle-engine-beta] Both custom battle scenes removed entirely
  -- (explicit user instruction, 2026-08-20): the Gen 1 gimmick-menu
  -- overlay (combat/custom_battle_scene.lua, which also defined
  -- mod.exports.gimmickRing) and the full custom Gen 2 battle screen
  -- (combat/gen2_custom_battle_screen.lua). Both files deleted outright,
  -- not just uncalled -- unlike Gigantamax's own move/HP-increase logic
  -- (Phase 3 above, Phase 14 below), there is nothing in either scene
  -- file worth keeping on disk: GimmickRing's replacement is explicitly
  -- expected to live in a different mod entirely, not a future revival
  -- of this code. Battles are fully vanilla on both generations now.

  -- ------- Phase 12: custom menu takeover, party screen first -------
  -- Same architecture gen1_modern_ui itself uses for non-battle screens
  -- (a kindFor-style classifier + the two-hook screen.render_visible /
  -- render.hud suppress-and-replace pattern its own author documents),
  -- generalized from the battle scene's own render.hud panel technique.
  -- Gated on custom_menu_scene, independent of custom_battle_scene so
  -- either can be toggled alone. The plain party overview is native/
  -- vanilla, untouched; this only adds the MOVES/RELEARN/IV-EV party-
  -- submenu extras vanilla doesn't have -- see custom_party_scene.lua's
  -- own header for the reasoning.
  local installCustomPartyScene = loadSibling(mod, "ui/custom_party_scene.lua")
  installCustomPartyScene(mod, UiTheme)

  -- ------- Phase 13: custom menu takeover, title/start/options/mods -------
  -- Same custom_menu_scene gate and render.hud/screen.render_visible
  -- pattern as custom_party_scene.lua, extended to the title screen menu,
  -- the in-game start (pause) menu, the options menu, and the mod
  -- manager -- see custom_menu_takeover.lua's own header for the full
  -- grounding (Menu/OptionsMenu/ManagerState field names, why title/start
  -- menus need to be individually tagged rather than blanket-catching
  -- every Menu instance, and the MOD MENUS hub replication).
  local installCustomMenuTakeover = loadSibling(mod, "ui/custom_menu_takeover.lua")
  installCustomMenuTakeover(mod, UiTheme)

  -- ------- Phase 14: Gigantamax gimmick ring -------
  -- TEMPORARILY DISABLED (2026-08-20, same instruction as Phase 3 above):
  -- gimmick_dynamax.lua registered into mod.exports.gimmickRing, which no
  -- longer exists now that both custom battle scenes are removed. Its
  -- own HP-doubling/3-turn-duration/Max-Move-access logic is otherwise
  -- untouched and stays on disk -- explicit user instruction: keep it,
  -- commented out here, until proper hooks into whichever other mod now
  -- owns Gigantamax activation (and GimmickRing's replacement) are
  -- defined.
  -- local installGigantamax = loadSibling(mod, "gigantamax/gimmick_dynamax.lua")
  -- installGigantamax(mod, mod.exports.gimmickRing)

  -- ------- Phase 15: Gen 2 move-type readout ("Gen 2 WIDE") -------
  -- Independent of everything above -- own option (gen2_wide_layout),
  -- own battle.overlay hook, touches nothing Phase 14/custom_battle_scene
  -- already owns. See gen2_wide_scene.lua's own header for why this is a
  -- same-box addition rather than a real wider canvas (Gen 2 has no
  -- engine-level mechanism for the latter, confirmed this session).
  local installGen2WideScene = loadSibling(mod, "combat/gen2_wide_scene.lua")
  installGen2WideScene(mod)

  -- ------- Custom trainer roster registration API -------
  -- mod.exports.registerTrainer("CLASS:MEMBERID", party) -- explicit user
  -- directive, 2026-08-28. Needs stats/engine_modern_stats.lua's own
  -- ModernStats export (Phase "stats", well above), stats/
  -- trainer_modern_stats.lua's registerTrainerStatsProvider, gigantamax/
  -- tera_state.lua's setTeraType and gigantamax/dynamax_state.lua's
  -- setGigantamaxFactor/setMonDynamaxLevel (all loaded above), and
  -- combat/modern_combat.lua's isGen2Battle. See that file's own header
  -- for the full grounding (real trainer identity, the three real
  -- integration points, real defaults). Placed here, after everything
  -- else except the deliberately-last Phase 16 below -- this file
  -- touches no :update loop, so ordering relative to Phase 16 doesn't
  -- matter either way, but there's no reason to risk it.
  local installCustomTrainerRegistry = loadSibling(mod, "trainers/custom_trainer_registry.lua")
  installCustomTrainerRegistry(mod)

  -- TEMPORARY, 2026-08-29: in-process trainer registrations (Joey ->
  -- 2x Excadrill, doubles), isolated in their own file for readability
  -- -- see trainers/temp_test_registrations.lua's own header. Revert/
  -- delete both once the cross-mod registerTrainer investigation is
  -- resolved -- this does not belong in a shipped build.
  local installTempTestRegistrations = loadSibling(mod, "trainers/temp_test_registrations.lua")
  installTempTestRegistrations(mod)

  -- ------- Phase 16: move-availability gate (0-PP-style blocking) -------
  -- Wraps BattleState:update on both generations and must be the outermost
  -- layer among the wraps installed ABOVE it, so its input check runs
  -- before any of them (sprite animation, custom_battle_scene,
  -- gimmick_dynamax, gen2_wide_scene) gets a chance to consume the frame --
  -- see move_availability_gate.lua's own header. Phase 17 is installed
  -- after it and is therefore now the true outermost layer; that does not
  -- weaken this one, because Phase 17 reads no input and consumes no frame
  -- in any phase but its own (see the note there).
  local installMoveAvailabilityGate = loadSibling(mod, "combat/move_availability_gate.lua")
  -- CONFIRMED live crash, this session: learnset_ownership.lua's own
  -- return table uses the key `isUsable` (its own local function's real
  -- name), never `isMoveUsable` -- that second name only ever existed as
  -- a SEPARATE mod.exports.isMoveUsable assignment inside that file, not
  -- on this table. Reading .isMoveUsable off the table itself was always
  -- nil, silently, until this specific gate install actually tried to
  -- CALL it (move_availability_gate.lua:46) and crashed every update
  -- frame -- not something these two files' earlier edits this session
  -- introduced, a pre-existing naming mismatch this exposed.
  installMoveAvailabilityGate(mod, learnsetOwnership.isUsable)

  -- ------- Phase 17: two-choice in-battle prompt (mod-facing primitive) ---
  -- mod.exports.askBattleChoice / battleChoiceActive / cancelBattleChoice:
  -- any mod (including this one's own future boss-encounter code) can put a
  -- two-choice question on the Gen 2 battle screen and be called back with
  -- the answer. A primitive only -- nothing in it knows what a boss, a
  -- capture or an HP threshold is. See combat/battle_prompt.lua's own header
  -- for the base-engine limitation it works around (the yes/no box is drawn
  -- only for five hardcoded phase names, and an unrecognised phase falls off
  -- the end of native :update every frame) and for why Gen 1 is a follow-up
  -- rather than part of this.
  --
  -- Installed LAST of all, after the gate above: its :update wrap must be
  -- the outermost so its own phase name is intercepted before ANY other
  -- wrap can see it -- an unrecognised phase reaching another wrap's
  -- phase-specific code is the risk the whole file is built to remove. It
  -- takes nothing away from Phase 16: outside its own phase this wrap reads
  -- no input at all and falls straight through to native on the same frame.
  --
  -- Deliberately NOT folded into combat/boss_fight.lua even though the boss
  -- capture case is its motivating consumer -- that file is a flag-set
  -- policy layer with no UI and no class wrap; this is a screen primitive.
  local installBattlePrompt = loadSibling(mod, "combat/battle_prompt.lua")
  installBattlePrompt(mod)
end
