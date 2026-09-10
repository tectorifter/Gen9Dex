-- Gen 2 "WIDE" -- gated on the gen2_wide_layout option (options.lua).
--
-- Confirmed via direct engine source read before writing this (not
-- assumed): Gen 2 has no equivalent to Gen 1's real WIDE layout. Gen 1's
-- WIDE gets a genuinely wider render surface via Renderer:setUISize (Gen
-- 1-only, src/core/Game.lua:473) before anything draws. Gen 2's own
-- BattleState:drawsWidescreen()/wantsFillScale() (src/ui/gen2/
-- BattleState.lua:173-174) are hardcoded true but mean something
-- completely different: Game2:drawScene (src/core/Game2.lua) fit-scales
-- the SAME fixed 160x144 panel to fill the window via Chrome.fitScale/
-- fitOrigin, then Game2 itself (not the battle state) unconditionally
-- letterboxes around that same fixed box immediately after. There is no
-- Game2-level uiSize hook a mod state can widen the way Gen 1's can --
-- doing that for real would mean wrapping Game2's own top-level draw/
-- letterbox dispatch, code every other Gen 2 screen also depends on. That
-- was weighed against a same-box reflow and the safer option was chosen
-- (this session, explicit user call).
--
-- So this is deliberately a smaller feature than Gen 1 WIDE: during move
-- select only, it shows the highlighted move's TYPE -- the one piece of
-- info Gen 2's native move list doesn't display at all (it already shows
-- name + PP natively, src/ui/gen2/BattleState.lua:3273-3274) -- on the
-- move box's own bottom row. Chrome.box(0,12,20,6) (BattleState.lua:3232)
-- is 6 rows tall; native only ever writes rows 13-16 (one per move slot,
-- `ty = 13 + (i-1)`) inside it, leaving row 17 genuinely unused during the
-- "moves" phase (row 12 is the box's own top border). Drawing there adds
-- real information without overlapping, resizing, or suppressing a single
-- pixel of anything native already draws -- same "wrap on top, never
-- replace" idiom this mod uses everywhere else for battle rendering.
--
-- Registered on battle.overlay (not a Gen2BattleState:draw wrap) for the
-- same confirmed reason custom_battle_scene.lua's own Gen 2 ring fix
-- moved there: BattleState:draw() is not the real per-frame entry point
-- for an ordinary solo-battle-state screen under Gen 2's widescreen-fit
-- dispatch, but BattleState:drawScene() (src/ui/gen2/BattleState.lua:
-- 3334-3345) fires battle.overlay unconditionally every frame, already
-- inside whichever transform is active.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local TypeChart = require("src.battle.TypeChart")
  local isGen2Boot = GameVersion.generation(GameVersion.get()) == 2

  local chromeOk, Chrome = pcall(require, "src.ui.gen2.Chrome")
  Chrome = chromeOk and Chrome or nil
  if not chromeOk and isGen2Boot then
    mod.log:warn("galar_gmax_dex: gen2_wide_scene: src.ui.gen2.Chrome not available on a gen 2 boot: %s",
      tostring(Chrome))
  end

  local gen2BattleOk, Gen2Battle = pcall(require, "src.battle.gen2.Battle")
  Gen2Battle = gen2BattleOk and Gen2Battle or nil
  if not gen2BattleOk and isGen2Boot then
    mod.log:warn("galar_gmax_dex: gen2_wide_scene: src.battle.gen2.Battle not available on a gen 2 boot: %s",
      tostring(Gen2Battle))
  end

  local function isGen2Battle(battle)
    return Gen2Battle ~= nil and battle ~= nil and getmetatable(battle) == Gen2Battle
  end

  local function wideActive()
    return mod.options:get("gen2_wide_layout") == "true"
  end

  mod.hooks:wrap("battle.overlay", function(next, ctx)
    next(ctx)
    if not (Chrome and wideActive() and ctx and ctx.battle and isGen2Battle(ctx.battle)
        and ctx.phase == "moves" and ctx.playerMoves) then
      return
    end
    local ok, err = pcall(function()
      local moves = ctx:playerMoves()
      local move = moves and moves[ctx.moveIndex or 1]
      if not move then return end
      local def = ctx.game and ctx.game.data and ctx.game.data.moves and ctx.game.data.moves[move.id]
      if not def or not def.type then return end
      Chrome.print(("TYPE: %s"):format(TypeChart.displayName(def.type)), 2, 17)
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: gen2_wide_scene: type readout errored: %s", tostring(err))
    end
  end)

  mod.log:info("galar_gmax_dex: gen2_wide_scene installed (move-type readout, gen2_wide_layout option)")
end
