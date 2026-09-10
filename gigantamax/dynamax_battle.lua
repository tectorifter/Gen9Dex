-- Dynamax combat-property processor (round 13).
--
-- Explicit user scope (2026-08-20, restated 2026-09-07): battle_forms owns
-- Dynamax/Gigantamax activation and mechanics end to end -- WHEN a Pokemon
-- Dynamaxes, its 3-turn clock, its Max Move substitution (BATTLE_FORMS_*
-- ids), its damage-volume half (hpscale.lua), its Max Guard, and its Gen 2
-- size-up (gen2dynamaxgrow.lua). This mod does NOT decide when a gimmick
-- activates and does NOT provide its own gimmick activation. It READS the
-- activation trigger battle_forms already emits -- mod.battle_forms's own
-- `dynamax_applied` / `dynamax_reverted` events (src/formapi.lua,
-- fired from src/dynamax.lua's own apply/teardown) -- and CONSUMES it to
-- process the Dynamax combat properties battle_forms deliberately leaves
-- open, exactly the same consume-only relationship tera_state.lua already
-- has with `tera_applied`:
--
--   1. Dynamax Level drive. battle_forms' damage-volume half is
--      (30 + L) / 20 -- hpscale.lua reads L from the mon's
--      battleFormsDynamaxLevel stamp, which defaults to 0 (x1.5 HP). The
--      REAL level that should drive that multiplier is the one this mod
--      stores (dynamax_state.lua): per-mon when a trainer set one, else
--      battle_forms' own candy stamp when a Dynamax Candy was used, else
--      the player's per-save progression. On `dynamax_applied` we derive
--      that effective level and mirror it back into the mon's
--      battleFormsDynamaxLevel stamp so battle_forms' own hpscale uses
--      OUR answer (same read-backfill idiom tera_state.lua uses for the
--      tera type). Level 0 (x1.5) stays the default -- an unleveled
--      player who never touched a Candy or a trainer definition behaves
--      exactly as battle_forms ships.
--
--   2. Gen 1 size-up. battle_forms only grows the player's pic on Gen 2
--      (its src/gen2dynamaxgrow.lua wraps src.ui.gen2.BattleState
--      :picScale); its own main.lua documents that Gen 1 has no draw-time
--      scaling seam on its side. Gen 1's seam is this mod's: wrapping
--      src.battle.BattleState:drawBattlerPic (the same confirmed real
--      render point gimmick_dynamax.lua's own wrap uses -- BattleState
--      .lua:4875, signature (battler, x, y, scale)) and scaling the
--      player's pic around its bottom-centre while the mon is Dynamaxed.
--      Driven from wall-clock elapsed at draw time (no update-loop
--      interception -- battle_forms owns the turn clock, so unlike
--      gimmick_dynamax we must never block turn resolution). Sizing is
--      animated per the existing gigantamax_size / gigantamax_skip_animation
--      options; Gen 2 is deliberately untouched (battle_forms owns it).
--
--   3. Max Move secondary effects. battle_forms registers every damaging
--      Max Move as NO_ADDITIONAL_EFFECT (its own deliberate scope -- the
--      move data is generic across games and their gmaxmoves.lua has no
--      per-move secondaries). The Showdown-verified secondaries for Max
--      AND G-Max moves are processed in max_move_subeffects.lua, the
--      SAME way this mod processes every other move: a kind="full"
--      move-effects record (invisible to Gen 2's damage-preempting
--      dispatch) plus one shared battle.damage_dealt listener keyed on
--      the move's own effect field. Moves are discovered by battle_forms'
--      own BATTLE_FORMS_<STEM>_<POWER> id convention; the power ladder
--      (90-150 / 70-100 Fighting+Poison / fixed-160 G-Max) stays
--      battle_forms' -- this file never decides base power. maxguard
--      (status) is battle_forms' own -- skipped.
--
-- Why gimmick_dynamax.lua stays DISABLED (canonical-disabled, not
-- deleted): it is a full parallel Dynamax engine -- its own activation
-- ring, its own Max Move resolution, its OWN doubled-HP write and
-- per-battle 3-turn clock. battle_forms already owns all of that (the
-- 2026-08-20 scope note's whole point: a doubled-HP write from this mod
-- on top of battle_forms' would double-count), so booting both would
-- double HP, double substitutes, and race two 3-turn clocks. This file
-- is the consume-only replacement for that parallel engine.
return function(mod)
  if mod.exports.dynamaxBattleInstalled then return mod.exports end
  mod.exports.dynamaxBattleInstalled = true

  local clampLevel = function(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    if n > 10 then n = 10 end
    return math.floor(n)
  end

  -- Forward declarations for section 2's state: handleReverted (below)
  -- needs sizeUp/now even though the full size-up machinery is defined
  -- further down. Without these the names would resolve to nil globals.
  local sizeUp, now

  -- ---------------------------------------------------------------------
  -- 0. Trigger source: battle_forms' own events (pcall-guarded so the
  --    consume side still comes up if battle_forms is absent -- a
  --    dynamax_battle with no dynamax source just idles; the level/store
  --    and size-up options remain safe no-ops).
  -- ---------------------------------------------------------------------
  local appliedEvent, revertedEvent = "mod.battle_forms.dynamax_applied", "mod.battle_forms.dynamax_reverted"
  local okBf, bf = pcall(function() return mod.find and mod.find("battle_forms") end)
  if okBf and bf and bf.exports and bf.exports.events then
    if type(bf.exports.events.dynamaxApplied) == "string" then
      appliedEvent = bf.exports.events.dynamaxApplied
    end
    if type(bf.exports.events.dynamaxReverted) == "string" then
      revertedEvent = bf.exports.events.dynamaxReverted
    end
  end

  -- ---------------------------------------------------------------------
  -- 1. Dynamax Level drive + Dynamaxed marker. Keyed on the mon itself
  --    (battle_forms' payload carries the LIVE mon, not a battle -- Gen 1
  --    it is battle.player.mon, Gen 2 it is battle.player), so everything
  --    downstream -- including the Gen 1 size-up wrap, which only ever
  --    sees self.player.mon -- can key off the same identity.
  -- ---------------------------------------------------------------------
  local function handleApplied(ev)
    local mon = ev and ev.mon
    if not mon then return end
    mon.__g9Dynamaxed = true
    local effective
    local perMon = mod.exports.getMonDynamaxLevel and mod.exports.getMonDynamaxLevel(mon)
    if perMon ~= nil then
      effective = perMon
    elseif type(ev.dynamaxLevel) == "number" and ev.dynamaxLevel > 0 then
      -- battle_forms' own Dynamax Candy stamp (mon.battleFormsDynamaxLevel
      -- already set by its dynamaxlevel.lua) -- a per-mon candy is more
      -- specific than the per-save progression, so it wins over it.
      effective = ev.dynamaxLevel
    else
      effective = mod.exports.getDynamaxLevel and mod.exports.getDynamaxLevel() or 0
    end
    effective = clampLevel(effective)
    -- Mirror OUR effective level back into the stamp battle_forms' own
    -- hpscale.lua reads, so its (30+L)/20 damage-volume half reflects the
    -- level this mod actually stores. Same read-backfill idiom
    -- tera_state.lua uses for battleFormsTeraType.
    mon.battleFormsDynamaxLevel = effective
    return effective
  end

  local function handleReverted(ev)
    local mon = ev and ev.mon
    if not mon then return end
    mon.__g9Dynamaxed = nil
    local st = sizeUp[mon]
    if st and not st.shrinking then
      st.shrinking = true
      st.t0 = now()
    end
  end

  -- ---------------------------------------------------------------------
  -- 2. Gen 1 size-up. BattleState:drawBattlerPic is the one place the
  --    engine already renders the player's battle pic through a normal
  --    draw call -- wrapping it preserves the battle's palette, clipping,
  --    and every existing pic effect (same rationale + math as
  --    gimmick_dynamax.lua's own wrap). The factor is derived from
  --    wall-clock elapsed at draw time, so the animation advances with
  --    zero interference in the turn flow (battle_forms owns that).
  -- ---------------------------------------------------------------------
  local SIZE_LEVELS = { 1.2, 1.4, 1.8, 2.2, 2.6 }
  local DEFAULT_SIZE = 1.4
  local SEQUENCE_DURATION = 0.6

  now = function()
    if love and love.timer and love.timer.getTime then
      return love.timer.getTime()
    end
    return os.clock()
  end

  local function sizeOption()
    local raw = mod.options and mod.options:get("gigantamax_size")
    local n = tonumber(raw)
    if n and n >= 1 and n <= 3 then
      for _, lvl in ipairs(SIZE_LEVELS) do
        if n <= lvl then return lvl end
      end
      return SIZE_LEVELS[#SIZE_LEVELS]
    end
    return DEFAULT_SIZE
  end

  local function skipAnimationOption()
    return mod.options and mod.options:get("gigantamax_skip_animation") == "true"
  end

  local function growFractionAt(elapsed)
    if elapsed <= 0 then return 0 end
    if elapsed >= SEQUENCE_DURATION then return 1 end
    local t = elapsed / SEQUENCE_DURATION
    return t * t * (3 - 2 * t)
  end

  sizeUp = setmetatable({}, { __mode = "k" })

  local function scaleAtTime(mon)
    local st = sizeUp[mon]
    if not st then return nil end
    local skip = skipAnimationOption()
    if skip then
      if st.shrinking then
        sizeUp[mon] = nil
      end
      return st.shrinking and nil or st.target
    end
    local elapsed = now() - st.t0
    if st.shrinking then
      local frac = growFractionAt(math.max(0, SEQUENCE_DURATION - elapsed))
      local factor = 1 + (st.target - 1) * frac
      if elapsed >= SEQUENCE_DURATION then
        sizeUp[mon] = nil
      end
      return factor
    end
    local factor = 1 + (st.target - 1) * growFractionAt(elapsed)
    if elapsed >= SEQUENCE_DURATION then
      st.t0 = now()
      st.settled = true
    end
    return factor
  end

  local okBS, BattleState = pcall(require, "src.battle.BattleState")
  if okBS and BattleState and type(BattleState.drawBattlerPic) == "function"
      and not BattleState.__g9DynamaxBattleWrapped then
    BattleState.__g9DynamaxBattleWrapped = true
    local vanillaDrawBattlerPic = BattleState.drawBattlerPic
    function BattleState:drawBattlerPic(battler, x, y, scale)
      local st = battler and battler.mon and sizeUp[battler.mon]
      if st and battler == self.player and battler.sprite then
        local factor = scaleAtTime(battler.mon)
        if factor and factor ~= 1 then
          local width = battler.sprite:getWidth() * scale
          local height = battler.sprite:getHeight() * scale
          local anchorX, anchorY = x + width / 2, y + height
          love.graphics.push()
          love.graphics.translate(anchorX, anchorY)
          love.graphics.scale(factor, factor)
          love.graphics.translate(-anchorX, -anchorY)
          vanillaDrawBattlerPic(self, battler, x, y, scale)
          love.graphics.pop()
          return
        end
      end
      return vanillaDrawBattlerPic(self, battler, x, y, scale)
    end
  end

  -- ---------------------------------------------------------------------
  -- Wiring: subscribe to the trigger, start the grow tween on apply,
  -- shrink on revert, and defensively clear all markers on battle end
  -- (battle_forms emits a revert itself on teardown, but a battle ending
  -- mid-Dynamax should never leave a stale marker behind).
  -- ---------------------------------------------------------------------
  mod.events:on(appliedEvent, function(ev)
    local mon = ev and ev.mon
    if not mon then return end
    local effective = handleApplied(ev)
    if effective and not skipAnimationOption() then
      sizeUp[mon] = { target = sizeOption(), t0 = now(), shrinking = false }
    end
  end)
  mod.events:on(revertedEvent, function(ev)
    handleReverted(ev)
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, b in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      local mon = b and (b.mon or b)
      if mon then
        mon.__g9Dynamaxed = nil
        sizeUp[mon] = nil
      end
    end
  end)

  mod.log:info("galar_gmax_dex: dynamax_battle installed (consumes battle_forms' "
    .. "dynamax_applied/reverted -- Dynamax Level drive, Gen 1 size-up; Max Move secondaries now live in max_move_subeffects.lua)")
  return mod.exports
end
