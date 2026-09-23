-- Egg normalization (round 279, engine 4.4.0) -- an EGG is a Pokemon, and it
-- must load like one.
--
-- THE GAP. A Gen 2 egg is a real mon record whose species is hidden behind
-- `mon.isEgg = true` (src/core/gen2/Breeding.lua's own flag: the cart keeps the
-- species and only PRINTS "EGG"). The engine already keeps eggs out of every
-- battle path (Battle.new/BattleState pick checks, the party menu's own
-- `PartyMenuCheckEgg` routines, LinkBattle/TeamPick/Trade refusals), and
-- src/core/gen2/Boxes.lua pins a boxed egg's HP back to 0 -- but nothing ever
-- gave an egg the MODERN fields every other mon in this engine carries:
--   * no `mon.nature`      (ModernStats.generateNature owns it)
--   * no `mon.ability`     (ModernStats.generateAbility owns it)
--   * no IVs / EVs of its own -- save_scrub.lua's ModernStats.ensure would
--     derive a legacy egg's IVs/EVs from its DVs on a save load, but an egg
--     created during play (day-care, gift, ODD EGG) carried none at all, and
--     an egg's statExp is zero, so `ensure` answered a flat 0/0/0/0/0/0 = 0
--     for half the fields rather than a real roll
--   * no shared NAME. The cart's own nickname is literally `Breeding.EGG_NAME`
--     ("EGG"), the ODD EGG names itself "ODD", and Gold's party menu never
--     reads the nickname for an egg at all (PartyMenu.rowFor returns
--     Strings(EGG_LABEL) outright) -- so an egg could present three different
--     names depending on the screen. Explicit user rule: EVERY egg, whatever
--     species it is hiding, is named "egg".
--
-- THE RULE THIS FILE ENFORCES. Every egg, wherever it is found, is normalized
-- exactly once into a real Pokemon record that happens to be unhatched:
-- nature generated, ability generated, IVs generated, EVs initialized to zero,
-- the name "egg", and HP pinned to 0 -- an egg is a FAINTED Pokemon for every
-- battle purpose (it cannot be sent out, it cannot be dragged into a battle,
-- and its HP never reads as alive). The species stays untouched: it is the
-- hatchling's species and the whole point of an egg.
--
-- WHERE IT LOOKS (all of it, so no creation path can slip past):
--   1. `save.loaded`  -- the save's party, every box, and the day-care slots
--                        (Mon.eachSaveMon's exact set).
--   2. `game.ready`   -- the same walk on a boot that never emitted save.loaded
--                        (a brand-new game, a checkpoint restore).
--   3. `battle.started` -- the live player party, so an egg handed over
--                        mid-session is real before the next battle ends.
--   4. Breeding.makeEgg  -- the day-care egg, normalized the moment it is built.
--   5. World:giveEgg     -- the scripted gift egg (Togepi).
--   6. Mon.stampOT       -- the ODD EGG (and any other path that stamps OT on a
--                        record marked `isEgg` before it reaches the party).
-- The modern fields are IDEMPOTENT by construction (initialize keeps existing
-- IVs, generateNature/generateAbility only fill a nil), so a re-run can never
-- re-roll anything the player has already seen; only the name and the zero HP
-- are re-asserted every pass, which is what makes the rule absolute.
--
-- WHY NOT save_scrub.lua. That file's job is the SAVE's own validation pass and
-- it must stay generation-agnostic (it runs on Gen 1 too, where eggs do not
-- exist); it also derives fields from a legacy record rather than generating
-- fresh ones, which is the opposite of what a newly-laid egg needs. Eggs need
-- their own home, and this is it.
return function(mod)
  local ModernStats = mod.exports.ModernStats
  if type(ModernStats) ~= "table" then return end

  -- Explicit user rule: every egg is named "egg", whatever species it hides.
  local EGG_NAME = "egg"

  -- src.core.gen2.Breeding is a Gen 2 module. A Gen 1 boot must not require it
  -- (the engine's RequireGuard throws for a Gold module on Red/Blue/Yellow), so
  -- it is pcall'd and every use below tolerates its absence. On Gen 1 there is
  -- simply nothing to do -- eggs do not exist before Gold.
  local Breeding
  do
    local ok, b = pcall(require, "src.core.gen2.Breeding")
    Breeding = ok and type(b) == "table" and b or nil
  end

  local function isEgg(mon)
    if type(mon) ~= "table" then return false end
    if Breeding and type(Breeding.isEgg) == "function" then
      local ok, v = pcall(Breeding.isEgg, mon)
      if ok then return v and true or false end
    end
    return mon.isEgg == true
  end

  -- national_dex is a hard dependency of this mod (manifest.json) and the real
  -- base-stat/ability source of truth; the same lookup gen2_modern_stats.lua
  -- makes, for the same reason.
  local function nationalDexExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  -- Writes computeAll's {hp,attack,defense,speed,spa,spd} into BOTH this mod's
  -- own spa/spd keys and Gen 2's native specialAttack/specialDefense names --
  -- the exact dual write gen2_modern_stats.lua's applyComputedStats performs,
  -- for the exact same reason (Gen 2's own combat/TrainerAI read the native
  -- names, this mod's screens read spa/spd).
  local function applyStats(mon, computed)
    mon.stats = mon.stats or {}
    mon.stats.hp = computed.hp
    mon.stats.attack = computed.attack
    mon.stats.defense = computed.defense
    mon.stats.speed = computed.speed
    mon.stats.specialAttack = computed.spa
    mon.stats.specialDefense = computed.spd
    mon.stats.spa = computed.spa
    mon.stats.spd = computed.spd
    mon.maxHp = computed.hp
  end

  -- The one normalizer. Idempotent: everything expensive is behind the
  -- `g9EggNormalized` stamp (which rides in the save like every other modern
  -- field), and the two things that must hold ABSOLUTELY -- the name and the
  -- zero HP -- are re-asserted on every call, stamp or not, so a screen cannot
  -- resurrect either one.
  local function normalize(mon)
    if not isEgg(mon) then return false end
    mon.nickname = EGG_NAME
    mon.name = EGG_NAME
    mon.hp = 0
    if mon.g9EggNormalized then return true end

    -- IVs generated (a genuinely missing key is rolled 0-31; a legacy egg whose
    -- IVs save_scrub.lua already derived from its DVs keeps them) and EVs
    -- initialized to 0. initialize's own contract.
    ModernStats.initialize(mon)
    -- "A pokemon must always have an ability" -- the species' non-hidden slots,
    -- 50/50, exactly as every other mon in this engine generates one.
    ModernStats.generateAbility(mon,
      ModernStats.resolveAbilities(mon.species, nationalDexExports()))
    ModernStats.generateNature(mon)

    -- Stats from those modern fields, so an egg reads coherently in any screen
    -- that shows numbers. A species with no resolvable base stats (no
    -- national_dex and no local record) simply keeps the stats Mon.new gave it.
    local def = ModernStats.resolveBase(mon.species, nil, nationalDexExports())
    if type(def) == "table" and type(def.baseStats) == "table" then
      applyStats(mon, ModernStats.computeAll(def.baseStats, mon.ivs or {},
        mon.evs or {}, mon.level, mon.nature))
    end

    -- An egg is a FAINTED Pokemon: the cart carries it at zero HP and so does
    -- this record, whatever the stats pass above just computed for maxHp.
    mon.hp = 0
    mon.g9EggNormalized = true
    return true
  end

  -- Every mon a save holds: Mon.eachSaveMon's own set (party, every box, and the
  -- day-care slots), so an egg waiting in the day care is real before it is ever
  -- handed over.
  local function eggsInSave(save, fn)
    if type(save) ~= "table" then return end
    for _, mon in ipairs(save.party or {}) do fn(mon) end
    for _, box in pairs(save.boxes or {}) do
      if type(box) == "table" then
        for _, mon in ipairs(box) do fn(mon) end
      end
    end
    local dc = save.dayCare
    if type(dc) == "table" then
      if dc.man and dc.man.mon then fn(dc.man.mon) end
      if dc.lady and dc.lady.mon then fn(dc.lady.mon) end
      if dc.egg then fn(dc.egg) end
    end
    if type(save.daycare) == "table" and save.daycare.mon then
      fn(save.daycare.mon)
    end
  end

  local function sweepSave(save)
    return eggsInSave(save, function(mon) pcall(normalize, mon) end)
  end

  local function sweepList(list)
    if type(list) ~= "table" then return end
    for _, mon in ipairs(list) do pcall(normalize, mon) end
  end

  -- ---------------------------------------------------------------- the hooks

  mod.events:on("save.loaded", function(ev)
    local save = ev and ev.save
    local ok, err = pcall(sweepSave, save)
    if not ok then
      mod.log:warn("g9-battle-engine: egg_normalize: save.loaded failed: %s",
        tostring(err))
    end
  end)

  mod.events:on("game.ready", function(ev)
    local game = ev and ev.game
    local ok, err = pcall(sweepSave, game and game.save)
    if not ok then
      mod.log:warn("g9-battle-engine: egg_normalize: game.ready failed: %s",
        tostring(err))
    end
  end)

  -- The live player party. Gen 2's `battle.party` IS `save.party`, and Gen 1 has
  -- no eggs at all, so this is one walk that is a no-op on Gen 1.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if type(battle) ~= "table" then return end
    local ok, err = pcall(function()
      sweepList(battle.party)
      sweepList(battle.enemyParty)
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: egg_normalize: battle.started failed: %s",
        tostring(err))
    end
  end)

  -- The day-care egg: normalized the moment the one builder returns it, so it is
  -- already real by the time the Day-Care Man hands it over.
  if Breeding and type(Breeding.makeEgg) == "function"
      and not Breeding.__g9EggNormalize then
    Breeding.__g9EggNormalize = true
    local baseMakeEgg = Breeding.makeEgg
    Breeding.makeEgg = function(...)
      local egg = baseMakeEgg(...)
      if isEgg(egg) then pcall(normalize, egg) end
      return egg
    end
  end

  -- The scripted gift egg (World:giveEgg, the Togepi egg) writes its own
  -- nickname and its own HP=0 and appends straight to the party, so it is
  -- normalized right after the write. Unlike makeEgg it has no single builder
  -- wrapper of its own (it calls Mon.new itself).
  do
    local ok, World = pcall(require, "src.world.gen2.World")
    if ok and type(World) == "table" and type(World.giveEgg) == "function"
        and not World.__g9EggNormalize then
      World.__g9EggNormalize = true
      local baseGiveEgg = World.giveEgg
      World.giveEgg = function(self, speciesIndex, level)
        local res = baseGiveEgg(self, speciesIndex, level)
        if res then
          local game = self and self.game
          local save = game and game.save
          local party = save and save.party
          local mon = party and party[#party]
          if mon then pcall(normalize, mon) end
        end
        return res
      end
    end
  end

  -- `Mon.stampOT(save, mon)` is the last thing every OTHER party write does
  -- (move_mon.asm TryAddMonToParty), and both the ODD EGG builder and
  -- World:giveEgg stamp it AFTER marking the record `isEgg`, so it is the one
  -- seam that catches an egg arriving by any other route. Non-eggs fall out on
  -- the first line, so the cost on a normal party add is one table check.
  do
    local ok, Mon = pcall(require, "src.battle.gen2.Mon")
    if ok and type(Mon) == "table" and type(Mon.stampOT) == "function"
        and not Mon.__g9EggNormalize then
      Mon.__g9EggNormalize = true
      local baseStampOT = Mon.stampOT
      Mon.stampOT = function(save, mon)
        local res = baseStampOT(save, mon)
        if isEgg(mon) then pcall(normalize, mon) end
        return res
      end
    end
  end

  -- The NAME, at the one screen that ignores it. Gold's party list hardcodes
  -- the cart's own EGG label for an egg (PartyMenu.rowFor returns
  -- Strings(EGG_LABEL) without ever reading the nickname), so without this the
  -- row would read "EGG" while every other screen in the game reads "egg". The
  -- row is otherwise exactly the engine's own -- an egg keeps its icon and its
  -- missing HP/level columns, by the engine's own PartyMenuCheckEgg rule.
  do
    local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
    if ok and type(PartyMenu) == "table"
        and type(PartyMenu.rowFor) == "function"
        and not PartyMenu.__g9EggRow then
      PartyMenu.__g9EggRow = true
      local baseRowFor = PartyMenu.rowFor
      PartyMenu.rowFor = function(mon, hp, statuses)
        local row = baseRowFor(mon, hp, statuses)
        if type(row) == "table" and isEgg(mon) then
          row.name = mon.nickname or mon.name or EGG_NAME
        end
        return row
      end
    end
  end

  mod.log:info("g9-battle-engine: egg_normalize installed (eggs get a nature, "
    .. "an ability, IVs, EVs, the name \"egg\" and 0 HP on every load)")
end
