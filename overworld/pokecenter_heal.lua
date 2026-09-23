-- POKeMON CENTER nurse takeover (round 296) -- explicit user spec:
--
--   "we need to take over healing by pokemon center, it's healing under our HP
--    system by modern stats, so in gen 1 and gen 2 make it so healing in
--    pokemon center full heals to our modern stats max hp of each pokemon and
--    makes player turn away from the NPC (face south after done talking) make
--    sure NPC still has pokerus report to player and all of its sequencing.
--    lastly, shorten healing chats to a single message> player talks> no
--    pokerus > route one. yes pokerus> pokerus route> route 1. route one just
--    sends "We restore your tired Pokemon to full health." we remove the
--    questioning and welcome message. this shortening sequence is to be a
--    toggle on/off in g9-gui. dont play the pokeball placing in machine
--    sequence before healing."
--
-- UNCONDITIONAL (both generations, whatever the toggle says):
--   * Full heal to the MODERN max. Vanilla heals to `mon.stats.hp`, which is
--     this mod's modern figure only because recalcAll has already rewritten
--     the stat block -- so this file runs the same ModernStats.ensure +
--     recalcAll pair the TRAIN editor and stats/ev_yield_on_faint.lua use
--     (ensure derives a legacy mon's IVs/EVs once from its DVs/statExp;
--     recalcAll then recomputes all six from the modern base stats), and only
--     then restores HP to that new max. Eggs are skipped outright: an egg is a
--     FAINTED mon by rule (stats/egg_normalize.lua pins hp = 0 and every
--     battle path refuses it), and a center heal is exactly what would
--     resurrect one.
--   * Player faces SOUTH when the conversation is over. The player faces up at
--     the counter, so "turn away" is player.facing = "down".
--   * The pokeball-into-the-machine sequence never plays. Gen 1's `healAnim`
--     is skipped because this file owns the flow; Gen 2's
--     World:startHealMachineAnim is wrapped to resume immediately.
--   * The Pokerus report and ALL of its sequencing is preserved -- the ROM's
--     own NursePokerusText, the ENGINE_CAUGHT_POKERUS engine flag and the
--     SPECIALCALL_POKERUS phone call, behind the cart's own two guards
--     (checkphonecall / checkflag).
--
-- TOGGLED (g9-gui option `short_heal_chat`, default ON):
--   * ON: player talks -> (pokerus? pokerus report first) -> the single
--     route-one line -> done. Welcome / "shall we heal?" / HEAL-CANCEL /
--     "we'll need your Pokemon" / "fighting fit" / goodbye are all gone.
--   * OFF: the vanilla chat is kept. Gen 1's is reproduced here from the same
--     ROM strings (`_PokemonCenterWelcomeText`, `_ShallWeHealYourPokemonText`,
--     `_NeedYourPokemonText`, `_PokemonFightingFitText`,
--     `_PokemonCenterFarewellText`) with the HEAL/CANCEL box; Gen 2 lets the
--     cart's own extracted `PokecenterNurseScript` run through the VM
--     untouched, so its time-of-day greeting, choice and pokerus branch are
--     byte-identical to vanilla. Either way the unconditional rules above
--     still hold -- no machine, modern heal, face south.
--
-- HOW THE NURSE IS FOUND
--   * Gen 1: the nurse is dispatched by the `entry.nurse` TX_SCRIPT marker
--     into OverworldState:nurseHeal, so this file wraps that method -- the
--     identification is the dispatch itself.
--   * Gen 2: the nurse is an ordinary map object (SPRITE_NURSE behind a
--     counter) whose script is a per-map stub that `jumpstd
--     PokecenterNurseScript` (confirmed against the real maps: e.g.
--     maps/CherrygrovePokecenter1F.asm). It is recognised EITHER by sprite
--     name (world.constants.spriteOrder[def.sprite] == "SPRITE_NURSE") OR by
--     its script's rows naming the std script -- two independent signals, so
--     a ROM whose sprite order differs still matches.
--
-- WHY THE FACADE SEAMS AND NOT THE WORLD.  On Gold `src.world.OverworldController`
-- IS a dispatch facade (src/mods/Gen2Compat.lua), and World:interactBody calls
-- `Gen1Facade.talkToWrapper()(self, npc)` before its built-in dispatch -- a
-- `true` return suppresses the built-in path, anything else lets it run. So
-- setting OverworldController.talkTo is the one supported seam for a Gen 2
-- talk; the same module on Gen 1 IS the live OverworldState, which is why the
-- Gen 1 half wraps nurseHeal on it instead. `OverworldController.update` is
-- called from World:step's tail by Gen2Compat.worldTick, and is used only as
-- the "the native chat has settled, now face south" watcher for the toggle-OFF
-- Gen 2 path (World:busy() is the settle test).
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Strings = require("src.core.Strings")
  local ModernStats = mod.exports.ModernStats

  if type(ModernStats) ~= "table" then
    mod.log:warn("g9-battle-engine: pokecenter_heal: ModernStats export missing, skipped")
    return
  end

  local IS_GEN2 = false
  do
    local ok, gen = pcall(function() return GameVersion.generation(GameVersion.get()) end)
    IS_GEN2 = ok and gen == 2
  end

  -- The one authored line (explicit user text). Soft-wraps in the box.
  local ROUTE_ONE = "We restore your tired Pokémon to full health."
  -- Only used if the ROM's own NursePokerusText cannot be resolved.
  local POKERUS_FALLBACK = "Your POKéMON may have\ncaught Pokérus!"

  local function nationalDexExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  -- require("src.core.Game") is the Gen2Compat facade on Gold and the live
  -- Game module on Red/Blue/Yellow -- neither .save nor .data is translated,
  -- so both resolve through to whichever game is actually running.
  local function liveGame()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game end
    return nil
  end

  local function isEgg(mon)
    return type(mon) == "table" and mon.isEgg == true
  end

  local function speciesDefFor(game, mon)
    local data = game and game.data
    local tbl = data and data.pokemon
    return tbl and mon and mon.species and tbl[mon.species] or nil
  end

  -- Recompute a mon's modern stat block and answer its modern max HP.
  -- ensure() is the fill-only first pass (IVs/EVs from DVs/statExp for a mon
  -- that has never been through the modern layer); recalcAll() then writes all
  -- six stats from those plus the modern base stats. On Gen 2 the native
  -- specialAttack/specialDefense aliases and mon.maxHp are mirrored, exactly
  -- as stats/gen2_modern_stats.lua's applyComputedStats does.
  local function modernMaxHp(game, mon, gen2)
    if type(mon) ~= "table" then return nil end
    local def = ModernStats.resolveBase(mon.species, speciesDefFor(game, mon), nationalDexExports())
    if type(def) ~= "table" or type(def.baseStats) ~= "table" then
      return (mon.stats and mon.stats.hp) or mon.maxHp or mon.hp
    end
    ModernStats.ensure(def, mon)
    ModernStats.recalcAll(def, mon)
    mon.stats = mon.stats or {}
    if gen2 then
      mon.stats.specialAttack = mon.stats.spa
      mon.stats.specialDefense = mon.stats.spd
      mon.maxHp = mon.stats.hp
    else
      -- Gen 1 has ONE Special key in the native block, and the engine's own
      -- Stats.ensure rebuilds a stat block from dvs/statExp the moment any of
      -- its five Gen 1 keys is missing -- which would throw this modern heal
      -- away.  Mirroring Spa keeps the block complete AND current, exactly as
      -- stats/train_screen.lua's applyModern and stats/ev_yield_on_faint.lua
      -- do for the same reason.
      mon.stats.special = mon.stats.spa
    end
    return mon.stats.hp
  end
  mod.exports.pokecenterModernMaxHp = modernMaxHp

  -- Gen 1: Pokemon.heal is the engine's own center-heal (hp = stats.hp, status
  -- cleared, PP restored to base + PP-Up bonus), so running it AFTER the
  -- modern recalc makes it heal to the modern max with no reimplementation.
  local function fullHealGen1(game, mon)
    if isEgg(mon) then return end
    modernMaxHp(game, mon, false)
    local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
    if ok and type(Pokemon) == "table" and type(Pokemon.heal) == "function" then
      pcall(Pokemon.heal, mon)
    else
      mon.hp = (mon.stats and mon.stats.hp) or mon.hp
      mon.status = nil
    end
  end

  -- Gen 2: World:healParty's own rules (hp = maxHp, status/statusTurns clear,
  -- PP = maxPp) against the modern max.
  local function fullHealGen2(game, mon)
    if isEgg(mon) then return end
    local maxHp = modernMaxHp(game, mon, true)
    if not maxHp or maxHp <= 0 then return end
    mon.hp = maxHp
    mon.status = nil
    mon.statusTurns = nil
    for _, mv in ipairs(mon.moves or {}) do
      if type(mv) == "table" then mv.pp = mv.maxPp or mv.pp end
    end
  end

  local function healParty(game, gen2)
    local save = game and game.save
    for _, mon in ipairs((save and save.party) or {}) do
      local fn = gen2 and fullHealGen2 or fullHealGen1
      pcall(fn, game, mon)
    end
  end
  mod.exports.pokecenterHealParty = healParty

  -- Cross-mod options read: mod.options:get only ever sees the CALLING mod's
  -- own bucket, so g9-gui publishes its SHORT HEAL CHAT toggle through
  -- mod.exports.  Read LAZILY (every mod is loaded long before anyone talks to
  -- a nurse) and never cached, so flipping the row takes effect on the next
  -- conversation.
  --
  -- The answer is accepted in every shape a choice row can take -- a real
  -- boolean, the "true"/"false" STRINGS the Mod Manager stores, "on"/"off", a
  -- number -- because a reader that insists on a boolean falls back to its
  -- default on any other shape, and the default here is ON.  That failure is
  -- invisible: the row looks like it does nothing at all.
  --
  -- TWO channels are tried in order, so a g9-gui that cannot be resolved
  -- through mod.find (not yet run, disabled, failed, a partial install, an
  -- older loader) still answers:
  --   1. mod.find("g9-gui").exports.shortHealChatEnabled() -- the documented
  --      cross-mod route, and the only channel that is g9-gui's own live value.
  --   2. the persisted row straight out of the live save
  --      (save.options.modOptions["g9-gui"].short_heal_chat) -- the same table
  --      ManagerState:setOption writes, so it tracks the Mod Manager.
  -- With neither available the shortening keeps the historical default (ON),
  -- exactly as it did before g9-gui existed.
  local function coerceOnOff(v)
    if v == nil then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    local s = tostring(v):lower()
    if s == "false" or s == "off" or s == "0" or s == "no" then return false end
    if s == "true" or s == "on" or s == "1" or s == "yes" then return true end
    return nil
  end

  -- The resolved value is logged ONCE per session (the first time a nurse is
  -- talked to), so "the option does nothing" becomes a readable line naming the
  -- channel and the raw value that answered.
  local shortReported = false
  local function reportShortChat(on, how)
    if shortReported then return end
    shortReported = true
    mod.log:info("g9-battle-engine: pokecenter_heal: SHORT HEAL CHAT is %s (%s)",
      on and "ON" or "OFF", how)
  end

  local function shortChatEnabled()
    -- channel 1: g9-gui's own published export
    local okFind, handle = pcall(function()
      return mod.find and mod.find("g9-gui")
    end)
    if not okFind then handle = nil end
    local fn = handle and handle.exports and handle.exports.shortHealChatEnabled
    if type(fn) == "function" then
      local ok, raw = pcall(fn)
      if ok then
        local v = coerceOnOff(raw)
        if v ~= nil then
          reportShortChat(v, "g9-gui export shortHealChatEnabled()=" .. tostring(raw))
          return v
        end
      end
    end
    -- channel 2: the persisted option row off the live save
    local okGame, Game = pcall(require, "src.core.Game")
    if okGame and type(Game) == "table" and type(Game.save) == "table" then
      local opts = Game.save.options
      local buckets = opts and opts.modOptions
      local bucket = buckets and buckets["g9-gui"]
      local raw = bucket and bucket.short_heal_chat
      local v = coerceOnOff(raw)
      if v ~= nil then
        reportShortChat(v, "save modOptions['g9-gui'].short_heal_chat=" .. tostring(raw))
        return v
      end
    end
    -- neither channel answered: keep the historical default.
    reportShortChat(true, "no g9-gui value found; default ON")
    return true
  end
  mod.exports.pokecenterShortChatEnabled = shortChatEnabled

  local function faceSouth(player)
    if player then player.facing = "down" end
  end

  -- =====================================================================
  -- Gen 1
  -- =====================================================================
  local function gen1SetLastHeal(self)
    local Game = liveGame()
    if not (Game and Game.save) then return end
    Game.save.lastHeal = {
      map = self.map and self.map.id,
      x = self.player and self.player.cellX,
      y = self.player and self.player.cellY,
      outdoor = self.lastOutdoor
        and { id = self.lastOutdoor.id, x = self.lastOutdoor.x, y = self.lastOutdoor.y }
        or nil,
    }
  end

  local function gen1Finish(self, onDone, npc)
    if npc then pcall(function() npc:facePlayer(self.player) end) end
    faceSouth(self.player)
    if onDone then onDone() end
  end

  local function gen1ShortFlow(self, onDone, npc)
    local Game = liveGame()
    local TextBox = require("src.render.TextBox")
    healParty(Game, false)
    gen1SetLastHeal(self)
    Game.stack:push(TextBox.new(Game, Strings(ROUTE_ONE), function()
      gen1Finish(self, onDone, npc)
    end))
  end

  -- Toggle OFF: the vanilla chat, reproduced from the ROM strings, minus the
  -- machine and plus the modern heal. Left/right/up/down keep the original
  -- wording and the HEAL / CANCEL box.
  local function gen1VanillaFlow(self, onDone, npc)
    local Game = liveGame()
    local Theme = require("src.ui.Theme")
    local TextBox = require("src.render.TextBox")
    local t = (Game and Game.data and Game.data.text) or {}
    local bye = t._PokemonCenterFarewellText or Strings("We hope to see\nyou again!")
    local hello = t._PokemonCenterWelcomeText or Strings("Welcome to our\nPOKEMON CENTER!")
    if Game and Game.save and not Game.save.usedPokecenter then
      Game.save.usedPokecenter = true
      hello = hello .. "\f"
        .. (t._ShallWeHealYourPokemonText or Strings("Shall we heal your\nPOKeMON?"))
    end
    Game.stack:push(TextBox.new(Game, hello, nil, {
      choice = function(yes)
        if not yes then
          Game.stack:push(TextBox.new(Game, bye, function()
            gen1Finish(self, onDone, npc)
          end))
          return
        end
        healParty(Game, false)
        gen1SetLastHeal(self)
        local need = t._NeedYourPokemonText or Strings("OK. We'll need\nyour POKeMON.")
        Game.stack:push(TextBox.new(Game, need, function()
          local fit = t._PokemonFightingFitText or Strings("Your POKeMON are\nfighting fit!")
          Game.stack:push(TextBox.new(Game, fit, function()
            Game.stack:push(TextBox.new(Game, bye, function()
              gen1Finish(self, onDone, npc)
            end))
          end))
        end))
      end,
      choiceLabels = { Strings("HEAL"), Strings("CANCEL") },
      choiceBox = Theme.healCancelBox,
    }))
  end

  local function installGen1()
    local ok, OverworldState = pcall(require, "src.world.OverworldController")
    if not (ok and type(OverworldState) == "table") then
      mod.log:warn("g9-battle-engine: pokecenter_heal: OverworldController unavailable, skipped")
      return
    end
    local baseNurseHeal = OverworldState.nurseHeal
    if type(baseNurseHeal) ~= "function" or OverworldState.__g9PokecenterHeal then
      return
    end
    OverworldState.__g9PokecenterHeal = true

    function OverworldState:nurseHeal(onDone, npc)
      local flow = gen1VanillaFlow
      if shortChatEnabled() then flow = gen1ShortFlow end
      local okRun, err = pcall(flow, self, onDone, npc)
      if okRun then return end
      mod.log:warn("g9-battle-engine: pokecenter_heal: Gen 1 nurse flow failed: %s",
        tostring(err))
      -- Never leave the interaction stuck: our flow failed before it could
      -- hand control back, so close it out.
      pcall(function() self.player.facing = "down" end)
      if onDone then pcall(onDone) end
    end
  end

  -- =====================================================================
  -- Gen 2
  -- =====================================================================
  local function spriteName(world, npc)
    local sprite = npc and npc.def and npc.def.sprite
    if type(sprite) == "string" then return sprite end
    if type(sprite) == "number" then
      local order = world and world.constants and world.constants.spriteOrder
      return order and order[sprite] or nil
    end
    return nil
  end

  local function scriptMentionsNurse(world, npc)
    local key = npc and npc.def and npc.def.scriptKey
    if not key then return false end
    local std = world and world.stdScripts and world.stdScripts.scripts
      and world.stdScripts.scripts.PokecenterNurseScript
    local stdKey = std and std.key
    if stdKey and key == stdKey then return true end
    local rows = world and world.scripts and world.scripts[key]
    for _, cmd in ipairs(rows or {}) do
      if cmd.std == "PokecenterNurseScript" then return true end
      if stdKey and cmd.script == stdKey then return true end
    end
    return false
  end

  local function isNurseNpc(world, npc)
    if spriteName(world, npc) == "SPRITE_NURSE" then return true end
    return scriptMentionsNurse(world, npc)
  end
  mod.exports.pokecenterIsNurseNpc = isNurseNpc

  -- The std script's OWN rows (the cart's PokecenterNurseScript body). The map
  -- object's scriptKey points at a per-map `jumpstd` stub, so the full body is
  -- reached through world.stdScripts.
  local function nurseScriptRows(world, npc)
    local std = world and world.stdScripts and world.stdScripts.scripts
      and world.stdScripts.scripts.PokecenterNurseScript
    local stdKey = std and std.key
    if stdKey and world.scripts and world.scripts[stdKey] then
      return world.scripts[stdKey]
    end
    local key = npc and npc.def and npc.def.scriptKey
    return key and world.scripts and world.scripts[key] or nil
  end

  -- The pokerus report is the LAST writetext in the script body (the cart's
  -- `.pokerus` arm), so its decoded ROM text is reused verbatim.
  local function pokerusBody(world, npc)
    local text = (world and world.text) or {}
    local body
    for _, cmd in ipairs(nurseScriptRows(world, npc) or {}) do
      if (cmd.op == "writetext" or cmd.op == "jumptext") and cmd.text then
        body = text[cmd.text] or body
      end
    end
    return body
  end

  local function pokerusPending(world)
    local save = world and world.game and world.game.save
    if not save then return false end
    if world.engineFlag and world:engineFlag("ENGINE_CAUGHT_POKERUS") then return false end
    -- checkphonecall: a queued special call means Elm's call is already on its
    -- way, so the nurse must not repeat the report.
    if world.specialCall and (world:specialCall() or 0) ~= 0 then return false end
    local ok, Pokerus = pcall(require, "src.core.gen2.Pokerus")
    if not (ok and type(Pokerus) == "table" and type(Pokerus.inParty) == "function") then
      return false
    end
    local ok2, infected = pcall(Pokerus.inParty, save.party)
    return ok2 and infected and true or false
  end

  -- The cart's .pokerus arm: report, setflag ENGINE_CAUGHT_POKERUS, then
  -- specialphonecall SPECIALCALL_POKERUS -- in that order, after the text.
  local function reportPokerus(world)
    if world.setEngineFlag then pcall(world.setEngineFlag, world, "ENGINE_CAUGHT_POKERUS", true) end
    if world.setSpecialCall then
      local id = 1
      local ok, Phone = pcall(require, "src.core.gen2.Phone")
      if ok and type(Phone) == "table" and type(Phone.SPECIAL_CALLS) == "table" then
        for k, row in pairs(Phone.SPECIAL_CALLS) do
          if type(row) == "table" and row.name == "SPECIALCALL_POKERUS" then id = k break end
        end
      end
      pcall(world.setSpecialCall, world, id)
    end
  end

  local function runGen2ShortFlow(world, npc)
    -- Heal first and silently: the balls-in-the-machine beat is gone.
    healParty(world.game, true)
    if npc and npc.facePlayer and world.player then pcall(npc.facePlayer, npc, world.player) end

    local function finish()
      if npc then pcall(function() npc.frozen = false end) end
      faceSouth(world.player)
    end

    if pokerusPending(world) then
      world:showText(pokerusBody(world, npc) or Strings(POKERUS_FALLBACK), function()
        reportPokerus(world)
        world:showText(Strings(ROUTE_ONE), finish)
      end)
    else
      world:showText(Strings(ROUTE_ONE), finish)
    end
  end

  local function installGen2()
    local okWorld, World = pcall(require, "src.world.gen2.World")

    -- Modern heal replaces World:healParty so EVERY caller (the nurse script,
    -- a whiteout, anything else) gets the modern max.
    if okWorld and type(World) == "table" and type(World.healParty) == "function"
        and not World.__g9PokecenterHeal then
      World.__g9PokecenterHeal = true
      local baseHealParty = World.healParty
      function World:healParty()
        local okRun, err = pcall(healParty, self and self.game, true)
        if okRun then return end
        mod.log:warn("g9-battle-engine: pokecenter_heal: Gen 2 healParty failed: %s",
          tostring(err))
        return baseHealParty(self)
      end
    end

    -- The pokeball placement beat is skipped outright by resuming instantly.
    if okWorld and type(World) == "table" and type(World.startHealMachineAnim) == "function"
        and not World.__g9PokecenterHealAnim then
      World.__g9PokecenterHealAnim = true
      function World:startHealMachineAnim(_animType, onDone)
        if onDone then onDone() end
      end
    end

    local okOc, OverworldController = pcall(require, "src.world.OverworldController")
    if not (okOc and type(OverworldController) == "table") then
      mod.log:warn("g9-battle-engine: pokecenter_heal: OverworldController facade unavailable, skipped")
      return
    end
    if OverworldController.__g9PokecenterHeal then return end
    OverworldController.__g9PokecenterHeal = true

    -- Set when a toggle-OFF nurse conversation has been left to the cart's own
    -- script; the update watcher below faces the player south once it settles.
    local pendingFaceSouth = nil

    OverworldController.talkTo = function(world, npc)
      if not isNurseNpc(world, npc) then return false end
      if shortChatEnabled() then
        local okRun, err = pcall(runGen2ShortFlow, world, npc)
        if okRun then return true end
        mod.log:warn("g9-battle-engine: pokecenter_heal: Gen 2 short flow failed, "
          .. "falling back to the native script: %s", tostring(err))
        return false
      end
      -- Toggle OFF: let the cart's own script run; watch for it to settle.
      pendingFaceSouth = world
      return false
    end

    -- Gen2Compat.worldTick calls this from World:step's tail (the one per-frame
    -- seam Gold offers a mod). World:busy() is false only once the script, its
    -- text boxes and any pending movement have all finished.
    OverworldController.update = function(world, _dt)
      if pendingFaceSouth ~= world then return end
      if not world.busy or world:busy() then return end
      pendingFaceSouth = nil
      faceSouth(world.player)
    end
  end

  if IS_GEN2 then installGen2() else installGen1() end

  mod.log:info("g9-battle-engine: pokecenter_heal installed (%s; modern-max full heal, "
    .. "pokeball machine skipped, player faces south when done, pokerus report preserved; "
    .. "short chat follows the g9-gui SHORT HEAL CHAT option)",
    IS_GEN2 and "Gen 2" or "Gen 1")
end
