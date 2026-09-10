-- Dev Tools > DEVSTATS: a diagnostic party-submenu screen for the
-- selected Pokemon, gated entirely behind the "dev_tools" option
-- (options.lua) -- OFF by default, adds nothing to the party submenu
-- when off.
--
-- REBUILT (2026-08-27) after the wide-canvas version crashed silently on
-- selection, no error dialog shown at all. Diagnosed by comparing against
-- mods/learn-any-move's own real, confirmed-working (both generations)
-- party-submenu screen rather than guessing further -- that mod (left
-- untouched, per explicit instruction) establishes the ACTUAL safe
-- pattern this file was missing on two counts:
--   1. Plain 160x144 UI size, never touching Renderer:setUISize at all.
--      The 256x144 wide-canvas technique this file used to copy from
--      stats/modern_stats_screen.lua is exactly the thing THAT screen's
--      own "not yet verified against Gen 2" boot gate was protecting
--      against -- removing that gate without also dropping the technique
--      it was guarding left the real hazard in place.
--   2. Screen.new/:update/:draw all run through pcall, same as learn-
--      any-move's own safeCall/onSelect pattern -- a failure inside any
--      of them marks the screen broken and pops it off the stack next
--      frame (or refuses to open at all), logged via mod.log:warn,
--      instead of propagating an uncaught error with no visible dialog.
--
-- Three pages ("windows"), cycled with A, same content plan as before,
-- laid out for the real 160px width instead of the removed 256px one:
--   1. Identity/mechanics: ability, Nature, Tera Type, Dynamax Level,
--      Gigantamax Factor on/off, the six real combat stats (mon.stats --
--      already the full BST+EV+IV+Nature computation) plus their sum.
--   2. EV distribution -- mon.evs, keyed by ModernStats.ORDER's own
--      short stat names ("hp"/"atk"/"def"/"spa"/"spd"/"spe"), each shown
--      as a number plus a bar scaled to the real 252-per-stat cap, and
--      the real 510 total cap.
--   3. IV distribution -- mon.ivs, same key convention, bars scaled to
--      the real 0-31 range.
--
-- Confirmed real on both generations, same grounding as before: the
-- "ui.party.submenu" hook, item shape (id+label), .onSelect dispatch,
-- and mon.stats/ivs/evs/ability/nature/teraType/dynamaxLevel field shapes
-- are all identical across engines (src/ui/gen2/PartyMenu.lua:230/450,
-- combat/gen2_modern_stats.lua's own applyComputedStats).
return function(mod)
  local ModernStats = mod.exports.ModernStats
  local Font = require("src.render.Font")

  local STAT_LABEL = { hp = "HP", atk = "ATK", def = "DEF", spa = "SPA", spd = "SPD", spe = "SPE" }
  local STAT_ORDER = ModernStats.ORDER -- {"hp","atk","def","spa","spd","spe"}

  local UI_W, UI_H = 160, 144
  local NONE = "----"

  local function safeText(value)
    if value == nil or tostring(value) == "" then return NONE end
    return tostring(value)
  end

  local function row(text, y)
    Font.draw(text, 4, y)
  end

  -- Same idiom learn-any-move's own drawList/drawChooseSlot use for a
  -- simple label:value line -- one string, one draw call, no column math
  -- that assumes the wide canvas this file no longer has.
  local function labelValue(label, value, y)
    row(label .. ": " .. safeText(value), y)
  end

  -- A plain filled-rectangle bar -- the simplest reliable "distribution"
  -- visual this engine's own primitives support without a new asset.
  -- Clamped so an out-of-range value never overdraws the box.
  local function drawBar(x, y, barWidth, barHeight, value, max)
    local frac = max > 0 and math.max(0, math.min(1, (value or 0) / max)) or 0
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.rectangle("fill", x, y, barWidth, barHeight)
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.rectangle("line", x, y, barWidth, barHeight)
    if frac > 0 then
      love.graphics.rectangle("fill", x, y, barWidth * frac, barHeight)
    end
    love.graphics.setColor(0, 0, 0, 1)
  end

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true
  Screen.screenId = "GgdDevStats"

  function Screen:uiSize()
    return UI_W, UI_H
  end

  function Screen.new(game, mon)
    local def = game.data.pokemon[mon.species]
    ModernStats.ensure(def, mon)
    -- Same gap as modern_stats_screen.lua's own Screen.new: ability/nature
    -- generation is otherwise only wired to battle.started, so a party
    -- mon opened here before its first battle still shows a nil
    -- ability/nature. Both generate functions are idempotent, so calling
    -- them on every open is safe -- matches the "derive on demand" ensure
    -- above already relies on.
    local nd = mod.find and mod.find("national_dex")
    ModernStats.generateAbility(mon, ModernStats.resolveAbilities(mon.species, nd and nd.exports))
    ModernStats.generateNature(mon)
    return setmetatable({ game = game, mon = mon, page = 1, broken = false }, Screen)
  end

  local function safeCall(self, label, fn)
    local ok, err = pcall(fn)
    if not ok then
      mod.log:warn("g9-battle-engine-beta: dev_stats_screen: %s errored, closing (%s)", label, tostring(err))
      self.broken = true
    end
  end

  function Screen:update(dt)
    if self.broken then
      if self.game and self.game.stack then self.game.stack:pop() end
      return
    end
    safeCall(self, "update", function()
      local input = self.game.input
      if input:wasPressed("a") then
        self.page = self.page % 3 + 1
      elseif input:wasPressed("b") then
        self.game.stack:pop()
      end
    end)
  end

  function Screen:drawPageOne()
    local mon = self.mon
    row(("DEVSTATS %d/3 IDENTITY"):format(self.page), 2)

    labelValue("ABILITY", mon.ability, 16)
    labelValue("NATURE", mon.nature, 27)
    -- Real fix, explicit user request: raw mon.teraType reads whatever
    -- happens to already be stored, which for a mon that has never
    -- Terastallized (its own storage's only prior writer, combat/
    -- modern_tera.lua, gated on mon.teraActive -- itself currently inert,
    -- see that file's own header) is always nil, showing blank here even
    -- though a real initial type is defined. mod.exports.getTeraType(mon)
    -- is the same lazy-roll-then-persist function that writer already
    -- used -- calling it here (self-heals into mon.teraType permanently,
    -- so this same call is also what SAVES the initial roll, satisfying
    -- "not only on Terastallize") means simply opening this screen is now
    -- enough to both roll AND persist the real initial type.
    local teraType = mod.exports.getTeraType and mod.exports.getTeraType(mon)
    labelValue("TERA", teraType, 38)
    -- Same fix as modern_stats_screen.lua: Dynamax Level is per-save, not
    -- per-mon (dynamax_state.lua's own storage contract) -- mon.dynamaxLevel
    -- never actually exists as a field.
    local dmaxLevel = mod.exports.getDynamaxLevel and mod.exports.getDynamaxLevel()
    labelValue("DMAX LVL", dmaxLevel, 49)
    local gFactor = mod.exports.getGigantamaxFactor and mod.exports.getGigantamaxFactor(mon)
    labelValue("G-FACTOR", gFactor and "ON" or "OFF", 60)

    row("COMBAT STATS", 74)
    local stats = {
      { "HP", mon.stats and mon.stats.hp or 0 },
      { "ATK", mon.stats and mon.stats.attack or 0 },
      { "DEF", mon.stats and mon.stats.defense or 0 },
      { "SPA", mon.stats and (mon.stats.spa or mon.stats.special or 0) or 0 },
      { "SPD", mon.stats and (mon.stats.spd or mon.stats.special or 0) or 0 },
      { "SPE", mon.stats and mon.stats.speed or 0 },
    }
    local total = 0
    for i, s in ipairs(stats) do
      row(("%-4s%3d"):format(s[1], s[2]), 74 + i * 9)
      total = total + s[2]
    end
    row(("TOTAL %4d"):format(total), 74 + 7 * 9)
  end

  function Screen:drawDistributionPage(title, store, max)
    row(("DEVSTATS %d/3 %s"):format(self.page, title), 2)
    local total = 0
    for i, key in ipairs(STAT_ORDER) do
      local y = 16 + (i - 1) * 20
      local value = store and store[key] or 0
      total = total + value
      row(("%s %3d"):format(STAT_LABEL[key], value), y)
      drawBar(4, y + 9, 120, 6, value, max)
    end
    row(("TOTAL %4d"):format(total), 16 + 6 * 20)
  end

  function Screen:draw()
    if self.broken then return end
    safeCall(self, "draw", function()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, UI_W, UI_H)
      love.graphics.setColor(0, 0, 0, 1)
      if self.page == 2 then
        self:drawDistributionPage("EV DIST", self.mon.evs, 252)
      elseif self.page == 3 then
        self:drawDistributionPage("IV DIST", self.mon.ivs, 31)
      else
        self:drawPageOne()
      end
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end

  mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    local result = nextFn(game, items, mon, ctx)
    if type(result) ~= "table" then result = items end
    -- Field-list only, same scope modern_stats_screen.lua's own STATS
    -- replacement already uses (not the in-battle SWITCH/STATS/CANCEL
    -- box). Same NUM_MONMENU_ITEMS ceiling learn-any-move's own hook
    -- checks (src/ui/gen2/PartyMenu.lua's real submenu box capacity).
    local NUM_MONMENU_ITEMS = 8
    if not (ctx and ctx.battle) and #result < NUM_MONMENU_ITEMS
        and mod.options:get("dev_tools") == "true" then
      result[#result + 1] = {
        id = "DEVSTATS", label = "DEVSTATS",
        onSelect = function(selectedMon, selectedGame)
          local ok, screen = pcall(Screen.new, selectedGame, selectedMon)
          if ok and screen then
            selectedGame.stack:push(screen)
          else
            mod.log:warn("g9-battle-engine-beta: dev_stats_screen: Screen.new errored, not opening (%s)", tostring(screen))
          end
        end,
      }
    end
    return result
  end, 0)

  mod.log:info("g9-battle-engine-beta: dev_stats_screen installed (Dev Tools > DEVSTATS)")
end
