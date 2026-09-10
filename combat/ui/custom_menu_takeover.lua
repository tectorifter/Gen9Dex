-- GalarGmaxDex's own reskin of the title screen menu, the in-game start
-- menu, the options menu, and the mod manager -- gated on the same
-- custom_menu_scene option custom_party_scene.lua uses. Same two-hook
-- pattern as that file (screen.render_visible to hide native draw,
-- render.hud to draw our own after composite); native update()/input is
-- never touched, so cursor movement, scrolling, option stepping, mod
-- toggling, everything already-working keeps working exactly as before
-- -- only the pixels change.
--
-- Ground rules, confirmed against real engine source before writing this:
--   - Title menu AND the in-game start menu are BOTH just instances of
--     the one generic src/ui/Menu.lua class (Menu.new(game, items, opts),
--     self.items/self.index/self.scroll/self.maxVisible) -- confirmed by
--     reading TitleState:openMenu (TitleState.lua:368-407, builds items,
--     Menu.new(...), game.stack:push(menu) -- all inline, the menu is
--     never returned to a caller) and StartMenu.new (StartMenu.lua:19-186,
--     builds items, returns Menu.new(...) directly). Since Menu is also
--     almost certainly used elsewhere (shop lists etc) that this pass
--     hasn't touched, taking over EVERY Menu instance would be too broad
--     -- instead this file tags only the two menus it means to reskin,
--     by wrapping Menu.new itself (stamps __ggdKind from an ambient flag)
--     together with TitleState.openMenu (sets the flag around the vanilla
--     call, since openMenu pushes internally and never hands the menu
--     back) and StartMenu.new (sets the flag around its own vanilla call,
--     simpler since it does return the menu). Every other Menu instance
--     (no __ggdKind stamped) is completely untouched.
--   - src/ui/OptionsMenu.lua: self.game/self.rows/self.index/self.scroll
--     (OptionsMenu.new, line 529-541, 0-based scroll, cursor 1..#rows+1
--     with #rows+1 being a virtual CANCEL row). Row shape:
--     {id=, label=, value=function(game)->string, step=function(game,dir),
--     activate=function(game)}. Left/right/A already drive row.step or
--     row.activate via native update() -- untouched here, only value
--     display is read.
--   - src/mods/ManagerState.lua: self.game/self.screen/self.tab/
--     self.cursor/self.scroll (1-based; ManagerState.new, line 169-180)
--     and the real instance method self:rowsForScreen() (line 388-403),
--     which already dispatches on self.screen/self.tab to whichever of
--     modRows/profileRows/errorRows/detailRows/permissionRows/applyRows
--     applies -- reused directly rather than reimplemented. Row shapes
--     vary (mod/profile/header/inert/action-bearing) but all carry
--     .label, .header, .inert -- enough for a generic display. Overlay
--     shape: self.overlay = {kind="ok"|"confirm", lines={...}, index=}
--     (confirmed at ManagerState.lua:583/601/606).
--   - "MOD MENUS" hub: gen1_modern_ui's own feature (confirmed at that
--     mod's main.lua, ~line 2746-2842), built by wrapping
--     ui.start_menu.items and diffing the post-chain item list against
--     a pre-chain snapshot to find mod-added rows, grouping them behind
--     one synthetic row. Since gen1_modern_ui is not a dependency this
--     project keeps around, this file replicates the same grouping
--     behavior natively: a HIGH-priority ui.start_menu.items wrap runs
--     first in the chain (Hooks.lua sorts descending by priority, so the
--     highest-priority link sees the ORIGINAL unhooked items as its own
--     `items` argument, then calls next() to let every other mod's wrap
--     run before the composed result bubbles back) -- confirmed real,
--     same Hooks:call mechanics GalarGmaxDex's own damage/party hooks
--     already rely on. No pinning (SELECT to promote a row back to
--     top-level) is implemented -- an honest, flagged scope limit, not
--     silently dropped; gen1_modern_ui's own pin persistence is more
--     machinery than this pass needs.
return function(mod, Theme)
  -- TEMPORARY: disabled entirely on a Gen 2 boot, confirmed root cause of
  -- a party-window crash. src.ui.StartMenu is a LIVE Gen2Compat facade
  -- over src.ui.gen2.StartMenu -- Gold's real native start-menu class
  -- (Gen2Compat.lua's own COVERAGE["src.ui.StartMenu"]: kind="facade",
  -- target="src.ui.gen2.StartMenu") -- and the facade's __newindex writes
  -- monkey-patches straight THROUGH onto that real class table, not a
  -- harmless copy. The Menu.new/TitleState:openMenu/StartMenu.new wraps
  -- below were installed completely unconditionally (no sceneActive()
  -- gate on the wrap installation itself, only on what they draw/stamp),
  -- so they were replacing a piece of Gold's actual start-menu
  -- construction -- the exact menu that leads to POKéMON -> the party
  -- window -- on every boot, both generations, regardless of the
  -- custom_menu_scene option. Bailing out here before any require/patch
  -- runs removes this file from Gen 2's menu pipeline entirely. Revisit
  -- with a real Gen 2-safe rewrite before re-enabling.
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.generation(GameVersion.get()) == 2 then
    mod.log:info("galar_gmax_dex: custom_menu_takeover: disabled on Gen 2 boot (temporary, see file header)")
    return
  end

  local Menu = require("src.ui.Menu")
  local TitleState = require("src.ui.TitleState")
  local StartMenu = require("src.ui.StartMenu")
  local OptionsMenu = require("src.ui.OptionsMenu")
  local ManagerState = require("src.mods.ManagerState")

  if Menu.galarMenuTakeoverHook then return end
  Menu.galarMenuTakeoverHook = true

  local function sceneActive()
    return mod.options:get("custom_menu_scene") == "true"
  end

  local COLOR_BORDER = Theme.COLOR_BORDER
  local COLOR_TEXT = Theme.COLOR_TEXT
  local COLOR_MUTED = Theme.COLOR_MUTED
  local panel = Theme.panel
  local printText = Theme.printText
  local fitName = Theme.fitName
  local drawCursor = Theme.drawCursor

  ------------------------------------------------------------------
  -- Title menu / start menu tagging (see header comment for why).
  ------------------------------------------------------------------
  local pendingMenuKind = nil

  local vanillaMenuNew = Menu.new
  function Menu.new(...)
    local m = vanillaMenuNew(...)
    if pendingMenuKind then m.__ggdKind = pendingMenuKind end
    return m
  end

  -- The vanilla title menu should stay fully native. The old takeover
  -- path used to clear titleUiBox so the custom overlay could replace the
  -- whole menu, but that behavior is no longer needed here. We keep the
  -- start-menu shortcut injection intact and leave the title screen alone.
  local vanillaOpenMenu = TitleState.openMenu
  function TitleState:openMenu()
    local ok, err = pcall(vanillaOpenMenu, self)
    if not ok then error(err, 0) end
  end

  local vanillaStartMenuNew = StartMenu.new
  function StartMenu.new(game)
    local ok, m = pcall(vanillaStartMenuNew, game)
    if not ok then error(m, 0) end
    return m
  end

  local MENU_TITLES = { title = "MAIN MENU", start = "PAUSE MENU", modmenus = "MOD MENUS" }

  local function menuActive(state)
    return sceneActive() and getmetatable(state) == Menu and state.__ggdKind == "modmenus"
  end

  ------------------------------------------------------------------
  -- Menu (title/start/modmenus) goes back to the plain two-hook
  -- technique -- screen.render_visible=false below, render.hud draws
  -- ours -- now that clearing titleUiBox (above) removes the one real
  -- obstacle to it (the GRAYS zone carve-out that only made sense while
  -- the native box was actually opaque). Two earlier attempts at
  -- "keep native drawing for its side effects, hide/replace the pixels"
  -- (full colorMask, then a surgical box-only redraw) both either
  -- bled the zone onto the raw background or left a visible empty native
  -- box/border showing through -- fixing the ROOT cause (the zone
  -- depending on content that no longer exists once we hide the box) is
  -- what actually made full suppression safe, rather than working around
  -- it draw-call by draw-call.
  --
  -- OptionsMenu/ManagerState have no titleUiBox-style zone dependency
  -- reported against them, so they keep the simpler colorMask technique
  -- (full native draw, invisible pixels) -- nothing suggests they need
  -- this same treatment.
  ------------------------------------------------------------------
  local vanillaOptionsDraw = OptionsMenu.draw
  function OptionsMenu:draw()
    return vanillaOptionsDraw(self)
  end

  local vanillaManagerDraw = ManagerState.draw
  function ManagerState:draw()
    return vanillaManagerDraw(self)
  end

  local function drawGenericMenu(state, x, y, w, h)
    panel(x, y, w, h)
    printText(MENU_TITLES[state.__ggdKind] or "", x + 12, y + 10, 16, COLOR_BORDER)
    local items = state.items or {}
    local visible = state.maxVisible and math.min(state.maxVisible, #items) or #items
    local scroll = state.scroll or 0
    local top = y + 32
    local rowH = math.min(20, (h - 40) / math.max(1, visible))
    for row = 1, visible do
      local i = scroll + row
      local item = items[i]
      if not item then break end
      local ry = top + (row - 1) * rowH
      local selected = i == state.index
      printText(fitName(item.label or "", w - 40, 15), x + 16, ry, 15,
        selected and COLOR_TEXT or COLOR_MUTED)
      if selected then drawCursor(x + 4, ry - 1) end
    end
  end

  ------------------------------------------------------------------
  -- Options menu
  ------------------------------------------------------------------
  local function optionsActive(state)
    return sceneActive() and getmetatable(state) == OptionsMenu
  end

  local function drawOptionsMenu(state, x, y, w, h)
    panel(x, y, w, h)
    printText("OPTIONS", x + 12, y + 10, 16, COLOR_BORDER)
    local rows = state.rows or {}
    local cancelRow = #rows + 1
    local visible = 8
    local scroll = state.scroll or 0
    local top = y + 32
    local rowH = math.min(20, (h - 40) / visible)
    for row = 1, visible do
      local i = scroll + row
      if i > cancelRow then break end
      local ry = top + (row - 1) * rowH
      local selected = i == state.index
      if i <= #rows then
        local r = rows[i]
        printText(r.label or "", x + 16, ry, 15, selected and COLOR_TEXT or COLOR_MUTED)
        local ok, val = pcall(r.value, state.game)
        if ok and val then
          printText(fitName(tostring(val), math.max(40, w * 0.32), 14), x + w - 108, ry, 14, COLOR_MUTED)
        end
      else
        printText("CANCEL", x + 16, ry, 15, selected and COLOR_TEXT or COLOR_MUTED)
      end
      if selected then drawCursor(x + 4, ry - 1) end
    end
  end

  ------------------------------------------------------------------
  -- Mod manager
  ------------------------------------------------------------------
  local MANAGER_TABS = { "MODS", "PROFILES", "ERRORS" }

  local function managerActive(state)
    return sceneActive() and getmetatable(state) == ManagerState
  end

  local function drawManagerOverlay(state, x, y, w, h)
    local ov = state.overlay
    if not ov then return end
    local lines = ov.lines or {}
    local pw = 360
    local ph = 60 + #lines * 24 + (ov.kind == "confirm" and 40 or 0)
    local px, py = x + w / 2 - pw / 2, y + h / 2 - ph / 2
    panel(px, py, pw, ph, true)
    for i, line in ipairs(lines) do
      printText(line, px + 20, py + 16 + (i - 1) * 24, 16, Theme.COLOR_TEXT_ON_LIGHT)
    end
    if ov.kind == "confirm" then
      local yesY = py + ph - 36
      printText("YES", px + 60, yesY, 17,
        ov.index == 1 and Theme.COLOR_TEXT_ON_LIGHT or COLOR_MUTED)
      printText("NO", px + 160, yesY, 17,
        ov.index == 2 and Theme.COLOR_TEXT_ON_LIGHT or COLOR_MUTED)
    end
  end

  -- The "options" sub-screen (a mod's own auto-generated settings, opened
  -- from detail's "OPTIONS.." row) is NOT one of rowsForScreen()'s cases
  -- (ManagerState.lua:388-403 only handles list/detail/errors/
  -- permissions/apply, falling through to `return {}` for anything else)
  -- -- it lives in a separate field, self.optionRows, built by
  -- ManagerState:openOptions/:buildOptionRows (lines 991-997) and read by
  -- native draw via OptionRows.draw(self.game, self.optionRows or {}, ...)
  -- (line 1178). Reading rowsForScreen() alone left this screen blank.
  -- Row shape matches OptionsMenu's own (id/label/value/step/activate).
  -- Matching native's own visible-row count is load-bearing, not just
  -- cosmetic: ManagerState:moveCursor only scrolls self.scroll once the
  -- cursor passes scroll+LIST_ROWS-1 (ManagerState.lua:457-458, LIST_ROWS
  -- =11), and updateOptions scrolls via OptionRows.clampScroll against
  -- OptionRows.VISIBLE=4 (OptionRows.lua:14/23-24) -- native decides WHEN
  -- to scroll, we only decide how many rows to draw starting at
  -- state.scroll. An earlier hardcoded `visible = 9` showed fewer rows
  -- than LIST_ROWS=11 actually lets the cursor reach before scrolling,
  -- so the cursor could sit 2-3 rows below the last one drawn with
  -- nothing visibly there yet -- confirmed live, exactly the reported
  -- "have to move 2-3 rows past what's shown" symptom.
  local MANAGER_LIST_ROWS = 11
  local MANAGER_OPTION_ROWS = 4

  local function drawManagerRows(state, rows, x, y, headerY, w, h, isOptionRows)
    local visible = isOptionRows and MANAGER_OPTION_ROWS or MANAGER_LIST_ROWS
    -- ManagerState:goTo (ManagerState.lua:412) seeds self.scroll
    -- DIFFERENTLY per screen: 0 for "options" (matching OptionRows/
    -- OptionsMenu's 0-based convention), 1 for every other sub-screen
    -- (list/detail/errors/permissions/apply). Treating both as 1-based
    -- turned options' already-zero scroll into -1, landing every row
    -- index on rows[0] (always nil) and breaking out before drawing
    -- anything -- the exact cause of the blank options screen.
    local scroll = isOptionRows and (state.scroll or 0) or ((state.scroll or 1) - 1)
    -- `visible` is a scroll-window COUNT (must stay accurate to native,
    -- above), not a layout hint -- stretching rows to fill the whole
    -- panel height (up to ~1000px for 4 option rows) reads as huge gaps
    -- between them. Cap row height at a fixed, comfortable size instead;
    -- any leftover panel space below just stays empty rather than
    -- pulling rows apart.
    local rowH = math.min(20, (h - (headerY - y) - 20) / visible)
    local ry = headerY
    for row = 1, visible do
      local i = scroll + row
      local r = rows[i]
      if not r then break end
      local selected = i == state.cursor
      if r.header then
        printText(r.label or "", x + 16, ry, 15, COLOR_BORDER)
      else
        printText(fitName(r.label or "", w - 80, 15), x + 16, ry, 15,
          r.inert and COLOR_MUTED or (selected and COLOR_TEXT or COLOR_MUTED))
        if isOptionRows and r.value then
          local ok, val = pcall(r.value, state.game)
          if ok and val then
            printText(fitName(tostring(val), math.max(40, w * 0.28), 14), x + w - 120, ry, 14, COLOR_MUTED)
          end
        end
        if selected and not r.inert then drawCursor(x + 4, ry - 1) end
      end
      ry = ry + rowH
    end
  end

  local function drawManagerState(state, x, y, w, h)
    panel(x, y, w, h)
    local headerY = y + 16
    if state.screen == "list" then
      local tabX = x + 24
      for i, name in ipairs(MANAGER_TABS) do
        printText(name, tabX, headerY, 16, i == state.tab and COLOR_TEXT or COLOR_MUTED)
        tabX = tabX + 120
      end
      if state.banner then
        printText(state.banner, x + w - 260, headerY, 14, COLOR_BORDER)
      end
      headerY = headerY + 34
    else
      printText((state.screen or ""):upper(), x + 24, headerY, 18, COLOR_BORDER)
      headerY = headerY + 34
    end
    if state.screen == "options" then
      drawManagerRows(state, state.optionRows or {}, x, y, headerY, w, h, true)
    else
      local ok, rows = pcall(function() return state:rowsForScreen() end)
      if not ok or type(rows) ~= "table" then rows = {} end
      drawManagerRows(state, rows, x, y, headerY, w, h, false)
    end
    drawManagerOverlay(state, x, y, w, h)
  end

  ------------------------------------------------------------------
  -- MOD MENUS hub: high-priority ui.start_menu.items wrap sees the
  -- ORIGINAL vanilla items (it runs first in the sorted chain), snapshots
  -- them, then diffs what comes back through next() to find every row a
  -- mod added (including GalarGmaxDex's own "G9 DEX" row from main.lua).
  -- Those get pulled out of the top-level list and replaced with one
  -- "MOD MENUS" row that pushes a tagged Menu of just the grouped rows --
  -- reusing drawGenericMenu automatically since it's tagged the same way
  -- title/start are.
  ------------------------------------------------------------------
  local function itemKey(item)
    return item.id or ("label:" .. tostring(item.label))
  end

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local baseline = {}
    for _, it in ipairs(items) do baseline[itemKey(it)] = true end
    local out = next(game, items)
    if type(out) ~= "table" or not sceneActive() then return out end
    local grouped, kept = {}, {}
    for _, it in ipairs(out) do
      if baseline[itemKey(it)] or it.label == "MODS" then
        kept[#kept + 1] = it
      else
        grouped[#grouped + 1] = it
      end
    end
    if #grouped == 0 then return out end
    kept[#kept + 1] = {
      -- Menu:update() calls item.onSelect() with NO arguments (Menu.lua:94
      -- -- every native start/title menu row captures its own `game` via
      -- closure instead) -- this one closes over the `game` this hook was
      -- itself called with, the same convention TitleState/StartMenu's own
      -- item builders use. An earlier version of this took a `selectedGame`
      -- PARAMETER instead, matching the DIFFERENT (mon, game)-args
      -- convention ui.party.submenu entries get -- always nil here since
      -- nothing ever passed it, crashing on `selectedGame.stack:push`.
      label = "MOD MENUS",
      onSelect = function()
        local ok, err = pcall(function()
          pendingMenuKind = "modmenus"
          local menu = Menu.new(game, grouped, { tx = 4, ty = 2, tw = 12 })
          pendingMenuKind = nil
          game.stack:push(menu)
        end)
        if not ok then
          pendingMenuKind = nil
          mod.log:warn("galar_gmax_dex: custom_menu_takeover: MOD MENUS open errored: %s", tostring(err))
        end
      end,
    }
    return kept
  end, 1000)

  ------------------------------------------------------------------
  -- Hooks
  ------------------------------------------------------------------
  -- Only the grouped MOD MENUS screen uses the custom render path now.
  -- Title and pause menus stay fully vanilla, while the G9 Dex shortcut
  -- remains available from the start menu.
  mod.hooks:wrap("screen.render_visible", function(next, state)
    if menuActive(state) then return false end
    return next(state)
  end)

  local function topIf(game, predicate)
    local top = game and game.stack and game.stack.top and game.stack:top()
    if top and predicate(top) then return top end
    return nil
  end

  -- Only the grouped MOD MENUS screen gets the custom overlay. The
  -- vanilla options and manager screens should render as-is.
  local function windowRect(state, viewport, w, h)
    local kind = state.__ggdKind
    if kind == "start" then
      return w - 460, 20, 430, 420
    end
    return 30, 30, 380, 340
  end

  -- push("all")/pop() around every draw call below: Font.drawBox and
  -- native Menu:draw() both explicitly restore love.graphics.setColor
  -- when they finish (Font.lua/Menu.lua:151), and this file needs the
  -- same discipline -- confirmed live: leaving the last row's
  -- printText/drawCursor color active past the end of this hook bled a
  -- cyan/blue tint into the NEXT frame's world/sprite drawing (render.hud
  -- fires after the canvas->backbuffer blit, so nothing clears it before
  -- the next frame starts). push("all")/pop() is the same guard
  -- custom_battle_scene.lua already uses around its own native-call
  -- wrappers, applied here around OUR OWN drawing instead.
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    local menuState = topIf(game, menuActive)
    if not menuState then return end
    love.graphics.push("all")
    -- Theme.beginScaledDraw returns a VIRTUAL (w, h) to lay out against
    -- exactly like a real love.graphics.getDimensions() result -- the
    -- graphics transform (not this layout math) is what adapts to the
    -- real window/device size. See ui_theme.lua's own header for why a
    -- single min(w/ref,h/ref) scale doesn't work for phone portrait.
    local w, h = Theme.beginScaledDraw()
    local ok, err = pcall(function()
      local mx, my, mw, mh = windowRect(menuState, viewport, w, h)
      drawGenericMenu(menuState, mx, my, mw, mh)
    end)
    Theme.endScaledDraw()
    love.graphics.pop()
    if not ok then
      mod.log:warn("galar_gmax_dex: custom_menu_takeover: draw errored: %s", tostring(err))
    end
  end, 100)

  mod.log:info("galar_gmax_dex: custom_menu_takeover installed (title/start/options/mods)")
end
